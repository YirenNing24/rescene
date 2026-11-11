package main

import (
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
	"testing"
	"time"
)

func cardProgressAPI(t *testing.T) (*graphStore, *api, *shopFixture, *fiber.App, string, string) {
	s := testStore(t)
	token, owner := progressAccount(t, testApp(t, s), "pulseplayer")
	f := newShopFixture(t)
	f.cfg.CardsEnabled = true
	_, _ = s.ReadWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL)
	_, _ = s.ClaimWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", time.Now())
	if _, err := s.SaveWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", walletInfo{ID: "managed", Address: "0x" + strings.Repeat("4", 40), Status: "ready"}); err != nil {
		t.Fatal(err)
	}
	a := &api{store: s, config: f.cfg, replaySlots: make(chan struct{}, 2)}
	a.shop = &shopService{store: s, client: newShopClient(f.cfg)}
	app := fiber.New(fiber.Config{ErrorHandler: func(c fiber.Ctx, e error) error {
		if pe, ok := e.(progressError); ok {
			return failure(c, pe.status, "progression_error", pe.message)
		}
		return failure(c, 400, "bad_request", "Invalid request.")
	}})
	app.Use(a.authenticate)
	app.Post("/api/v1/collection/enhance", a.enhanceCard)
	app.Get("/api/v1/inventory", a.getInventory)
	app.Post("/api/v1/runs", a.startRun)
	app.Post("/api/v1/runs/:id/complete", a.completeRun)
	return s, a, f, app, token, owner
}
func TestLegacyFavoriteDoesNotGrantGameplayBonuses(t *testing.T) {
	s, _, f, app, token, owner := cardProgressAPI(t)
	f.cardOwned[8] = 1
	editProgress(t, s, owner, func(p *progression) { p.EquippedCard = "scene_03" })
	chart := firstChart()
	payload := map[string]any{"request_id": fmt.Sprintf("%032x", 909), "song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}
	status, _, _ := request(t, app, "POST", "/api/v1/runs", payload, token)
	requireStatus(t, status, 200)
	p, _, _ := s.ReadProgress(owner)
	if p.Active.Card != nil {
		t.Fatal("legacy cosmetic granted gameplay stats")
	}
}

func TestLegacyCardRefinementNeedsIndividualPreview(t *testing.T) {
	_, _, _, app, token, _ := cardProgressAPI(t)
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 501), "item_id": "prism_shards", "card_id": "scene_03", "quantity": 1}
	status, _, _ := request(t, app, "POST", "/api/v1/collection/enhance", body, token)
	requireStatus(t, status, 409)
}
