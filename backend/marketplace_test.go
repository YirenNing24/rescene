package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestMarketplaceLiveReadOnly(t *testing.T) {
	if os.Getenv("MARKETPLACE_LIVE_TEST") != "true" {
		t.Skip("set MARKETPLACE_LIVE_TEST=true with backend configuration for read-only verification")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.MarketplaceEnabled {
		t.Fatal("marketplace integration is disabled")
	}
	out, err := newMarketplaceService(cfg).status(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	expectedCheckout := cfg.StarlightEnabled && cfg.ShopEnabled && cfg.StarlightChainID == cfg.MarketplaceChainID
	if out.Status != "connected" || out.CheckoutEnabled != expectedCheckout {
		t.Fatalf("marketplace status mismatch: %+v", out)
	}
	t.Logf("Verified MarketplaceV3 through read-only calls on chain %d, total listing IDs: %s; checkout enabled: %t", out.ChainID, out.TotalListings, out.CheckoutEnabled)
}

func TestMarketplaceReadsAndCache(t *testing.T) {
	var calls atomic.Int32
	var wrong atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Method != "POST" || r.Header.Get("X-GMR-Engine-Key") != "market-read-key" || r.Header.Get("Idempotency-Key") != "" {
			t.Error("wrong credentials or write headers")
		}
		var body struct {
			ChainID         int64    `json:"chainId"`
			ContractAddress string   `json:"contractAddress"`
			FunctionName    string   `json:"functionName"`
			Method          string   `json:"method"`
			Args            []string `json:"args"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body.ChainID != 421614 {
			t.Error("wrong chain")
		}
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/v1/rpc/read" {
			if body.Method != "eth_chainId" {
				t.Error("unapproved RPC method")
			}
			fmt.Fprint(w, `{"result":"0x66eee"}`)
			return
		}
		if r.URL.Path != "/v1/contracts/read" || body.ContractAddress != "0x1111111111111111111111111111111111111111" || len(body.Args) != 0 {
			t.Error("unexpected call")
		}
		switch body.FunctionName {
		case "contractType":
			kind := "0x4d61726b6574706c616365563300000000000000000000000000000000000000"
			if wrong.Load() {
				kind = "0x00"
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"result": map[string]string{"result": kind}})
		case "totalListings":
			fmt.Fprint(w, `{"result":{"result":"0"}}`)
		default:
			t.Error("attempted non-read operation")
			w.WriteHeader(400)
		}
	}))
	defer server.Close()
	cfg := config{EngineURL: server.URL, MarketplaceEnabled: true, MarketplaceEngineKey: "market-read-key", MarketplaceChainID: 421614, MarketplaceAddress: "0x1111111111111111111111111111111111111111"}
	m := newMarketplaceService(cfg)
	var wg sync.WaitGroup
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out, err := m.status(context.Background())
			if err != nil || out.Status != "connected" || out.TotalListings != "0" || out.CheckoutEnabled || out.CheckedAt == "" {
				t.Errorf("invalid read-only result: %+v %v", out, err)
			}
		}()
	}
	wg.Wait()
	if calls.Load() != 3 {
		t.Fatalf("cache failed: %d calls", calls.Load())
	}
	wrong.Store(true)
	m.expires = time.Time{}
	out, err := m.status(context.Background())
	if err == nil || out.Status != "unavailable" || out.TotalListings != "" || out.CheckedAt != "" {
		t.Fatal("stale success served after contract mismatch")
	}
}

func TestMarketplaceFailures(t *testing.T) {
	for _, tc := range []struct {
		name, body string
		status     int
	}{
		{"scope", `{"error":"secret provider details"}`, 403},
		{"chain", `{"result":"0x1"}`, 200},
		{"malformed", `{`, 200},
		{"oversize", strings.Repeat("x", 1048577), 200},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); fmt.Fprint(w, tc.body) }))
			defer server.Close()
			m := newMarketplaceService(config{MarketplaceEnabled: true, EngineURL: server.URL, MarketplaceEngineKey: "key", MarketplaceChainID: 421614})
			out, err := m.status(context.Background())
			if err == nil || out.Status != "unavailable" || out.TotalListings != "" || out.CheckoutEnabled {
				t.Fatal("upstream failure exposed as empty/ready catalog")
			}
		})
	}
	disabled := newMarketplaceService(config{})
	out, err := disabled.status(context.Background())
	if err != nil || out.Status != "not_configured" || out.CheckoutEnabled {
		t.Fatal("disabled marketplace contacted Engine")
	}
}

func TestMarketplaceRequiresLoginAndHasNoWrites(t *testing.T) {
	app := testApp(t, testStore(t))
	status, _, _ := request(t, app, "GET", "/api/v1/marketplace", nil, "")
	requireStatus(t, status, 401)
	status, body, _ := request(t, app, "POST", "/api/v1/auth/register", creds("MarketPlayer", "secure password"), "")
	requireStatus(t, status, 201)
	token := body["access_token"].(string)
	status, body, _ = request(t, app, "GET", "/api/v1/marketplace", nil, token)
	requireStatus(t, status, 200)
	market := body["marketplace"].(map[string]any)
	if market["status"] != "not_configured" || market["checkout_enabled"] != false {
		t.Fatal(body)
	}
	for _, path := range []string{"/api/v1/marketplace", "/api/v1/marketplace/buy", "/api/v1/marketplace/listings"} {
		status, _, _ = request(t, app, "POST", path, map[string]string{"item": "scene_01"}, token)
		if status < 400 {
			t.Fatal("unexpected marketplace mutation endpoint")
		}
	}
}

func TestMarketplaceConfiguration(t *testing.T) {
	cfg := config{EngineURL: "https://engine.example.test", EngineProjectID: "project", MarketplaceEngineKey: "key", MarketplaceAddress: "0x" + strings.Repeat("1", 40), MarketplaceCollection: "0x" + strings.Repeat("2", 40), MarketplaceChainID: 421614}
	if err := validateMarketplaceConfig(cfg); err != nil {
		t.Fatal(err)
	}
	for _, raw := range []string{"http://engine.example.test", "https://key@engine.example.test", "https://engine.example.test?key=secret", "https://engine.example.test#fragment"} {
		bad := cfg
		bad.EngineURL = raw
		if validateMarketplaceConfig(bad) == nil {
			t.Error("accepted unsafe Engine URL", raw)
		}
	}
	cfg.MarketplaceEngineKey = ""
	if validateMarketplaceConfig(cfg) == nil {
		t.Fatal("accepted missing read key")
	}
}
