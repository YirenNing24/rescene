package main

import (
	"context"
	"errors"
	"github.com/gofiber/fiber/v3"
	"log"
	"strconv"
	"strings"
	"sync"
	"time"
)

type starlightStore interface {
	claimStarlight(string, time.Time) (starlightJob, bool, error)
	saveStarlight(starlightJob, time.Time) error
	backfillStarlight(config) error
	pendingStarlight(string, string) (int64, error)
	ReadWallet(string, string, string) (walletInfo, error)
}
type starlightService struct {
	demand chainDemand
	store  starlightStore
	client *starlightClient
	target string
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	ready  bool
}

func startStarlightService(store userStore, c config) (*starlightService, error) {
	if !c.StarlightEnabled {
		return nil, nil
	}
	if err := validateStarlightConfig(c); err != nil {
		return nil, err
	}
	db, ok := store.(starlightStore)
	if !ok {
		return nil, errors.New("Starlight storage unavailable")
	}
	if err := db.backfillStarlight(c); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &starlightService{demand: newChainDemand(), store: db, client: newStarlightClient(c), target: starlightTarget(c), ctx: ctx, cancel: cancel}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
func (s *starlightService) close() error {
	if s != nil {
		s.cancel()
		s.wg.Wait()
	}
	return nil
}
func (s *starlightService) run() {
	defer s.wg.Done()
	runChainWorker(s.ctx, &s.demand, s.client.cfg.ChainBackgroundWorkers, func() {
		if err := s.process(); err != nil {
			log.Print("Reward delivery: " + err.Error())
		}
	})
}
func (s *starlightService) process() error {
	if s.client.p.rpcCoolingDown() {
		return nil
	}
	ctx, cancel := context.WithTimeout(s.ctx, 20*time.Second)
	defer cancel()

	j, ok, err := s.store.claimStarlight(s.target, time.Now())
	if err != nil {
		return errors.New("starlight_storage_unavailable")
	}
	if !ok {
		return nil
	}
	if j.Status == "confirmed" && !s.client.cfg.ChainBackgroundWorkers {
		return s.store.saveStarlight(j, time.Now().Add(24*time.Hour))
	}
	next := time.Now().Add(15 * time.Second)
	err = func() error {
		if !s.ready {
			if err := s.client.preflight(ctx); err != nil {
				return err
			}
			s.ready = true
			log.Printf("Reward delivery connected: chain=%d token=%s item=%t", s.client.cfg.StarlightChainID, s.client.cfg.StarlightToken, s.client.item)
		}
		return s.advance(ctx, &j, &next)
	}()
	if err != nil {
		j.ErrorCode = err.Error()
	}
	next = recoveryNext(&j.Recovery, err, next)
	if saveErr := s.store.saveStarlight(j, next); saveErr != nil {
		return errors.New("starlight_storage_unavailable")
	}
	if recoveryPending(err) {
		return nil
	}
	return err
}
func (s *starlightService) advance(ctx context.Context, j *starlightJob, next *time.Time) error {
	p := s.client
	c := p.cfg
	if j.Recipient == "" {
		wallet, err := s.store.ReadWallet(j.Owner, c.EngineProjectID, c.EngineURL)
		if err != nil {
			return errors.New("starlight_wallet_unavailable")
		}
		if wallet.Status != "ready" || !validHex(wallet.Address, 20) {
			return errors.New("starlight_wallet_pending")
		}
		j.Recipient = strings.ToLower(wallet.Address)
		if strings.EqualFold(j.Recipient, c.StarlightTreasury) || strings.EqualFold(j.Recipient, c.StarlightDistributor) {
			return errors.New("starlight_recipient_invalid")
		}
		j.FromBlock, err = p.p.head(ctx)
		return err // Persist destination and scan boundary before any POST.
	}
	if !validHex(j.Recipient, 20) || j.FromBlock <= 0 {
		return errors.New("starlight_job_invalid")
	}
	processed, err := p.processed(ctx, *j)
	if err != nil {
		return err
	}
	if processed {
		if !validHex(j.TxHash, 32) && j.EngineID != "" {
			hash, err := recoveryEngineHash(&j.Recovery, func() (enginePublicationTx, error) { return p.transaction(ctx, *j) })
			if err != nil {
				return err
			}
			j.TxHash = hash
		}
		confirmed, err := p.confirmed(ctx, *j)
		if err != nil && err.Error() != "starlight_receipt_mismatch" {
			return err
		}
		if !validHex(j.TxHash, 32) || err != nil {
			hash, findErr := p.findPaid(ctx, j)
			if findErr != nil {
				return findErr
			}
			j.TxHash = hash
			confirmed, err = p.confirmed(ctx, *j)
			if err != nil {
				return err
			}
		}
		j.Status = "confirming"
		j.ErrorCode = ""
		if confirmed {
			j.Status = "confirmed"
			*next = time.Now().Add(24 * time.Hour)
		}
		return nil
	}
	if j.Status == "confirmed" || j.Status == "confirming" {
		j.Recovery = recoveryState{}
		j.Generation++
		j.EngineID = ""
		j.TxHash = ""
		j.Status = "pending"
	}
	if j.EngineID != "" {
		tx, err := p.transaction(ctx, *j)
		if err != nil {
			return err
		}
		if tx.Hash != "" {
			j.TxHash = tx.Hash
		}
		switch tx.Status {
		case "failed":
			j.Generation++
			j.EngineID = ""
			j.TxHash = ""
			j.Status = "pending"
			j.ErrorCode = "starlight_transaction_failed"
			*next = time.Now().Add(time.Minute)
		case "queued", "signing", "submitted", "retrying", "confirmed":
			j.Status = "submitted"
		default:
			return errors.New("starlight_engine_status_invalid")
		}
		return nil
	}
	balance, err := p.balance(ctx, c.StarlightTreasury)
	if err != nil {
		return err
	}
	if balance.Cmp(p.raw(j.Amount)) < 0 {
		return errors.New("starlight_treasury_low")
	}
	approvalMethod := "allowance(address,address)"
	if p.item {
		approvalMethod = "isApprovedForAll(address,address)"
	}
	allowance, err := p.call(ctx, c.StarlightToken, selector(approvalMethod)+addressWord(c.StarlightTreasury)+addressWord(c.StarlightDistributor))
	if err != nil {
		return err
	}
	approved, err := uint256Hex(allowance)
	if err != nil {
		return err
	}
	if (!p.item && approved.Cmp(p.raw(j.Amount)) < 0) || (p.item && approved.Sign() == 0) {
		return errors.New("starlight_approval_required")
	}
	tx, err := p.enqueue(ctx, *j)
	if err != nil {
		return err
	}
	j.EngineID = tx.ID
	j.TxHash = tx.Hash
	j.Status = "submitted"
	j.ErrorCode = ""
	return nil
}
func (a *api) progressionView(p progression, now time.Time) fiber.Map {
	view := progressionView(p, now)
	view["events"] = eventsView(p, now)
	view["starlight_token"] = fiber.Map{"enabled": a.config.StarlightEnabled, "chain_id": a.config.StarlightChainID, "contract_address": a.config.StarlightToken, "symbol": "STARL", "decimals": 18}
	return view
}
func (a *api) getStarlight(c fiber.Ctx) error {
	if a.starlight != nil {
		defer a.starlight.demand.request()
	}
	if a.eventRewards != nil {
		defer a.eventRewards.demand.request()
	}
	if a.starlight == nil {
		return c.JSON(fiber.Map{"starlight": fiber.Map{"status": "not_configured"}})
	}
	s := a.starlight
	cfg := s.client.cfg
	owner := c.Locals("user").(user).ID
	wallet, err := s.store.ReadWallet(owner, cfg.EngineProjectID, cfg.EngineURL)
	if err != nil {
		return err
	}
	pending, err := s.store.pendingStarlight(s.target, owner)
	if err != nil {
		return err
	}
	view := fiber.Map{"status": "wallet_pending", "chain_id": cfg.StarlightChainID, "contract_address": cfg.StarlightToken, "symbol": "STARL", "decimals": 18, "wallet_address": wallet.Address, "pending": strconv.FormatInt(pending, 10)}
	if wallet.Status != "ready" {
		a.wallets.queue(owner)
		return c.JSON(fiber.Map{"starlight": view})
	}
	if !validHex(wallet.Address, 20) {
		return failure(c, 503, "wallet_unavailable", "Your wallet is temporarily unavailable.")
	}
	ctx, cancel := context.WithTimeout(c.Context(), 6*time.Second)
	defer cancel()
	balance, err := s.client.balance(ctx, wallet.Address)
	if err != nil {
		return failure(c, 503, "starlight_unavailable", "Your Starlight balance is updating. Please try again shortly.")
	}
	view["status"], view["balance"], view["balance_raw"], view["checked_at"] = "ready", formatStarlight(balance), balance.String(), time.Now().UTC().Format(time.RFC3339)
	return c.JSON(fiber.Map{"starlight": view})
}
