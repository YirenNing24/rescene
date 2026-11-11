package main

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func TestAdminLiveReadiness(t *testing.T) {
	if os.Getenv("ADMIN_LIVE_READS") != "1" {
		t.Skip("read-only deployment check")
	}
	cfg, e := loadConfig()
	if e != nil {
		t.Fatal(e)
	}
	client := newShopClient(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	for _, id := range []string{"energy_drink", "legacy_scene_01"} {
		cl, e := client.forItem(id)
		if e != nil {
			cl = client
		}
		for _, v := range []struct{ name, address string }{{"operator()", cfg.StarlightTreasury}, {"token()", cfg.StarlightToken}, {"items()", cfg.MarketplaceCollection}, {"market()", cfg.MarketplaceAddress}} {
			raw, e := cl.call(ctx, cl.cfg.ShopRouter, v.name, "")
			t.Log(id, v.name, "matches", strings.EqualFold(raw, "0x"+addressWord(v.address)), "actual", raw, "error", e)
		}
		for _, v := range []string{"tokenId()", "listingId()", "unitPrice()"} {
			n, e := cl.number(ctx, cl.cfg.ShopRouter, v, "")
			t.Log(id, v, n, e)
		}
	}
}
