package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
)

func publicationConfig() config {
	c := testConfig()
	c.LeaderboardEnabled = true
	c.LeaderboardChainID = 421614
	c.LeaderboardConfirmations = 3
	c.EngineURL = "https://engine.example.test"
	c.EngineProjectID = "scene-project"
	c.LeaderboardAddress = "0x1111111111111111111111111111111111111111"
	c.LeaderboardPublisher = "0x2222222222222222222222222222222222222222"
	c.LeaderboardEngineKey = "fixture-only"
	c.LeaderboardRPC = "https://rpc.example.test"
	return c
}
func TestPublicationAtomicityOrderingAndBackfill(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	_, id := progressAccount(t, app, "publicationstore")
	cfg := publicationConfig()
	target := publicationTarget(cfg)
	chart := firstChart()
	p, v, err := s.ReadProgress(id)
	if err != nil {
		t.Fatal(err)
	}
	score := personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: 900000, MaxCombo: 100, AchievedAt: time.Now().UnixMilli(), RunID: strings.Repeat("1", 32)}
	p.publicationTarget = target
	p.rankedBest = &score
	p.XP = 100
	if ok, err := s.WriteProgress(id, v+1, p); err != nil || ok {
		t.Fatal("stale CAS succeeded", err)
	}
	r, err := s.query("MATCH(j:LeaderboardPublication) RETURN count(j)", nil)
	if err != nil || !r.Next() || r.Record().Values()[0].(int64) != 0 {
		t.Fatal("failed CAS created publication")
	}
	if ok, err := s.WriteProgress(id, v, p); err != nil || !ok {
		t.Fatal("write", err)
	}
	if ok, err := s.WriteProgress(id, v, p); err != nil || ok {
		t.Fatal("repeated CAS succeeded")
	}
	score.RunID = strings.Repeat("2", 32)
	score.Score = 950000
	p.XP = 200
	if ok, err := s.WriteProgress(id, v+1, p); err != nil || !ok {
		t.Fatal("improvement", err)
	}
	first, ok, err := s.claimPublication(target, time.Now())
	if err != nil || !ok || first.Payload.Score != 900000 {
		t.Fatalf("first claim: %+v %v", first, err)
	}
	if _, ok, err := s.claimPublication(target, time.Now()); err != nil || ok {
		t.Fatal("later score bypassed leased predecessor", err)
	}
	first.Status = "retrying"
	if err = s.savePublication(first, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, ok, err := s.claimPublication(target, time.Now()); err != nil || ok {
		t.Fatal("later score bypassed retrying predecessor", err)
	}
	first.Status = "confirmed"
	if err = s.savePublication(first, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	second, ok, err := s.claimPublication(target, time.Now())
	if err != nil || !ok || second.Payload.Score != 950000 {
		t.Fatalf("second claim: %+v %v", second, err)
	}
	if err = s.backfillPublications(target); err != nil {
		t.Fatal(err)
	}
	r, err = s.query("MATCH(j:LeaderboardPublication) RETURN count(j)", nil)
	if err != nil || !r.Next() || r.Record().Values()[0].(int64) != 2 {
		t.Fatal("backfill duplicated queue")
	}
	// A worse ranked replay may award progression, but creates no extra publication.
	score.RunID = strings.Repeat("3", 32)
	score.Score = 800000
	if ok, err := s.WriteProgress(id, v+2, p); err != nil || !ok {
		t.Fatal(err)
	}
	r, _ = s.query("MATCH(j:LeaderboardPublication) RETURN count(j)", nil)
	r.Next()
	if r.Record().Values()[0].(int64) != 2 {
		t.Fatal("worse replay published")
	}
	// A rotated credential retains the same target/queue namespace.
	rotated := cfg
	rotated.LeaderboardEngineKey = "rotated"
	if publicationTarget(rotated) != target {
		t.Fatal("key rotation changed namespace")
	}
}

func TestAutomaticPublicationWithLostResponseRestartAndReorg(t *testing.T) {
	for _, binary := range []string{"anvil", "forge", "cast"} {
		if _, err := exec.LookPath(binary); err != nil {
			t.Skip(binary + " required for local chain integration")
		}
	}
	s := testStore(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()
	cmd := exec.Command("anvil", "--host", "127.0.0.1", "--port", fmt.Sprint(port), "--silent")
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	rpcURL := fmt.Sprintf("http://127.0.0.1:%d", port)
	for i := 0; i < 100; i++ {
		conn, e := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Millisecond*100)
		if e == nil {
			_ = conn.Close()
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	owner := "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
	// Public Anvil fixture key, never a production credential.
	key := "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
	cast := func(args ...string) string {
		t.Helper()
		args = append([]string{args[0], "--rpc-url", rpcURL}, args[1:]...)
		out, e := exec.Command("cast", args...).CombinedOutput()
		if e != nil {
			t.Fatalf("cast: %v %s", e, out)
		}
		return strings.TrimSpace(string(out))
	}
	root, _ := filepath.Abs("../contracts")
	out, e := exec.Command("forge", "inspect", "--root", root, "ResceneLeaderboard", "bytecode").CombinedOutput()
	if e != nil {
		t.Fatalf("forge: %v %s", e, out)
	}
	bytecode := strings.TrimSpace(string(out))
	if !strings.HasPrefix(bytecode, "0x") {
		t.Fatalf("invalid bytecode %.100s", bytecode)
	}
	args := strings.Repeat("0", 24) + strings.TrimPrefix(owner, "0x")
	args += args + hex.EncodeToString(word(172800))
	hash := cast("send", "--async", "--private-key", key, "--create", bytecode+args)
	var deployment struct {
		ContractAddress string `json:"contractAddress"`
	}
	_ = json.Unmarshal([]byte(cast("receipt", hash, "--json")), &deployment)
	if deployment.ContractAddress == "" {
		t.Fatal("missing deployed address")
	}
	chart := firstChart()
	index := map[string]string{"Easy": "0", "Normal": "1", "Hard": "2", "Ultra Hard": "3"}[chart.Difficulty]
	cast("send", "--private-key", key, deployment.ContractAddress, "registerBoard(string,uint8,bytes32,uint32)", chart.SongID, index, "0x"+chart.Revision, fmt.Sprint(chart.Units))
	snapshot := cast("rpc", "evm_snapshot")
	upstream, _ := url.Parse(rpcURL)
	proxy := httputil.NewSingleHostReverseProxy(upstream)
	var mu sync.Mutex
	writes := 0
	lost := false
	txs := map[string]enginePublicationTx{}
	cfg := publicationConfig()
	cfg.LeaderboardChainID = 31337
	cfg.LeaderboardConfirmations = 1
	cfg.LeaderboardStartBlock = 0
	cfg.LeaderboardAddress = strings.ToLower(deployment.ContractAddress)
	cfg.LeaderboardPublisher = owner
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/rpc" {
			r.URL.Path = "/"
			proxy.ServeHTTP(w, r)
			return
		}
		if r.Header.Get("X-GMR-Engine-Key") != cfg.LeaderboardEngineKey {
			w.WriteHeader(401)
			return
		}
		if r.URL.Path == "/v1/auth/me" {
			_ = json.NewEncoder(w).Encode(map[string]any{"app": map[string]any{"id": cfg.EngineProjectID}})
			return
		}
		mu.Lock()
		defer mu.Unlock()
		if r.Method == "POST" && r.URL.Path == "/v1/contracts/write" {
			dedup := r.Header.Get("Idempotency-Key")
			if dedup == "" {
				w.WriteHeader(400)
				return
			}
			if prior, ok := txs[dedup]; ok {
				_ = json.NewEncoder(w).Encode(map[string]any{"transaction": prior})
				return
			}
			var body struct {
				ChainID  int64    `json:"chainId"`
				Address  string   `json:"contractAddress"`
				Wallet   string   `json:"walletAddress"`
				Function string   `json:"functionName"`
				Args     []string `json:"args"`
			}
			if json.NewDecoder(r.Body).Decode(&body) != nil {
				w.WriteHeader(400)
				return
			}
			var entry struct {
				Player string `json:"playerId"`
				Run    string `json:"runId"`
				Score  int    `json:"score"`
				Combo  int    `json:"maxCombo"`
				At     int64  `json:"achievedAt"`
			}
			_ = json.Unmarshal([]byte(body.Args[1]), &entry)
			tuple := fmt.Sprintf("(%s,%s,%d,%d,%d)", entry.Player, entry.Run, entry.Score, entry.Combo, entry.At)
			transactionHash := cast("send", "--async", "--private-key", key, body.Address, "submitScore(bytes32,(bytes16,bytes16,uint32,uint32,uint64))", body.Args[0], tuple)
			tx := enginePublicationTx{ID: fmt.Sprint(writes + 1), AppID: cfg.EngineProjectID, ChainID: body.ChainID, ContractAddress: body.Address, WalletAddress: body.Wallet, Method: body.Function, Args: body.Args, Status: "confirmed", Hash: transactionHash}
			writes++
			txs[dedup] = tx
			if !lost {
				lost = true
				conn, _, _ := w.(http.Hijacker).Hijack()
				_ = conn.Close()
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
			return
		}
		if strings.HasPrefix(r.URL.Path, "/v1/transactions/") {
			id := strings.TrimPrefix(r.URL.Path, "/v1/transactions/")
			for _, tx := range txs {
				if tx.ID == id {
					_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
					return
				}
			}
		}
		w.WriteHeader(404)
	}))
	defer server.Close()
	cfg.EngineURL = server.URL
	cfg.LeaderboardRPC = server.URL + "/rpc"
	base := testApp(t, s)
	token, id := progressAccount(t, base, "publishactual")
	run := rankedRun(t, base, s, token, id, chart)
	replay := fixtureReplay(chart, -1)
	replay.RunID = run
	result := replayResult(t, replay, chart)
	a := &api{store: s, config: cfg, replaySlots: make(chan struct{}, 2)}
	app := fiber.New()
	app.Post("/api/v1/runs/:id/complete", a.authenticate, a.completeRun)
	status, _, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", result, token)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", result, token)
	requireStatus(t, status, 200)
	client := newPublicationClient(cfg)
	client.http = server.Client()
	service := &publicationService{store: s, client: client, target: publicationTarget(cfg), ctx: context.Background()}
	drive := func() *publicationJob {
		t.Helper()
		for i := 0; i < 12; i++ {
			_, err = s.query("MATCH(j:LeaderboardPublication) SET j.next_attempt_at=0 RETURN j.key", nil)
			if err != nil {
				t.Fatal(err)
			}
			_ = service.process()
			board, _ := chartBoardKey(chart.SongID, chart.Difficulty, chart.Revision)
			job, e := s.publicationFor(publicationTarget(cfg), id, board)
			if e != nil || job == nil {
				t.Fatal("missing publication", e)
			}
			if job.Status == "confirmed" {
				return job
			}
			// Reconstructing the worker proves progress is persisted, not held in memory.
			service = &publicationService{store: s, client: client, target: publicationTarget(cfg), ctx: context.Background()}
		}
		t.Fatal("publication did not confirm")
		return nil
	}
	job := drive()
	if job.TxHash == "" {
		t.Fatal("confirmed without receipt")
	}
	mu.Lock()
	count := writes
	mu.Unlock()
	if count != 1 {
		t.Fatalf("lost response caused %d writes", count)
	}
	bests, _ := s.ReadBests(id)
	if len(bests) != 1 || bests[0].Score != job.Payload.Score {
		t.Fatal("chain payload differs from canonical result")
	}
	// Restore the chain before publication. The persisted DB receipt must be repaired.
	cast("rpc", "evm_revert", strings.Trim(snapshot, "\""))
	_, _ = s.query("MATCH(j:LeaderboardPublication) SET j.next_attempt_at=0 RETURN j.key", nil)
	if err = service.process(); err != nil {
		t.Fatal(err)
	}
	job = drive()
	if job.Generation != 1 {
		t.Fatal("reorg did not create a fresh Engine attempt")
	}
	mu.Lock()
	count = writes
	mu.Unlock()
	if count != 2 {
		t.Fatal("reorg repair did not publish exactly once")
	}
}

func TestPublicationReceiptRequiresExactEvidenceAndConfirmations(t *testing.T) {
	cfg := publicationConfig()
	chart := firstChart()
	board, _ := chartBoardKey(chart.SongID, chart.Difficulty, chart.Revision)
	job := publicationJob{TxHash: "0x" + strings.Repeat("ab", 32), Payload: publishedScore{PlayerID: strings.Repeat("1", 32), RunID: strings.Repeat("2", 32), BoardID: board, Score: 930000, MaxCombo: 100, AchievedAt: 1790000000000}}
	payload := append(word(930000), word(100)...)
	payload = append(payload, word(job.Payload.AchievedAt)...)
	payload = append(payload, word(1)...)
	log := scoreLog{Address: cfg.LeaderboardAddress, Topics: []string{scoreProcessedTopic, board, "0x" + paddedID(job.Payload.PlayerID), "0x" + paddedID(job.Payload.RunID)}, Data: "0x" + hex.EncodeToString(payload)}
	receipt := publicationReceipt{TxHash: job.TxHash, Status: "0x1", BlockHash: "0x" + strings.Repeat("cd", 32), BlockNumber: "0x10", Logs: []scoreLog{log}}
	head := "0x11"
	canonical := receipt.BlockHash
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Method string `json:"method"`
		}
		_ = json.NewDecoder(r.Body).Decode(&request)
		var result any
		switch request.Method {
		case "eth_getTransactionReceipt":
			result = receipt
		case "eth_blockNumber":
			result = head
		case "eth_getBlockByNumber":
			result = map[string]any{"hash": canonical}
		default:
			t.Errorf("unexpected method %s", request.Method)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": result})
	}))
	defer server.Close()
	cfg.LeaderboardRPC = server.URL
	p := newPublicationClient(cfg)
	p.http = server.Client()
	if ok, err := p.confirmed(context.Background(), job); err != nil || ok {
		t.Fatal("accepted too few confirmations", err)
	}
	head = "0x12"
	if ok, err := p.confirmed(context.Background(), job); err != nil || !ok {
		t.Fatal("rejected canonical confirmed receipt", err)
	}
	canonical = "0x" + strings.Repeat("ef", 32)
	if ok, err := p.confirmed(context.Background(), job); err != nil || ok {
		t.Fatal("accepted orphaned block", err)
	}
	canonical = receipt.BlockHash
	for _, mutate := range []func(*scoreLog){
		func(l *scoreLog) { l.Address = "0x" + strings.Repeat("f", 40) },
		func(l *scoreLog) {
			l.Topics = append([]string{}, l.Topics...)
			l.Topics[1] = "0x" + strings.Repeat("0", 64)
		},
		func(l *scoreLog) {
			l.Topics = append([]string{}, l.Topics...)
			l.Topics[2] = "0x" + strings.Repeat("0", 64)
		},
		func(l *scoreLog) { l.Data = "0x" },
		func(l *scoreLog) { l.Removed = true },
	} {
		bad := log
		mutate(&bad)
		receipt.Logs = []scoreLog{bad}
		if ok, err := p.confirmed(context.Background(), job); err == nil || ok {
			t.Fatal("accepted mismatched event")
		}
	}
}
