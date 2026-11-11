package main

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestPulseLaunchLiveReadiness(t *testing.T) {
	if os.Getenv("PULSE_LIVE_READS") != "1" {
		t.Skip("explicit read-only live launch check")
	}
	cfg, e := loadConfig()
	if e != nil {
		t.Fatal(e)
	}
	client := newShopClient(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if e := client.preflight(ctx); e != nil {
		t.Fatal("energy router", e)
	}
	if e := client.pulsePreflight(ctx); e != nil {
		t.Fatal("PULSE", e)
	}
	block, e := client.pulseBlock(ctx)
	if e != nil {
		t.Fatal(e)
	}
	raw, e := client.pulseRead(ctx, block, "INITIAL_LE_ALLOCATION()", "")
	if e != nil {
		t.Fatal(e)
	}
	cap, e := wordInt(raw, 0)
	if e != nil || cap != 50 {
		t.Fatal("allocation", cap, e)
	}
	for _, material := range cardMaterials {
		raw, e := client.pulseRead(ctx, block, "materialStock(uint256)", hexWord(material.TokenID))
		if e != nil {
			t.Fatal(e)
		}
		stock, e := wordInt(raw, 0)
		if e != nil || stock < 1 {
			t.Fatal("empty material stock", stock, e)
		}
	}
	t.Log("PASS: energy and PULSE bindings, roles, mutable metadata, 50/member initial allocation and three stocked materials")
}
