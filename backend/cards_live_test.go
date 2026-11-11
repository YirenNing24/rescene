package main

import (
	"context"
	"encoding/json"
	"fmt"
	"golang.org/x/crypto/bcrypt"
	"os"
	"strings"
	"testing"
	"time"
)

func TestCardsLiveReadOnly(t *testing.T) {
	if os.Getenv("CARDS_LIVE_READ_TEST") != "true" {
		t.Skip("opt-in read-only deployed card verification")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.CardsEnabled || cfg.StarlightChainID != 421614 {
		t.Fatal("expected testnet cards")
	}
	data, err := os.ReadFile("../contracts/deployments/member-card-live-verification.json")
	if err != nil {
		t.Fatal(err)
	}
	var proof struct {
		Wallet string `json:"wallet"`
	}
	if json.Unmarshal(data, &proof) != nil || !validHex(proof.Wallet, 20) {
		t.Fatal("invalid public test receipt")
	}
	client := newShopClient(cfg)
	card, _ := client.forItem("scene_01")
	if err = card.preflight(context.Background()); err != nil {
		t.Fatal(err)
	}
	quantities, err := client.ownedItems(context.Background(), proof.Wallet)
	if err != nil || len(quantities) != 6 || quantities["scene_03"] != 1 {
		t.Fatal("confirmed card batch mismatch", err)
	}
	for _, id := range []string{"scene_01", "scene_02", "scene_04", "scene_05", "energy_drink"} {
		if quantities[id] != 0 {
			t.Fatal("unexpected test wallet inventory")
		}
	}
	t.Log("Deployed router and one confirmed inventory batch: PASS (read only)")
}

// Opt-in only: an isolated test graph/account/wallet buys one cosmetic card with
// 450 testnet STARL supplied by treasury. No existing player is modified.
func TestCardsLiveTestnetPurchaseAndEquip(t *testing.T) {
	if os.Getenv("CARDS_LIVE_TEST") != "true" {
		t.Skip("explicit testnet card checkout smoke test")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.CardsEnabled || cfg.StarlightChainID != 421614 || cfg.EngineProjectID != "7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d" {
		t.Fatal("expected RESCENE testnet card configuration")
	}
	cfg.LeaderboardEnabled = false
	cfg.Secret = testConfig().Secret
	store := testStore(t)
	app, err := newApp(store, cfg, bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = app.Shutdown() })
	token, owner := progressAccount(t, app, fmt.Sprintf("card_test_%d", time.Now().Unix()))
	var wallet walletInfo
	for range 60 {
		wallet, err = store.ReadWallet(owner, cfg.EngineProjectID, cfg.EngineURL)
		if err == nil && wallet.Status == "ready" {
			break
		}
		time.Sleep(time.Second)
	}
	if wallet.Status != "ready" {
		t.Fatal("test managed wallet pending")
	}
	client := newStarlightClient(cfg)
	head, err := client.p.head(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	funding := starlightJob{Key: strings.TrimPrefix(hashHex([]byte("member-card-test/"+owner)), "0x"), Owner: owner, Recipient: wallet.Address, Amount: 450, FromBlock: head}
	tx, err := client.enqueue(context.Background(), funding)
	if err != nil {
		t.Fatal(err)
	}
	funding.TxHash = tx.Hash
	funded := false
	for range 90 {
		processed, err := client.processed(context.Background(), funding)
		if err != nil {
			t.Fatal(err)
		}
		if processed {
			if funding.TxHash == "" {
				funding.TxHash, err = client.findPaid(context.Background(), &funding)
				if err != nil {
					t.Fatal(err)
				}
			}
			funded, err = client.confirmed(context.Background(), funding)
			if err != nil {
				t.Fatal(err)
			}
			if funded {
				break
			}
		}
		time.Sleep(2 * time.Second)
	}
	if !funded {
		t.Fatal("test funding not confirmed")
	}
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 1), "item_id": "scene_03", "quantity": 1, "expected_total": "450"}
	status, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	var order *shopJob
	for range 120 {
		order, err = store.shopOperation(shopKey(cfg, owner, body["request_id"].(string)), owner)
		if err != nil {
			t.Fatal(err)
		}
		if order.Status == "confirmed" {
			break
		}
		if order.Status == "failed" {
			t.Fatal("card purchase failed", order.Error)
		}
		time.Sleep(2 * time.Second)
	}
	if order == nil || order.Status != "confirmed" {
		t.Fatal("purchase still pending")
	}
	status, data, _ := request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	found := false
	for _, raw := range data["items"].([]any) {
		item := raw.(map[string]any)
		if item["id"] == "scene_03" && item["quantity"] == float64(1) {
			found = true
		}
	}
	if !found {
		t.Fatal("card not delivered")
	}
	for range 2 {
		status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
		requireStatus(t, status, 200)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "scene_03"}, token)
	requireStatus(t, status, 200)
	status, data, _ = request(t, app, "GET", "/api/v1/players/"+owner, nil, token)
	requireStatus(t, status, 200)
	if data["profile"].(map[string]any)["progression"].(map[string]any)["equipped_card"] != "scene_03" {
		t.Fatal("public profile missing confirmed favorite")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/equip", map[string]any{"item_id": "scene_02"}, token)
	requireStatus(t, status, 409)
	balance, err := client.balance(context.Background(), wallet.Address)
	if err != nil || balance.Sign() != 0 {
		t.Fatal("wrong STARL debit", err)
	}
	cardClient, _ := newShopClient(cfg).forItem("scene_03")
	quantity, err := cardClient.owned(context.Background(), wallet.Address)
	if err != nil || quantity != 1 {
		t.Fatal("duplicate delivery", err)
	}
	progress, _, _ := store.ReadProgress(owner)
	if progress.EquippedCard != "scene_03" || progress.Energy.Current != 15 {
		t.Fatal("favorite did not persist or changed energy")
	}
	proof := map[string]any{"network": "Arbitrum Sepolia", "wallet": wallet.Address, "item_id": "scene_03", "token_id": "3", "price": "450 STARL", "funding_transaction": funding.TxHash, "purchase_transaction": order.TxHash, "quantity_owned": quantity, "equipped_card": progress.EquippedCard, "duplicate_requests": "no additional payment or item", "unowned_equip": "rejected", "energy": progress.Energy.Current}
	bytes, _ := json.MarshalIndent(proof, "", "  ")
	if err = os.WriteFile("../contracts/deployments/member-card-live-verification.json", append(bytes, '\n'), 0644); err != nil {
		t.Fatal(err)
	}
	t.Log("Real card paid, delivered, equipped, shown on public profile; duplicate purchase safe.")
}
