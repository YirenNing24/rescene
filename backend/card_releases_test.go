package main

import (
	"context"
	"fmt"
	"testing"
)

func TestReleaseCardsCheckoutInventoryAndEquipment(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	f.f.cfg.CardReleases = true
	a.config = f.f.cfg
	a.shop.client = newShopClient(f.f.cfg)
	status, data, _ := request(t, app, "GET", "/api/v1/shop/catalog", nil, token)
	requireStatus(t, status, 200)
	products := data["catalog"].([]any)
	if len(products) != 49 {
		t.Fatalf("catalog has %d products, want 45 cards and 4 consumables", len(products))
	}
	for index, card := range allMemberCards() {
		release := cardReleaseFor(card)
		nonce := 10000 + index*10
		body := map[string]any{"request_id": fmt.Sprintf("%032x", nonce), "item_id": card.ID, "quantity": 1, "expected_total": "450"}
		status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
		requireStatus(t, status, 200)
		key := shopKey(f.f.cfg, owner, body["request_id"].(string))
		job := finishPulse(t, s, a, f, key)
		// Duplicate requests retain the original roll and never charge again.
		payments := f.f.payments
		status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
		requireStatus(t, status, 200)
		if f.f.payments != payments {
			t.Fatal("retry charged twice")
		}
		number, ok := pulseToken(job.CardID)
		if !ok {
			t.Fatal("missing token")
		}
		owned, err := a.shop.client.pulseCard(context.Background(), 100, job.Wallet, number)
		if err != nil {
			t.Fatal(err)
		}
		view := owned.view()
		if view["template_id"] != card.ID || view["set_id"] != release.SetID || owned.Member != index%5 {
			t.Fatalf("wrong release identity for %s: %+v", card.ID, view)
		}
		equip := map[string]any{"kind": "equip", "card_id": job.CardID, "set_id": release.SetID, "member_index": owned.Member}
		quote := quotePulse(t, app, token, equip)
		submitPulse(t, app, token, equip, quote, nonce+1)
		finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, fmt.Sprintf("%032x", nonce+1)))
		wrong := map[string]any{"kind": "equip", "card_id": job.CardID, "set_id": cardReleases[release.Number%9].SetID, "member_index": owned.Member}
		status, _, _ = request(t, app, "POST", "/api/v1/collection/quote", wrong, token)
		if status < 400 {
			t.Fatal("cross-release equipment accepted")
		}
	}
	items, decks, err := a.shop.client.pulseInventory(context.Background(), "0x4444444444444444444444444444444444444444")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 45 || len(decks) != 9 {
		t.Fatalf("inventory missing releases: %d cards, %d decks", len(items), len(decks))
	}
	for _, release := range cardReleases {
		team, ids, err := a.shop.client.pulseDeck(context.Background(), 100, "0x4444444444444444444444444444444444444444", release.SetID)
		if err != nil {
			t.Fatal(err)
		}
		if len(team) != 5 || len(ids) != 5 || combinedPulseCards(team) == nil {
			t.Fatal("missing set bonuses")
		}
		for _, id := range ids {
			if id == "" {
				t.Fatal("missing equipped member")
			}
		}
	}
}

func TestReleaseTemplatesCannotBePurchasedThroughOldPulseRouter(t *testing.T) {
	_, _, _, app, token, _ := newPulseTest(t)
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 99999), "item_id": "le_scenedrome_01", "quantity": 1, "expected_total": "450"}
	status, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	if status < 400 {
		t.Fatal("new release sent to old PULSE contract")
	}
}
