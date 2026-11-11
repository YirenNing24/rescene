package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
)

type publicationStore interface {
	claimPublication(string, time.Time) (publicationJob, bool, error)
	savePublication(publicationJob, time.Time) error
	backfillPublications(string) error
	publicationFor(string, string, string) (*publicationJob, error)
}
type publicationService struct {
	store  publicationStore
	client *publicationClient
	target string
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	ready  bool
}

func startPublicationService(store userStore, cfg config) (*publicationService, error) {
	if !cfg.LeaderboardEnabled {
		return nil, nil
	}
	if err := validatePublisherConfig(cfg); err != nil {
		return nil, err
	}
	ps, ok := store.(publicationStore)
	if !ok {
		return nil, errors.New("leaderboard publication storage unavailable")
	}
	ctx, cancel := context.WithCancel(context.Background())
	service := &publicationService{store: ps, client: newPublicationClient(cfg), target: publicationTarget(cfg), ctx: ctx, cancel: cancel}
	if err := ps.backfillPublications(service.target); err != nil {
		cancel()
		return nil, err
	}
	service.wg.Add(1)
	go service.run()
	return service, nil
}
func (s *publicationService) close() error {
	if s != nil {
		s.cancel()
		s.wg.Wait()
	}
	return nil
}
func (s *publicationService) run() {
	defer s.wg.Done()
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for {
		if s.ctx.Err() != nil {
			return
		}
		if err := s.process(); err != nil {
			log.Print("leaderboard publisher: " + err.Error())
		}
		select {
		case <-s.ctx.Done():
			return
		case <-tick.C:
		}
	}
}
func (s *publicationService) process() error {
	if !s.ready {
		if err := s.client.preflight(s.ctx); err != nil {
			return err
		}
		s.ready = true
		log.Printf("leaderboard publisher connected: project=%s chain=%d contract=%s", s.client.cfg.EngineProjectID, s.client.cfg.LeaderboardChainID, s.client.cfg.LeaderboardAddress)
	}
	j, ok, err := s.store.claimPublication(s.target, time.Now())
	if err != nil {
		return errors.New("publication_storage_unavailable")
	}
	if !ok {
		return nil
	}
	next := time.Now().Add(3 * time.Second)
	err = s.advance(&j, &next)
	if err != nil {
		j.ErrorCode = err.Error()
		next = time.Now().Add(15 * time.Second)
	}
	if saveErr := s.store.savePublication(j, next); saveErr != nil {
		return errors.New("publication_storage_unavailable")
	}
	return err
}
func (s *publicationService) advance(j *publicationJob, next *time.Time) error {
	p := s.client
	ctx := s.ctx
	processed, err := p.processed(ctx, *j)
	if err != nil {
		return err
	}
	if processed {
		confirmed, err := p.confirmed(ctx, *j)
		if err != nil || !confirmed {
			hash, findErr := p.findPublished(ctx, j)
			if findErr != nil {
				return findErr
			}
			j.TxHash = hash
			confirmed, err = p.confirmed(ctx, *j)
			if err != nil {
				return err
			}
		}
		if confirmed {
			j.Status = "confirmed"
			j.ErrorCode = ""
			*next = time.Now().Add(5 * time.Minute)
		} else {
			j.Status = "confirming"
		}
		return nil
	}
	if j.Status == "confirmed" || j.Status == "confirming" {
		j.Generation++
		j.EngineID = ""
		j.TxHash = ""
		j.Status = "pending"
	}
	if j.EngineID != "" {
		transaction, err := p.transaction(ctx, *j)
		if err != nil {
			return err
		}
		if transaction.Hash != "" {
			j.TxHash = transaction.Hash
		}
		switch transaction.Status {
		case "failed":
			j.Generation++
			j.EngineID = ""
			j.TxHash = ""
			j.Status = "retrying"
			*next = time.Now().Add(time.Minute)
			j.ErrorCode = "engine_transaction_failed"
		case "confirmed":
			head, err := p.head(ctx)
			if err != nil {
				return err
			}
			if head-j.FromBlock > 512 {
				j.Generation++
				j.EngineID = ""
				j.TxHash = ""
				j.Status = "retrying"
			} else {
				j.Status = "submitted"
			}
		case "queued", "signing", "submitted", "retrying":
			j.Status = "submitted"
		default:
			return errors.New("engine_status_invalid")
		}
		return nil
	}
	if err = s.ensureBoard(*j); err != nil {
		return err
	}
	if j.FromBlock == 0 {
		j.FromBlock, err = p.head(ctx)
		if err != nil {
			return err
		}
		// Release the job with its scan boundary persisted. POST starts on the next claim.
		return nil
	}
	tx, err := p.enqueue(ctx, fmt.Sprintf("rescene/%s/%d", j.Key, j.Generation), "submitScore", submitScoreABI, scoreArgs(*j))
	if err != nil {
		return err
	}
	j.EngineID = tx.ID
	j.TxHash = tx.Hash
	j.Status = "submitted"
	j.ErrorCode = ""
	return nil
}
func (s *publicationService) ensureBoard(j publicationJob) error {
	p := s.client
	b := j.Payload
	data, err := p.ethCall(s.ctx, selector("boards(bytes32)")+strings.TrimPrefix(b.BoardID, "0x"))
	if err != nil {
		return err
	}
	units, err := wordInt(data, 0)
	if err != nil {
		return err
	}
	if units == 0 {
		difficulty := map[string]int{"Easy": 0, "Normal": 1, "Hard": 2, "Ultra Hard": 3}[b.Difficulty]
		args := []string{b.SongID, strconv.Itoa(difficulty), "0x" + strings.TrimPrefix(b.Revision, "0x"), strconv.Itoa(b.Units)}
		tx, err := p.enqueue(s.ctx, "rescene/chart/"+hashHex([]byte(s.target))+"/"+b.BoardID, "registerBoard", registerBoardABI, args)
		if err != nil {
			return err
		}
		if tx.Status == "failed" {
			return errors.New("chart_registration_failed")
		}
		return errors.New("chart_registration_pending")
	}
	if units != int64(b.Units) {
		return errors.New("chart_units_mismatch")
	}
	enabled, err := wordInt(data, 2)
	if err != nil {
		return err
	}
	if enabled != 1 {
		return errors.New("chart_publication_disabled")
	}
	return nil
}
func (a *api) getPublication(c fiber.Ctx) error {
	cfg := a.config
	if !cfg.LeaderboardEnabled {
		return c.JSON(fiber.Map{"publication": fiber.Map{"status": "not_configured"}})
	}
	chart, ok := rewardCharts[c.Query("song_id")+"/"+c.Query("difficulty")]
	if !ok {
		return failure(c, 400, "invalid_chart", "Choose an available song and difficulty.")
	}
	board, err := chartBoardKey(chart.SongID, chart.Difficulty, chart.Revision)
	if err != nil {
		return err
	}
	store, ok := a.store.(publicationStore)
	if !ok {
		return failure(c, 503, "unavailable", "Score publication is unavailable.")
	}
	job, err := store.publicationFor(publicationTarget(cfg), c.Locals("user").(user).ID, board)
	if err != nil {
		return err
	}
	result := publicationView(cfg, job)
	return c.JSON(fiber.Map{"publication": result})
}
func publicationView(cfg config, job *publicationJob) fiber.Map {
	result := fiber.Map{"status": "not_published", "chain_id": cfg.LeaderboardChainID, "contract_address": cfg.LeaderboardAddress}
	if job != nil {
		result["status"], result["score"], result["max_combo"], result["transaction_hash"], result["retrying"] = job.Status, job.Payload.Score, job.Payload.MaxCombo, job.TxHash, job.ErrorCode != ""
	}
	return result
}
