package main

import (
	"context"
	"errors"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"log"
	"strings"
	"sync"
	"time"
)

type shopStore interface {
	progressStore
	ReadWallet(string, string, string) (walletInfo, error)
	shopOperation(string, string) (*shopJob, error)
	claimShop(string) (shopJob, bool, error)
	saveShop(shopJob, time.Time) error
	finishShop(shopJob) error
}
type shopService struct {
	store  shopStore
	client *shopClient
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	ready  bool
}

func startShopService(store userStore, c config) (*shopService, error) {
	if !c.ShopEnabled {
		return nil, nil
	}
	db, ok := store.(shopStore)
	if !ok {
		return nil, errors.New("shop storage unavailable")
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &shopService{store: db, client: newShopClient(c), ctx: ctx, cancel: cancel}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
func (s *shopService) close() error {
	if s != nil {
		s.cancel()
		s.wg.Wait()
	}
	return nil
}
func (s *shopService) run() {
	defer s.wg.Done()
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for {
		if s.ctx.Err() != nil {
			return
		}
		if err := s.process(); err != nil {
			log.Print("shop worker: " + err.Error())
		}
		select {
		case <-s.ctx.Done():
			return
		case <-tick.C:
		}
	}
}
func (s *shopService) process() error {
	ctx, cancel := context.WithTimeout(s.ctx, 20*time.Second)
	defer cancel()
	if !s.ready {
		if err := s.client.preflight(ctx); err != nil {
			return err
		}
		if s.client.cfg.CardsEnabled && s.client.cfg.PulseRouter == "" {
			card, _ := s.client.forItem(s.client.itemIDs()[1])
			if err := card.preflight(ctx); err != nil {
				return err
			}
		}
		if s.client.cfg.PulseRouter != "" {
			if err := s.client.pulsePreflight(ctx); err != nil {
				return err
			}
		}
		s.ready = true
	}
	j, ok, err := s.store.claimShop(shopTarget(s.client.cfg))
	if err != nil {
		return errors.New("shop_storage_unavailable")
	}
	if !ok {
		return nil
	}
	err = s.advance(ctx, &j)
	if err == nil && (j.Status == "confirmed" || j.Status == "failed") {
		return s.store.finishShop(j)
	}
	next := time.Now().Add(2 * time.Second)
	if err != nil {
		j.Error = "Still processing. Your request is saved; please refresh shortly."
		next = time.Now().Add(15 * time.Second)
	} else {
		j.Error = ""
	}
	if saveErr := s.store.saveShop(j, next); saveErr != nil {
		return errors.New("shop_storage_unavailable")
	}
	return err
}
func (s *shopService) advance(ctx context.Context, j *shopJob) error {
	if pulseActive(*j) {
		return s.advancePulse(ctx, j)
	}
	itemID := j.ItemID
	if j.Router != "" && strings.EqualFold(j.Router, s.client.cfg.LegacyCardsRouter) && !strings.HasPrefix(itemID, "legacy_") {
		itemID = "legacy_" + itemID
	}
	c, err := s.client.forItem(itemID)
	if err != nil {
		return err
	}
	if j.Router != "" && !strings.EqualFold(j.Router, c.cfg.ShopRouter) {
		return errors.New("shop_order_router_changed")
	}
	processed, err := c.processed(ctx, *j)
	if err != nil {
		return err
	}
	if processed {
		// Approval/funding hashes are not purchase receipts.
		if j.Stage != "execute" {
			j.TxHash = ""
		}
		ok, err := c.confirmed(ctx, j)
		if err != nil {
			return err
		}
		if ok {
			j.Status = "confirmed"
			j.Error = ""
		}
		return nil
	}
	if j.EngineID != "" {
		tx, err := c.transaction(ctx, *j)
		if err != nil {
			return err
		}
		switch tx.Status {
		case "queued", "signing", "submitted", "retrying":
			return nil
		case "confirmed":
			j.EngineID = ""
			j.TxHash = ""
			j.Generation = 0
			switch j.Stage {
			case "gas":
				j.Stage = "approve"
			case "approve":
				j.Stage = "execute"
			default:
				return errors.New("shop_receipt_pending")
			}
			return nil // Persist stage before the next signed operation.
		case "failed":
			// A generic timeout may have succeeded on chain; processed() above prevents
			// a second charge/burn, and the router remains idempotent on all retries.
			j.Generation++
			j.EngineID = ""
			j.TxHash = ""
			return errors.New("shop_transaction_retrying")
		default:
			return errors.New("shop_engine_status_invalid")
		}
	}
	if j.Stage == "execute" && j.ExecuteStarted {
		// The previous POST may still be queued after its response was lost.
		// Recover its stable Engine ID before checking changing balances/stock;
		// never unlock the account while an execution is uncertain.
		tx, err := c.enqueue(ctx, *j)
		if err != nil {
			return err
		}
		j.EngineID, j.TxHash = tx.ID, tx.Hash
		return nil
	}
	switch j.Stage {
	case "gas":
		var raw string
		if err = c.star.p.rpc(ctx, "eth_getBalance", []any{j.Wallet, "latest"}, &raw); err != nil {
			return err
		}
		balance, ok := newBigQuantity(raw)
		if !ok {
			return errors.New("shop_gas_balance_invalid")
		}
		if balance.Cmp(gasThreshold) >= 0 {
			j.Stage = "approve"
			return nil
		}
	case "approve":
		ready := false
		if j.Kind == "buy" {
			allowance, err := c.number(ctx, c.cfg.StarlightToken, "allowance(address,address)", addressWord(j.Wallet)+addressWord(c.cfg.ShopRouter))
			if err != nil {
				return err
			}
			ready = allowance.Cmp(starlightRaw(int64(j.Quantity*c.price()))) >= 0
		} else {
			approved, err := c.number(ctx, c.cfg.MarketplaceCollection, "isApprovedForAll(address,address)", addressWord(j.Wallet)+addressWord(c.cfg.ShopRouter))
			if err != nil {
				return err
			}
			ready = approved.Sign() > 0
		}
		if ready {
			j.Stage = "execute"
			return nil
		}
	case "execute":
		if j.Kind == "buy" {
			listing, err := c.listing(ctx)
			if err != nil {
				j.Status = "failed"
				j.Error = "This listing changed. Nothing was purchased."
				return nil
			}
			balance, err := c.star.balance(ctx, j.Wallet)
			if err != nil {
				return err
			}
			if listing.Stock < int64(j.Quantity) || listing.End <= time.Now().Unix() || listing.Start > time.Now().Unix() || balance.Cmp(starlightRaw(int64(j.Quantity*c.price()))) < 0 {
				j.Status = "failed"
				j.Error = "The item is sold out or you no longer have enough STARL. Nothing was purchased."
				return nil
			}

		} else {
			progress, _, readErr := s.store.ReadProgress(j.Owner)
			if readErr != nil {
				return errors.New("shop_progression_unavailable")
			}
			progress.normalize(time.Now())
			if progress.Energy.Current >= energyCap {
				j.Status = "failed"
				j.Error = "Your energy recovered to full. Your drink was kept."
				return nil
			}
			owned, err := c.owned(ctx, j.Wallet)
			if err != nil {
				return err
			}
			if owned < 1 {
				j.Status = "failed"
				j.Error = "You no longer own an Energy Drink. No energy was added."
				return nil
			}
		}
		j.ExecuteStarted = true
		return nil // Persist execution intent before the first purchase/burn POST.
	default:
		return errors.New("shop_stage_invalid")
	}
	tx, err := c.enqueue(ctx, *j)
	if err != nil {
		return err
	}
	j.EngineID = tx.ID
	j.TxHash = tx.Hash
	return nil
}
func (a *api) shopWallet(c fiber.Ctx) (walletInfo, error) {
	wallet, err := a.shop.store.ReadWallet(c.Locals("user").(user).ID, a.config.EngineProjectID, a.config.EngineURL)
	if err != nil {
		return wallet, err
	}
	if wallet.Status != "ready" || !validHex(wallet.Address, 20) {
		return wallet, badProgress("Your wallet is getting ready. Please try again shortly.")
	}
	return wallet, nil
}
func (a *api) shopCatalog(c fiber.Ctx) error {
	if a.shop == nil {
		return c.JSON(fiber.Map{"catalog": []any{}, "checkout_enabled": false})
	}
	ctx, cancel := context.WithTimeout(c.Context(), 10*time.Second)
	defer cancel()
	block, on := int64(0), int64(0)
	if a.config.PulseRouter != "" {
		var e error
		block, e = a.shop.client.pulseBlock(ctx)
		if e != nil {
			return e
		}
		raw, e := a.shop.client.pulseRead(ctx, block, "salesEnabled()", "")
		if e != nil {
			return e
		}
		on, e = wordInt(raw, 0)
		if e != nil {
			return e
		}
	}
	if a.config.CardReleases {
		products, err := a.shop.client.releaseCatalog(ctx, block)
		if err != nil {
			return failure(c, 503, "catalog_unavailable", "The shop is updating. Please retry shortly.")
		}
		return releaseCatalogResponse(c, products)
	}
	ids := a.shop.client.itemIDs()
	products := make([]any, len(ids))
	errs := make([]error, len(ids))
	var wg sync.WaitGroup
	for index, id := range ids {
		wg.Go(func() {
			client, e := a.shop.client.forItem(id)
			if e != nil {
				errs[index] = e
				return
			}
			products[index], errs[index] = catalogProduct(ctx, client, block, on)
		})
	}
	wg.Wait()
	available := false
	for i, e := range errs {
		if e != nil {
			return failure(c, 503, "catalog_unavailable", "The shop is updating. Please retry shortly.")
		}
		available = available || products[i].(fiber.Map)["available"] == true
	}
	return c.JSON(fiber.Map{"catalog": products, "checkout_enabled": available})
}
func catalogProduct(ctx context.Context, client *shopClient, block, on int64) (fiber.Map, error) {
	product := client.itemView()
	product["price"], product["currency"], product["price_raw"] = client.price(), "STARL", starlightRaw(int64(client.price())).String()
	if client.cfg.PulseRouter != "" && client.isCard() && !client.legacy() {
		card, _ := cardByID(client.itemID)
		raw, e := client.pulseRead(ctx, block, "initialLESold(uint256)", hexWord(card.TokenID-6))
		if e != nil {
			return nil, e
		}
		sold, e := wordInt(raw, 0)
		if e != nil {
			return nil, e
		}
		product["initial_allocation"], product["initial_sold"], product["stock"] = 50, sold, max(int64(0), 50-sold)
		product["artwork_may_be_reissued"], product["admin_issuance_outside_allocation"] = true, true
		product["available"], product["max_quantity"], product["generation"], product["set_id"] = on == 1 && sold < 50, 1, "individual_randomized", cardReleaseFor(card).SetID
		delete(product, "token_id")
		product["drop_rates"] = map[string]any{"rarity": "LE", "score_percent_values": []int{7, 8, 9, 10}, "recovery_rating_values": []int{7, 8, 9, 10}, "each_stat_value_chance_bp": 2500, "skill_chance_bp": 10000, "skill_ids": []int{1, 2, 3, 4, 5, 6}, "skill_weights": []int{1, 1, 1, 1, 1, 1}}
		return product, nil
	}
	if client.cfg.PulseRouter != "" && client.isMaterial() {
		raw, e := client.pulseRead(ctx, block, "materialStock(uint256)", hexWord(client.cfg.ShopTokenID))
		if e != nil {
			return nil, e
		}
		stock, e := wordInt(raw, 0)
		if e != nil {
			return nil, e
		}
		product["stock"], product["available"], product["max_quantity"] = stock, on == 1 && stock > 0, 10
		return product, nil
	}
	listing, e := client.listing(ctx)
	if e != nil {
		return nil, e
	}
	now := time.Now().Unix()
	product["stock"], product["available"], product["max_quantity"], product["listing_id"] = listing.Stock, listing.Stock > 0 && listing.Start <= now && listing.End > now, 10, fmt.Sprint(client.cfg.ShopListingID)
	return product, nil
}
func (a *api) getInventory(c fiber.Ctx) error {
	if a.shop == nil {
		return c.JSON(fiber.Map{"items": []any{}, "enabled": false})
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return failure(c, 409, "wallet_pending", "Your wallet is getting ready. Please try again shortly.")
	}
	ctx, cancel := context.WithTimeout(c.Context(), 10*time.Second)
	defer cancel()
	p, _, err := a.shop.store.ReadProgress(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	p.normalize(time.Now())
	items := []any{}
	ownership, err := a.shop.client.ownedItems(ctx, wallet.Address)
	if err != nil {
		return failure(c, 503, "inventory_unavailable", "Your inventory is updating. Please try again shortly.")
	}
	for _, id := range a.shop.client.inventoryIDs() {
		client, _ := a.shop.client.forItem(id)
		item := client.itemView()
		item["quantity"] = ownership[id]

		items = append(items, item)
	}
	decks := map[string]any{}
	if a.config.PulseRouter != "" {
		unique, deck, err := a.shop.client.pulseInventory(ctx, wallet.Address)
		if err != nil {
			return failure(c, 503, "collection_unavailable", "Your individual cards are updating. Please retry.")
		}
		if p.Active != nil && time.Now().UnixMilli()-p.Active.StartedAt < int64((2*time.Hour).Milliseconds()) {
			active := map[string]bool{}
			for _, id := range p.Active.DeckIDs {
				active[id] = true
			}
			for _, value := range unique {
				if item, ok := value.(map[string]any); ok {
					if id, ok := item["id"].(string); ok && active[id] {
						item["in_use"] = true
					}
				}
			}
		}
		ids := []string{}
		for _, value := range unique {
			if item, ok := value.(map[string]any); ok {
				ids = append(ids, item["id"].(string))
			}
		}
		busy, err := a.pulseBusy(ids, "", "")
		if err != nil {
			return err
		}
		for _, value := range unique {
			if item, ok := value.(map[string]any); ok && busy[pulseLeaseKey(a.config, item["id"].(string))] {
				item["in_use"] = true
			}
		}
		items = append(items, unique...)
		for setID, ids := range deck {
			decks[setID] = ids
		}
	}
	key := p.ShopActive
	if key == "" {
		key = p.ShopLast
	}
	var operation *shopJob
	if key != "" {
		operation, err = a.shop.store.shopOperation(key, c.Locals("user").(user).ID)
		if err != nil {
			return err
		}
	}
	equipped := p.EquippedCard
	if ownership[equipped] < 1 {
		equipped = ""
	}
	return c.JSON(fiber.Map{"enabled": true, "items": items, "equipped_card": equipped, "operation": operation, "decks": decks, "progression": a.progressionView(p, time.Now())})
}
func (a *api) beginShopOperation(c fiber.Ctx, kind string) error {
	if a.shop == nil {
		return failure(c, 503, "shop_disabled", "Purchases are not open yet.")
	}
	var body struct {
		RequestID     string `json:"request_id"`
		ItemID        string `json:"item_id"`
		CardID        string `json:"card_id"`
		Quantity      int    `json:"quantity"`
		ExpectedTotal string `json:"expected_total"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(body.RequestID, 16) || body.ItemID == "" || body.Quantity < 1 || body.Quantity > 10 || (kind != "buy" && body.Quantity != 1) {
		return failure(c, 400, "invalid_item", "Choose a valid item and quantity.")
	}
	if a.config.PulseRouter != "" && kind == "buy" {
		if card, ok := cardByID(body.ItemID); ok && !card.Legacy {
			return a.buyPulseCard(c, body.ItemID, body.RequestID, body.ExpectedTotal, body.Quantity)
		}
	}
	if a.config.PulseRouter != "" && kind == "buy" {
		if _, ok := materialByID(body.ItemID); ok {
			return a.buyPulseCard(c, body.ItemID, body.RequestID, body.ExpectedTotal, body.Quantity)
		}
	}
	client, itemErr := a.shop.client.forItem(body.ItemID)
	if itemErr != nil || client.legacy() || (kind == "consume" && body.ItemID != "energy_drink") || (kind == "enhance") || (kind != "enhance" && body.CardID != "") {
		return failure(c, 400, "invalid_item", "Choose a valid item.")
	}
	if kind == "buy" && body.ExpectedTotal != fmt.Sprint(body.Quantity*client.price()) {
		return failure(c, 409, "quote_changed", "The price changed. Refresh this item before purchasing.")
	}
	owner := c.Locals("user").(user).ID
	key := shopKey(a.config, owner, body.RequestID)
	old, err := a.shop.store.shopOperation(key, owner)
	if err != nil {
		return err
	}
	if old != nil {
		if old.Kind != kind || old.Quantity != body.Quantity || old.CardID != body.CardID || normalizedItemID(old.ItemID) != body.ItemID {
			return failure(c, 409, "request_conflict", "This request belongs to another action.")
		}
		return c.JSON(fiber.Map{"operation": old})
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return failure(c, 409, "wallet_pending", "Your wallet is getting ready. Please try again shortly.")
	}
	ctx, cancel := context.WithTimeout(c.Context(), 6*time.Second)
	defer cancel()
	if kind == "buy" {
		listing, err := client.listing(ctx)
		if err != nil {
			return failure(c, 503, "listing_unavailable", "The listing is updating. Please try again shortly.")
		}
		if listing.Stock < int64(body.Quantity) || listing.Start > time.Now().Unix() || listing.End <= time.Now().Unix() {
			return failure(c, 409, "sold_out", "This item is not available right now.")
		}
		balance, err := client.star.balance(ctx, wallet.Address)
		if err != nil {
			return failure(c, 503, "balance_unavailable", "Your balance is updating. Please try again shortly.")
		}
		if balance.Cmp(starlightRaw(int64(body.Quantity*client.price()))) < 0 {
			return failure(c, 409, "insufficient_starlight", "Not enough Starlight in your wallet.")
		}
	} else {
		owned, err := client.owned(ctx, wallet.Address)
		if err != nil {
			return failure(c, 503, "inventory_unavailable", "Your inventory is updating. Please try again shortly.")
		}
		if owned < 1 {
			return failure(c, 409, "no_item", "You do not own this item.")
		}
	}

	head, err := client.star.p.head(ctx)
	if err != nil {
		return failure(c, 503, "shop_unavailable", "The shop is updating. Please try again shortly.")
	}
	roll := 0
	if kind == "enhance" {
		var err error
		roll, err = cardUpgradeRoll()
		if err != nil {
			return err
		}
	}
	j := shopJob{UpgradeRoll: roll, CardID: body.CardID, Router: client.cfg.ShopRouter, ItemID: body.ItemID, Key: key, Owner: owner, RequestID: body.RequestID, Kind: kind, Wallet: strings.ToLower(wallet.Address), Quantity: body.Quantity, Status: "pending", Stage: "gas", FromBlock: head}
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		if p.ShopActive != "" {
			if p.ShopActive == key {
				existing, lookupErr := a.shop.store.shopOperation(key, owner)
				if lookupErr != nil {
					return nil, lookupErr
				}
				if existing == nil || existing.Kind != kind || existing.Quantity != body.Quantity || existing.CardID != body.CardID || normalizedItemID(existing.ItemID) != body.ItemID {
					return nil, badProgress("This request belongs to another action.")
				}
				return *existing, nil
			}
			return nil, badProgress("Your previous item action is still processing. Check Inventory for its status.")
		}
		// Recheck the durable request inside the CAS retry loop, including after a
		// worker finishes quickly between two simultaneous identical requests.
		prior, err := a.shop.store.shopOperation(key, owner)
		if err != nil {
			return nil, err
		}
		if prior != nil {
			if prior.Kind != kind || prior.Quantity != body.Quantity || prior.CardID != body.CardID || normalizedItemID(prior.ItemID) != body.ItemID {
				return nil, badProgress("This request belongs to another action.")
			}
			return *prior, nil
		}
		if kind == "consume" && p.Energy.Current >= energyCap {
			return nil, badProgress("Your energy is already full. Keep this drink for later.")
		}

		p.ShopActive = key
		p.shopNew = &j
		p.shopTarget = shopTarget(a.config)
		return j, nil
	})
}
func (a *api) buyItem(c fiber.Ctx) error     { return a.beginShopOperation(c, "buy") }
func (a *api) consumeItem(c fiber.Ctx) error { return a.beginShopOperation(c, "consume") }

func (a *api) enhanceCard(c fiber.Ctx) error {
	return failure(c, 409, "individual_card_required", "Preview an individual card in Collection before refining it.")
}
