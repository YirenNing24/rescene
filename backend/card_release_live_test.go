package main

import (
	"context"
	"github.com/gofiber/fiber/v3"
	"os"
	"testing"
	"time"
)

func TestReleaseCardsLiveReadOnly(t *testing.T) {
	if os.Getenv("RELEASE_CARDS_LIVE_READS") != "1" {
		t.Skip("explicit read-only release verification")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.CardReleases || cfg.StarlightChainID != 99901 {
		t.Fatal("wrong live release binding")
	}
	c := newShopClient(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	block, err := c.pulseBlock(ctx)
	if err != nil {
		t.Fatal(err)
	}
	products, err := c.releaseCatalog(ctx, block)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	sets := map[string]bool{}
	for _, raw := range products {
		p := raw.(fiber.Map)
		if p["category"] != "cards" {
			continue
		}
		if p["price"] != 450 || p["available"] != true || p["stock"] != int64(50) {
			t.Fatalf("unexpected live allocation %s", p["id"])
		}
		count++
		sets[p["set_id"].(string)] = true
	}
	if count != 45 || len(sets) != 9 {
		t.Fatalf("missing products: %d / %d sets", count, len(sets))
	}
	t.Log("Confirmed live Elysium catalog: 45 available cards, 9 releases, 450 STARL, 50 per member per set")
}
