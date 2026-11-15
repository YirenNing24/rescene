package main

import (
	"context"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
	"testing"
	"time"
)

func TestMemberCardCheckoutOwnershipAndEquipment(t *testing.T) {
	s := testStore(t)
	base := testApp(t, s)
	token, owner := progressAccount(t, base, "cardcollector")
	f := newShopFixture(t)
	f.cfg.CardsEnabled = true
	f.balance = 2000
	wallet := "0x" + strings.Repeat("4", 40)
	_, _ = s.ReadWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL)
	_, _ = s.ClaimWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", time.Now())
	if _, err := s.SaveWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", walletInfo{ID: "managed-player", Address: wallet, Status: "ready"}); err != nil {
		t.Fatal(err)
	}
	a := &api{store: s, config: f.cfg}
	a.shop = &shopService{store: s, client: newShopClient(f.cfg)}
	app := fiber.New(fiber.Config{ErrorHandler: func(c fiber.Ctx, e error) error { return failure(c, 400, "bad_request", "Invalid request.") }})
	app.Use(a.authenticate)
	app.Get("/api/v1/inventory", a.getInventory)
	app.Get("/api/v1/shop/catalog", a.shopCatalog)
	app.Post("/api/v1/shop/purchase", a.buyItem)
	app.Post("/api/v1/inventory/consume", a.consumeItem)
	app.Post("/api/v1/collection/equip", a.equipMemberCard)
	status, _, _ := request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "scene_01"}, "")
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "scene_01"}, token)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "energy_drink"}, token)
	requireStatus(t, status, 400)
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 101), "item_id": "scene_03", "quantity": 2, "expected_total": "900"}
	status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", body, token)
	requireStatus(t, status, 400)
	body["expected_total"] = "200"
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 409)
	body["expected_total"] = "900"
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	f.lost = true
	key := shopKey(f.cfg, owner, body["request_id"].(string))
	for range 16 {
		job, ok, err := s.claimShop(shopTarget(f.cfg))
		if err != nil || !ok {
			t.Fatal("claim", err)
		}
		err = a.shop.advance(context.Background(), &job)
		if err != nil && err.Error() != "upstream_unavailable" {
			t.Fatal(err)
		}
		if job.Status == "confirmed" {
			if err = s.finishShop(job); err != nil {
				t.Fatal(err)
			}
			break
		}
		if err = s.saveShop(job, time.Now().Add(-time.Second)); err != nil {
			t.Fatal(err)
		}
	}
	job, err := s.shopOperation(key, owner)
	if err != nil || job.Status != "confirmed" {
		t.Fatal("card did not confirm", err)
	}
	if f.cardOwned[8] != 2 || f.balance != 1100 || f.payments != 1 {
		t.Fatal("incorrect price, ownership or duplicate charge")
	}
	// Exact retry is harmless; reusing the same ID for a different card is rejected.
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	body["item_id"] = "scene_04"
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "scene_03"}, token)
	requireStatus(t, status, 200)
	p, _, _ := s.ReadProgress(owner)
	if p.EquippedCard != "scene_03" || p.Energy.Current != energyCap {
		t.Fatal("equipment was not persisted or altered gameplay")
	}
	status, data, _ := request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	if data["equipped_card"] != "scene_03" || len(data["items"].([]any)) != 9 {
		t.Fatal("inventory missing collection")
	}
	// A transfer out of the managed wallet removes the public favorite immediately.
	f.cardOwned[8] = 0
	status, data, _ = request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	if data["equipped_card"] != "" || a.verifiedMemberCard(context.Background(), owner, "scene_03") != "" {
		t.Fatal("stale ownership advertised")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": ""}, token)
	requireStatus(t, status, 200)
	p, _, _ = s.ReadProgress(owner)
	if p.EquippedCard != "" {
		t.Fatal("favorite was not removed")
	}
}

func TestCardClientPinsItemPriceAndReceipt(t *testing.T) {
	f := newShopFixture(t)
	f.cfg.CardsEnabled = true
	client, err := newShopClient(f.cfg).forItem("scene_05")
	if err != nil {
		t.Fatal(err)
	}
	j := shopJob{ItemID: "scene_05", Key: strings.Repeat("a", 64), Wallet: "0x" + strings.Repeat("4", 40), Quantity: 1, Kind: "buy", Stage: "execute"}
	spec := client.spec(j)
	if spec.Method != "purchaseItem" || spec.Args[3] != "10" || spec.Address != f.cfg.CardsRouter || client.price() != 450 {
		t.Fatal("wrong card binding")
	}
	f.records[j.Key] = j
	f.hashes[j.Key] = "0x" + strings.Repeat("b", 64)
	j.TxHash = f.hashes[j.Key]
	if ok, err := client.confirmed(context.Background(), &j); err != nil || !ok {
		t.Fatal("real card receipt not confirmed", err)
	}
	wrong, _ := newShopClient(f.cfg).forItem("scene_04")
	if ok, err := wrong.confirmed(context.Background(), &j); err == nil || ok {
		t.Fatal("wrong card delivery accepted")
	}
	f.wrong = true
	if ok, err := client.confirmed(context.Background(), &j); err == nil || ok {
		t.Fatal("missing payment and card transfer accepted")
	}
}
