package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func starlightTestConfig() config {
	c := testConfig()
	c.StarlightEnabled = true
	c.EngineProjectID = "star-project"
	c.EngineAPIKey = "wallet-key"
	c.StarlightEngineKey = "star-key"
	c.StarlightToken = "0x" + strings.Repeat("1", 40)
	c.StarlightTreasury = "0x" + strings.Repeat("2", 40)
	c.StarlightDistributor = "0x" + strings.Repeat("3", 40)
	c.StarlightChainID = 421614
	c.StarlightConfirmations = 3
	return c
}
func TestStarlightLedgerAtomicityAndMigration(t *testing.T) {
	s := testStore(t)
	base := testApp(t, s)
	token, owner := progressAccount(t, base, "starplayer")
	cfg := starlightTestConfig()
	cfg.LeaderboardEnabled = true
	cfg.LeaderboardChainID = 421614
	cfg.LeaderboardAddress = "0x" + strings.Repeat("5", 40)
	a := &api{store: s, config: cfg, replaySlots: make(chan struct{}, 2)}
	app := fiber.New()
	app.Use(a.authenticate)
	app.Get("/api/v1/progression", a.getProgress)
	app.Post("/api/v1/runs", a.startRun)
	app.Post("/api/v1/runs/:id/complete", a.completeRun)
	app.Post("/api/v1/missions/:id/claim", a.claimMission)
	app.Post("/api/v1/daily-login/claim", a.claimDailyLogin)
	editProgress(t, s, owner, func(p *progression) { p.Starlight = 120 })
	var wg sync.WaitGroup
	for range 6 {
		wg.Add(1)
		go func() { defer wg.Done(); snapshot(t, app, token) }()
	}
	wg.Wait()
	if err := s.backfillStarlight(cfg); err != nil {
		t.Fatal(err)
	}
	pending, err := s.pendingStarlight(starlightTarget(cfg), owner)
	if err != nil || pending != 120 {
		t.Fatalf("historical migration: %d %v", pending, err)
	}
	chart := firstChart()
	run := startTestRun(t, app, token, chart)
	ageRun(t, s, owner, chart)
	for range 2 {
		status, _, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart, run), token)
		requireStatus(t, status, 200)
	}
	publications, err := s.query(`MATCH(j:LeaderboardPublication) RETURN count(j)`, nil)
	if err != nil || !publications.Next() {
		t.Fatal("score and currency outboxes did not commit together", err)
	}
	count, _ := publications.Record().GetByIndex(0)
	if count != int64(1) {
		t.Fatal("verified clear must create exactly one leaderboard publication alongside its STARL payout", count)
	}
	status, _, _ := request(t, app, "POST", "/api/v1/missions/first_clear/claim", map[string]string{"day": ""}, token)
	requireStatus(t, status, 200)
	date := time.Now().UTC().Format("2006-01-02")
	for range 2 {
		status, _, _ = request(t, app, "POST", "/api/v1/daily-login/claim", map[string]any{"date": date, "day": 1}, token)
		requireStatus(t, status, 200)
	}
	pending, err = s.pendingStarlight(starlightTarget(cfg), owner)
	if err != nil || pending != 260 {
		t.Fatalf("reward payout mismatch: %d %v", pending, err)
	}
	p, v, err := s.ReadProgress(owner)
	if err != nil {
		t.Fatal(err)
	}
	p.Starlight += 99
	if _, err = prepareStarlight(&p, cfg); err != nil {
		t.Fatal(err)
	}
	written, err := s.WriteProgress(owner, v-1, p)
	if err != nil || written {
		t.Fatal("stale CAS succeeded")
	}
	pending, _ = s.pendingStarlight(starlightTarget(cfg), owner)
	if pending != 260 {
		t.Fatal("rejected CAS created payout")
	}
	job, ok, err := s.claimStarlight(starlightTarget(cfg), time.Now())
	if err != nil || !ok || job.Amount != 120 {
		t.Fatal("oldest payout", job, err)
	}
	if _, ok, err = s.claimStarlight(starlightTarget(cfg), time.Now()); err != nil || ok {
		t.Fatal("leased owner overtaken")
	}
	job.Status = "confirmed"
	if err = s.saveStarlight(job, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	next, ok, err := s.claimStarlight(starlightTarget(cfg), time.Now())
	if err != nil || !ok || next.Amount != 60 {
		t.Fatal("next payout", next, err)
	}
	cfg.StarlightDistributor = "0x" + strings.Repeat("4", 40)
	cfg.EngineURL = "https://another-engine.example"
	p, _, _ = s.ReadProgress(owner)
	changed, err := prepareStarlight(&p, cfg)
	if err != nil || changed {
		t.Fatal("router/URL change re-granted historical earnings")
	}
	reopened, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	p, _, err = reopened.ReadProgress(owner)
	if err != nil || p.StarlightAccrued[starlightAsset(cfg)] != 260 {
		t.Fatal("accrual did not persist")
	}
}

type starlightFixture struct {
	mu                      sync.Mutex
	cfg                     config
	server                  *httptest.Server
	processed, loseResponse bool
	transfers, posts        int
	tx                      enginePublicationTx
	job                     starlightJob
	wrongReceipt, reorg     bool
}

func fakeStarlight(t *testing.T) *starlightFixture {
	f := &starlightFixture{cfg: starlightTestConfig(), job: starlightJob{Key: strings.Repeat("a", 64), Owner: "owner", Amount: 60, Recipient: "0x" + strings.Repeat("4", 40), FromBlock: 100, Status: "pending"}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/v1/contracts/write" {
			if r.Header.Get("X-GMR-Engine-Key") != "star-key" || r.Header.Get("Idempotency-Key") != "rescene/starlight/"+f.job.Key+"/0" {
				t.Error("wrong payout key")
			}
			var b struct {
				ChainID  int64    `json:"chainId"`
				Address  string   `json:"contractAddress"`
				Wallet   string   `json:"walletAddress"`
				Function string   `json:"functionName"`
				Args     []string `json:"args"`
				Value    string   `json:"value"`
			}
			_ = json.NewDecoder(r.Body).Decode(&b)
			if b.Function != "pay" || b.Address != f.cfg.StarlightDistributor || b.Wallet != f.cfg.StarlightTreasury || b.Value != "0" || strings.Join(b.Args, "/") != strings.Join(starlightArgs(f.job), "/") {
				t.Error("wrong payout parameters")
			}
			f.posts++
			if !f.processed {
				f.processed = true
				f.transfers++
			}
			f.tx = enginePublicationTx{ID: "tx-1", AppID: f.cfg.EngineProjectID, ChainID: f.cfg.StarlightChainID, ContractAddress: b.Address, WalletAddress: b.Wallet, Method: b.Function, Args: b.Args, Status: "confirmed", Hash: "0x" + strings.Repeat("b", 64)}
			if f.loseResponse {
				f.loseResponse = false
				w.WriteHeader(503)
				fmt.Fprint(w, `{"error":"secret provider error"}`)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"transaction": f.tx})
			return
		}
		if r.URL.Path == "/v1/auth/me" {
			_ = json.NewEncoder(w).Encode(map[string]any{"app": map[string]string{"id": f.cfg.EngineProjectID}})
			return
		}
		if strings.HasPrefix(r.URL.Path, "/v1/transactions/") {
			_ = json.NewEncoder(w).Encode(map[string]any{"transaction": f.tx})
			return
		}
		if r.URL.Path != "/rpc" {
			t.Error("unexpected route", r.URL.Path)
			w.WriteHeader(404)
			return
		}
		var rpc struct {
			Method string            `json:"method"`
			Params []json.RawMessage `json:"params"`
		}
		_ = json.NewDecoder(r.Body).Decode(&rpc)
		var result any
		amount := "0x" + hex.EncodeToString(starlightRaw(f.job.Amount).FillBytes(make([]byte, 32)))
		hash := "0x" + strings.Repeat("b", 64)
		switch rpc.Method {
		case "eth_chainId":
			result = "0x66eee"
		case "eth_blockNumber":
			result = "0x78"
		case "eth_call":
			var call struct{ To, Data string }
			_ = json.Unmarshal(rpc.Params[0], &call)
			switch {
			case strings.HasPrefix(call.Data, selector("payouts(bytes32)")):
				result = "0x" + strings.Repeat("0", 64)
				if f.processed {
					result = starlightDigest(f.job)
				}
			case strings.HasPrefix(call.Data, selector("balanceOf(address)")), strings.HasPrefix(call.Data, selector("allowance(address,address)")):
				result = "0x" + hex.EncodeToString(starlightRaw(1000000).FillBytes(make([]byte, 32)))
			case call.Data == selector("token()"):
				result = "0x" + addressWord(f.cfg.StarlightToken)
			case call.Data == selector("treasury()"):
				result = "0x" + addressWord(f.cfg.StarlightTreasury)
			case call.Data == selector("decimals()"):
				result = "0x" + hex.EncodeToString(word(18))
			default:
				t.Error("unexpected eth_call", call.Data)
			}
		case "eth_getLogs":
			result = []scoreLog{{Address: f.cfg.StarlightDistributor, Topics: []string{starlightPaidTopic, "0x" + f.job.Key, "0x" + addressWord(f.job.Recipient)}, Data: amount, TxHash: hash}}
		case "eth_getTransactionReceipt":
			transfer := scoreLog{Address: f.cfg.StarlightToken, Topics: []string{tokenTransferTopic, "0x" + addressWord(f.cfg.StarlightTreasury), "0x" + addressWord(f.job.Recipient)}, Data: amount}
			if f.wrongReceipt {
				transfer.Topics[2] = "0x" + addressWord(f.cfg.StarlightTreasury)
			}
			result = publicationReceipt{Status: "0x1", TxHash: hash, BlockHash: "0x" + strings.Repeat("c", 64), BlockNumber: "0x64", Logs: []scoreLog{{Address: f.cfg.StarlightDistributor, Topics: []string{starlightPaidTopic, "0x" + f.job.Key, "0x" + addressWord(f.job.Recipient)}, Data: amount}, transfer}}
		case "eth_getBlockByNumber":
			h := "0x" + strings.Repeat("c", 64)
			if f.reorg {
				h = "0x" + strings.Repeat("d", 64)
			}
			result = map[string]string{"hash": h}
		default:
			t.Error("unexpected RPC", rpc.Method)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": result})
	}))
	f.cfg.EngineURL = f.server.URL
	f.cfg.StarlightRPC = f.server.URL + "/rpc"
	t.Cleanup(f.server.Close)
	return f
}
func TestStarlightAmbiguousResponseAndReceiptVerification(t *testing.T) {
	f := fakeStarlight(t)
	f.loseResponse = true
	client := newStarlightClient(f.cfg)
	if err := client.preflight(context.Background()); err != nil {
		t.Fatal(err)
	}
	service := &starlightService{client: client}
	job := f.job
	next := time.Now()
	if err := service.advance(context.Background(), &job, &next); err == nil {
		t.Fatal("lost response expected")
	}
	if job.EngineID != "" {
		t.Fatal("invented Engine ID")
	}
	service = &starlightService{client: newStarlightClient(f.cfg)}
	if err := service.advance(context.Background(), &job, &next); err != nil {
		t.Fatal(err)
	}
	if job.Status != "confirmed" || f.transfers != 1 || f.posts != 1 {
		t.Fatal("payout repeated or unconfirmed", job, f.transfers, f.posts)
	}
	if err := service.advance(context.Background(), &job, &next); err != nil {
		t.Fatal(err)
	}
	f.wrongReceipt = true
	if _, err := client.confirmed(context.Background(), job); err == nil {
		t.Fatal("wrong recipient accepted")
	}
	f.wrongReceipt = false
	f.reorg = true
	confirmed, err := client.confirmed(context.Background(), job)
	if err != nil || confirmed {
		t.Fatal("noncanonical payout accepted")
	}
}
func TestStarlightExactAmountsAndConfiguration(t *testing.T) {
	for raw, want := range map[string]string{"0": "0", "1": "0.000000000000000001", "1000000000000000001": "1.000000000000000001", "60000000000000000000": "60"} {
		n, _ := new(big.Int).SetString(raw, 10)
		if got := formatStarlight(n); got != want {
			t.Errorf("format %s: %s", raw, got)
		}
	}
	if starlightRaw(60).String() != "60000000000000000000" {
		t.Fatal("base units rounded")
	}
	cfg := starlightTestConfig()
	cfg.EngineURL = "https://engine.example.test"
	cfg.StarlightRPC = "https://rpc.example.test"
	if err := validateStarlightConfig(cfg); err != nil {
		t.Fatal(err)
	}
	cfg.StarlightTreasury = "0x" + strings.Repeat("0", 40)
	if validateStarlightConfig(cfg) == nil {
		t.Fatal("accepted zero treasury")
	}
	var p progression
	p.Starlight = 60
	if changed, err := prepareStarlight(&p, config{}); err != nil || changed || p.starlightAward != 0 {
		t.Fatal("disabled integration queued funds")
	}
}

func TestStarlightBalanceIsAuthenticatedAndReadOnly(t *testing.T) {
	s := testStore(t)
	base := testApp(t, s)
	token, owner := progressAccount(t, base, "balanceplayer")
	f := fakeStarlight(t)
	wallet, err := s.ReadWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL)
	if err != nil {
		t.Fatal(err)
	}
	if wallet.Status == "ready" {
		t.Fatal("unexpected fixture wallet")
	}
	claimed, err := s.ClaimWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "test-lease", time.Now())
	if err != nil || !claimed {
		t.Fatal(err)
	}
	saved, err := s.SaveWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "test-lease", walletInfo{ID: "managed-player", Address: f.job.Recipient, Status: "ready", CreatedAt: time.Now().Format(time.RFC3339)})
	if err != nil || !saved {
		t.Fatal(err)
	}
	a := &api{store: s, config: f.cfg, starlight: &starlightService{store: s, client: newStarlightClient(f.cfg), target: starlightTarget(f.cfg)}}
	app := fiber.New()
	app.Use(a.authenticate)
	app.Get("/api/v1/starlight", a.getStarlight)
	app.Use(func(c fiber.Ctx) error { return failure(c, 404, "not_found", "Endpoint not found.") })
	status, _, _ := request(t, app, "GET", "/api/v1/starlight", nil, "")
	requireStatus(t, status, 401)
	status, body, _ := request(t, app, "GET", "/api/v1/starlight?wallet_address="+f.cfg.StarlightTreasury, nil, token)
	requireStatus(t, status, 200)
	view := body["starlight"].(map[string]any)
	if view["wallet_address"] != f.job.Recipient || view["balance"] != "1000000" || view["pending"] != "0" {
		t.Fatal("wrong wallet balance", view)
	}
	bytes, _ := json.Marshal(body)
	if strings.Contains(string(bytes), f.cfg.StarlightEngineKey) || strings.Contains(string(bytes), f.cfg.EngineAPIKey) {
		t.Fatal("server key exposed")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/starlight", map[string]any{"amount": 1000, "recipient": f.cfg.StarlightTreasury}, token)
	if status < 400 {
		t.Fatal("client can request a transfer")
	}
	if f.posts != 0 {
		t.Fatal("balance reads sent a payment")
	}
}

func TestStarlightLiveReadOnly(t *testing.T) {
	if os.Getenv("STARLIGHT_LIVE_TEST") != "true" {
		t.Skip("enable STARLIGHT_LIVE_TEST for read-only deployment verification")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.StarlightEnabled {
		t.Fatal("Starlight disabled")
	}
	client := newStarlightClient(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err = client.preflight(ctx); err != nil {
		t.Fatal(err)
	}
	balance, err := client.balance(ctx, cfg.StarlightTreasury)
	if err != nil {
		t.Fatal(err)
	}
	allowance, err := client.call(ctx, cfg.StarlightToken, selector("allowance(address,address)")+addressWord(cfg.StarlightTreasury)+addressWord(cfg.StarlightDistributor))
	if err != nil {
		t.Fatal(err)
	}
	approved, err := uint256Hex(allowance)
	if err != nil || approved.Sign() <= 0 {
		t.Fatal("treasury allowance missing", err)
	}
	t.Logf("Verified STARL token and treasury-only distributor on chain %d; treasury %s STARL; allowance %s STARL", cfg.StarlightChainID, formatStarlight(balance), formatStarlight(approved))
}
