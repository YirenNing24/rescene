package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func releaseScanBudget(p *publicationClient) {
	g := p.recoveryGate()
	g.mu.Lock()
	g.nextScan = time.Time{}
	g.mu.Unlock()
}

func TestRPCRecoveryProviderRanges(t *testing.T) {
	for _, tc := range []struct {
		url            string
		override, want int64
	}{
		{"https://elysium-mainnet.g.alchemy.com/v2/private", 0, 10},
		{"https://arb-sepolia.g.alchemy.com/v2/private", 0, 10},
		{"https://rpc.example.test", 0, 2048},
		{"https://rpc.example.test", 10, 10},
		{"https://eth-mainnet.g.alchemy.com/v2/private", 2000, 2000},
	} {
		p := newPublicationClient(config{LeaderboardRPC: tc.url, RPCLogBlockRange: tc.override})
		if n := p.logBlockRange(); n != tc.want {
			t.Fatalf("range=%d want %d", n, tc.want)
		}
	}
}

func TestRPCRecoveryAllPathsBoundAndPersistCursor(t *testing.T) {
	for _, kind := range []string{"publication", "starlight", "shop", "pulse"} {
		t.Run(kind, func(t *testing.T) {
			var requests int
			var ranges [][2]int64
			head := int64(112)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests++
				var req struct {
					Method string
					Params []json.RawMessage
				}
				_ = json.NewDecoder(r.Body).Decode(&req)
				var out any
				switch req.Method {
				case "eth_blockNumber":
					out = fmt.Sprintf("0x%x", head)
				case "eth_getLogs":
					var filter struct {
						FromBlock, ToBlock, Address string
						Topics                      []string
					}
					_ = json.Unmarshal(req.Params[0], &filter)
					from, _ := parseQuantity(filter.FromBlock)
					to, _ := parseQuantity(filter.ToBlock)
					if to-from+1 > 10 || from < 100 || to > head-2 || filter.Address == "" || len(filter.Topics) < 3 {
						t.Errorf("invalid scan %+v", filter)
					}
					ranges = append(ranges, [2]int64{from, to})
					out = []scoreLog{}
				default:
					t.Errorf("unexpected %s", req.Method)
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"result": out})
			}))
			defer server.Close()
			cfg := starlightTestConfig()
			cfg.StarlightRPC = server.URL
			cfg.LeaderboardRPC = server.URL
			cfg.RPCLogBlockRange = 10
			cfg.LeaderboardConfirmations = 3
			cfg.StarlightConfirmations = 3
			cfg.LeaderboardAddress = "0x" + strings.Repeat("5", 40)
			cfg.ShopRouter = "0x" + strings.Repeat("6", 40)
			cfg.PulseRouter = "0x" + strings.Repeat("7", 40)
			p := newPublicationClient(cfg)
			star := newStarlightClient(cfg)
			shop := newShopClient(cfg)
			pub := publicationJob{FromBlock: 100}
			reward := starlightJob{FromBlock: 100}
			order := shopJob{FromBlock: 100, Kind: "buy"}
			scan := func() error {
				switch kind {
				case "publication":
					_, err := p.findPublished(context.Background(), &pub)
					return err
				case "starlight":
					_, err := star.findPaid(context.Background(), &reward)
					return err
				case "shop":
					_, err := shop.confirmed(context.Background(), &order)
					return err
				default:
					_, err := shop.pulseConfirmed(context.Background(), &order)
					return err
				}
			}
			cursor := func() int64 {
				switch kind {
				case "publication":
					return pub.Recovery.NextBlock
				case "starlight":
					return reward.Recovery.NextBlock
				default:
					return order.Recovery.NextBlock
				}
			}
			for i := 0; i < 2; i++ {
				if err := scan(); !recoveryPending(err) {
					t.Fatalf("expected bounded scan wait: %v", err)
				}
				want := int64(110)
				if i == 1 {
					want = 111
				}
				if cursor() != want {
					t.Fatalf("cursor=%d want=%d", cursor(), want)
				}
				before := requests
				if err := scan(); !recoveryPending(err) || requests != before {
					t.Fatalf("budget wait made network requests: %v count=%d", err, requests-before)
				}
				// Simulate reconstructing each job/client after saving its private state.
				pub.Recovery = decodeRecovery(encodeRecovery(pub.Recovery))
				reward.Recovery = decodeRecovery(encodeRecovery(reward.Recovery))
				order, _ = decodeShopJob(encodeShopJob(order))
				p = newPublicationClient(cfg)
				star = newStarlightClient(cfg)
				shop = newShopClient(cfg)
				releaseScanBudget(p)
			}
			if err := scan(); !recoveryPending(err) {
				t.Fatal(err)
			}
			if len(ranges) != 2 || ranges[0] != [2]int64{100, 109} || ranges[1] != [2]int64{110, 110} {
				t.Fatalf("rescanned history: %v", ranges)
			}
			if pub.FromBlock != 100 || reward.FromBlock != 100 || order.FromBlock != 100 {
				t.Fatal("mutated original submission boundary")
			}
		})
	}
}

func TestRPCRecoverySharedBudgetAcrossConcurrentClients(t *testing.T) {
	var calls, logs atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		var req struct{ Method string }
		_ = json.NewDecoder(r.Body).Decode(&req)
		var out any = "0x1000"
		if req.Method == "eth_getLogs" {
			logs.Add(1)
			out = []scoreLog{}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"result": out})
	}))
	defer server.Close()
	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p := newPublicationClient(config{LeaderboardRPC: server.URL, RPCLogBlockRange: 10})
			_, _ = p.recoveryLogs(context.Background(), &recoveryState{}, 100, 3, "contract", []string{"event"})
		}()
	}
	wg.Wait()
	if calls.Load() != 2 || logs.Load() != 1 {
		t.Fatalf("unbounded concurrent scans: calls=%d logs=%d", calls.Load(), logs.Load())
	}
}

func TestRPCRecoveryProviderErrorsBackOffWithoutBreakingReads(t *testing.T) {
	for _, tc := range []struct {
		status  int
		message string
		all     bool
		minimum time.Duration
	}{
		{200, "Under the Free tier plan, eth_getLogs is limited to a 10 block range. private-api-key", false, 59 * time.Minute},
		{400, "Under the Free tier plan, eth_getLogs is limited to a 10 block range. private-api-key", false, 59 * time.Minute},
		{429, "Rate limit exceeded", true, 55 * time.Second},
		{403, "Unauthorized private-api-key", true, 59 * time.Minute},
	} {
		t.Run(fmt.Sprint(tc.status), func(t *testing.T) {
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				if calls > 1 {
					_ = json.NewEncoder(w).Encode(map[string]any{"result": "0x1"})
					return
				}
				w.WriteHeader(tc.status)
				_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"code": -32600, "message": tc.message}})
			}))
			defer server.Close()
			cfg := starlightTestConfig()
			cfg.LeaderboardRPC = server.URL
			cfg.StarlightRPC = server.URL
			p := newPublicationClient(cfg)
			var out any
			err := p.rpc(context.Background(), "eth_getLogs", []any{}, &out)
			var wait *recoveryWait
			if !errors.As(err, &wait) || time.Until(wait.Until) < tc.minimum || strings.Contains(err.Error(), "private-api-key") {
				t.Fatalf("unsafe/unclassified error: %v", err)
			}
			state := recoveryState{NextBlock: 120}
			next := recoveryNext(&state, err, time.Now())
			if state.NextBlock != 120 || time.Until(next) < tc.minimum {
				t.Fatal("lost cursor/backoff")
			}
			for i := 0; i < 20; i++ {
				_ = p.rpc(context.Background(), "eth_getLogs", []any{}, &out)
			}
			if calls != 1 {
				t.Fatalf("cooldown still made %d log requests", calls)
			}
			if tc.all {
				pub := &publicationService{client: newPublicationClient(cfg)}
				star := &starlightService{client: newStarlightClient(cfg)}
				shop := &shopService{client: newShopClient(cfg)}
				for i := 0; i < 20; i++ {
					if pub.process() != nil || star.process() != nil || shop.process() != nil {
						t.Fatal("cooldown not quiet")
					}
					_ = p.rpc(context.Background(), "eth_blockNumber", []any{}, &out)
				}
				if calls != 1 {
					t.Fatal("provider cooldown still made requests", calls)
				}
			} else {
				if err := p.rpc(context.Background(), "eth_call", []any{}, &out); err != nil || calls != 2 {
					t.Fatal("log-only restriction broke working reads", err, calls)
				}
			}
		})
	}
}

func TestRPCRecoveryTransientBackoffAndStorage(t *testing.T) {
	r := recoveryState{NextBlock: 123}
	last := time.Duration(0)
	for i := 0; i < 9; i++ {
		next := recoveryNext(&r, errors.New("network_unavailable"), time.Now())
		delay := time.Until(next)
		if delay < last-time.Second || delay > 15*time.Minute {
			t.Fatal("backoff not bounded/increasing", delay)
		}
		last = delay
		r = decodeRecovery(encodeRecovery(r))
	}
	if r.NextBlock != 123 || r.Failures != 6 {
		t.Fatal("backoff/cursor not durable", r)
	}
	recoveryNext(&r, nil, time.Now())
	if r.Failures != 0 {
		t.Fatal("success did not reset failures")
	}
}

func TestStarlightKnownPendingReceiptNeverScans(t *testing.T) {
	cfg := starlightTestConfig()
	job := starlightJob{Key: strings.Repeat("a", 64), Recipient: "0x" + strings.Repeat("4", 40), Amount: 60, FromBlock: 100, TxHash: "0x" + strings.Repeat("b", 64)}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Method string }
		_ = json.NewDecoder(r.Body).Decode(&req)
		var result any
		switch req.Method {
		case "eth_call":
			result = starlightDigest(job)
		case "eth_getTransactionReceipt":
			result = nil
		default:
			t.Errorf("pending known receipt requested %s", req.Method)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"result": result})
	}))
	defer server.Close()
	cfg.StarlightRPC = server.URL
	service := &starlightService{client: newStarlightClient(cfg)}
	next := time.Now()
	for i := 0; i < 5; i++ {
		if err := service.advance(context.Background(), &job, &next); err != nil {
			t.Fatal(err)
		}
	}
	if job.Status != "confirming" || job.Generation != 0 || job.Recovery.NextBlock != 0 {
		t.Fatal("pending transaction resubmitted/scanned", job)
	}
}

func TestRecoveryDatabaseProgressAndSchedulesSurviveRestart(t *testing.T) {
	s := testStore(t)
	payload := publishedScore{Score: 900000}
	data, _ := json.Marshal(payload)
	params := map[string]interface{}{"payload": string(data)}
	_, err := s.query(`CREATE(j:LeaderboardPublication {key:'cursor-test',target:'test',owner:'a',board:'b',payload:$payload,sequence:0,created_at:0,status:'pending',next_attempt_at:0,lease_until:0,engine_id:'',tx_hash:'',generation:0,from_block:100,error_code:''}) RETURN j.key`, params)
	if err != nil {
		t.Fatal(err)
	}
	j, ok, err := s.claimPublication("test", time.Now())
	if err != nil || !ok {
		t.Fatal(err)
	}
	j.Recovery = recoveryState{NextBlock: 110, Failures: 3}
	next := time.Now().Add(time.Hour)
	if err = s.savePublication(j, next); err != nil {
		t.Fatal(err)
	}
	if _, ok, err = s.claimPublication("test", time.Now()); err != nil || ok {
		t.Fatal("ignored persisted delay", err)
	}
	restored, ok, err := s.claimPublication("test", next.Add(time.Second))
	if err != nil || !ok || restored.Recovery != j.Recovery || restored.FromBlock != 100 {
		t.Fatal("lost DB recovery state", restored, err)
	}
}

func TestStarlightRecoverySurvivesMissingEngineHistory(t *testing.T) {
	f := fakeStarlight(t)
	service := &starlightService{client: newStarlightClient(f.cfg)}
	job := f.job
	next := time.Now()
	if err := service.advance(context.Background(), &job, &next); err != nil {
		t.Fatal(err)
	}
	job.EngineID = "pruned-record"
	job.TxHash = ""
	if err := service.advance(context.Background(), &job, &next); err != nil {
		t.Fatal(err)
	}
	if job.Status != "confirmed" || f.transfers != 1 || f.posts != 1 {
		t.Fatal("missing Engine history prevented receipt recovery", job)
	}
	if time.Until(next) < 23*time.Hour {
		t.Fatal("confirmed payout scheduled for frequent polling")
	}
}

func TestRecoveryFailedPageNeverAdvancesCursor(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var req struct{ Method string }
		_ = json.NewDecoder(r.Body).Decode(&req)
		if req.Method == "eth_blockNumber" {
			_ = json.NewEncoder(w).Encode(map[string]any{"result": "0x1000"})
			return
		}
		w.WriteHeader(400)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"code": -32600, "message": "Under the Free tier plan: block range limit"}})
	}))
	defer server.Close()
	p := newPublicationClient(config{LeaderboardRPC: server.URL, RPCLogBlockRange: 10})
	state := recoveryState{NextBlock: 120}
	_, err := p.recoveryLogs(context.Background(), &state, 100, 3, "contract", []string{"event"})
	if err == nil || state.NextBlock != 120 || time.Until(recoveryNext(&state, err, time.Now())) < 59*time.Minute {
		t.Fatal("failed page lost progress/backoff", state, err)
	}
	_, _ = p.recoveryLogs(context.Background(), &state, 100, 3, "contract", []string{"event"})
	if calls != 2 {
		t.Fatal("failed page retried during cooldown", calls)
	}
}
