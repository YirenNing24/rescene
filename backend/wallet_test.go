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
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
)

const fakeEngineKey = "engine-test-secret-never-return-to-the-game"
const fakeProject = "test-project"

type fakeWalletEngine struct {
	mu              sync.Mutex
	server          *httptest.Server
	wallets         map[string]engineWallet
	calls           int
	failAfterCreate bool
}

func fakeEngine(t *testing.T) *fakeWalletEngine {
	t.Helper()
	e := &fakeWalletEngine{wallets: map[string]engineWallet{}}
	e.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/user-wallets/managed" || r.Method != "POST" {
			t.Errorf("unexpected Engine route %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
			return
		}
		if r.Header.Get("X-GMR-Engine-Key") != fakeEngineKey {
			t.Error("missing server Engine credential")
			w.WriteHeader(401)
			return
		}
		var body map[string]string
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			w.WriteHeader(400)
			return
		}
		if body["authProvider"] != walletAuthProvider || body["userID"] == "" {
			t.Error("wallet has no stable player identity")
			w.WriteHeader(400)
			return
		}
		e.mu.Lock()
		defer e.mu.Unlock()
		e.calls++
		wallet, ok := e.wallets[body["userID"]]
		if !ok {
			wallet = engineWallet{ID: fmt.Sprintf("engine-wallet-%d", len(e.wallets)+1), AppID: fakeProject, UserID: body["userID"], AuthProvider: walletAuthProvider, Address: fmt.Sprintf("0x%040x", len(e.wallets)+1), WalletCustody: "managed", WalletType: "managed_user", Status: "active", CreatedAt: time.Now().UTC().Format(time.RFC3339)}
			e.wallets[body["userID"]] = wallet
		}
		if e.failAfterCreate {
			e.failAfterCreate = false
			w.WriteHeader(503)
			_, _ = w.Write([]byte(fakeEngineKey))
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"wallet": wallet, "privateKey": "must-never-propagate"})
	}))
	t.Cleanup(e.server.Close)
	return e
}
func walletTestConfig(e *fakeWalletEngine) config {
	cfg := testConfig()
	cfg.EngineURL = e.server.URL
	cfg.EngineAPIKey = fakeEngineKey
	cfg.EngineProjectID = fakeProject
	return cfg
}
func waitWallet(t *testing.T, s *graphStore, id string, cfg config) walletInfo {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		w, err := s.ReadWallet(id, cfg.EngineProjectID, cfg.EngineURL)
		if err != nil {
			t.Fatal(err)
		}
		if w.Status == "ready" {
			return w
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("wallet was not provisioned")
	return walletInfo{}
}

func TestWalletLifecycleAndBackfill(t *testing.T) {
	s := testStore(t)
	e := fakeEngine(t)
	cfg := walletTestConfig(e)
	_, err := s.Create(user{ID: "existing-user", Username: "Existing", CreatedAt: "now", PasswordHash: "hash"}, "existing")
	if err != nil {
		t.Fatal(err)
	}
	app, err := newApp(s, cfg, bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = app.Shutdown() })
	existing := waitWallet(t, s, "existing-user", cfg)
	token, id := progressAccount(t, app, "walletplayer")
	wallet := waitWallet(t, s, id, cfg)
	if wallet.ID == existing.ID || wallet.Address == existing.Address {
		t.Fatal("players share a wallet")
	}
	for i := 0; i < 3; i++ {
		status, body, _ := request(t, app, "GET", "/api/v1/wallet?user_id=existing-user", nil, token)
		requireStatus(t, status, 200)
		if body["wallet"].(map[string]any)["id"] != wallet.ID {
			t.Fatal("wallet endpoint leaked another account")
		}
		raw, _ := json.Marshal(body)
		if strings.Contains(string(raw), fakeEngineKey) || strings.Contains(string(raw), "privateKey") {
			t.Fatal("secret exposed")
		}
	}
	status, body, _ := request(t, app, "GET", "/api/v1/auth/me", nil, token)
	requireStatus(t, status, 200)
	if body["user"].(map[string]any)["wallet"].(map[string]any)["address"] != wallet.Address {
		t.Fatal("profile lacks wallet")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/wallet/provision", map[string]string{"userID": "existing-user"}, token)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "GET", "/api/v1/wallet", nil, "")
	requireStatus(t, status, 401)
	// Restarting API workers must use the stored link instead of creating again.
	_ = app.Shutdown()
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	service, err := startWalletService(other, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer service.close()
	got, err := service.public(id)
	if err != nil || got.ID != wallet.ID {
		t.Fatal("wallet link did not persist")
	}
	time.Sleep(30 * time.Millisecond)
	e.mu.Lock()
	defer e.mu.Unlock()
	if len(e.wallets) != 2 || e.calls != 2 {
		t.Fatalf("unexpected wallet creations: calls=%d users=%d", e.calls, len(e.wallets))
	}
}

func TestWalletDistributedLease(t *testing.T) {
	s := testStore(t)
	e := fakeEngine(t)
	cfg := walletTestConfig(e)
	_, err := s.Create(user{ID: "lease-user", Username: "Lease", CreatedAt: "now", PasswordHash: "hash"}, "lease")
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.ReadWallet("lease-user", cfg.EngineProjectID, cfg.EngineURL)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	claims := make(chan bool, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
			if err != nil {
				t.Error(err)
				return
			}
			defer other.Close()
			ok, err := other.ClaimWallet("lease-user", cfg.EngineProjectID, cfg.EngineURL, fmt.Sprint(i), time.Now())
			if err != nil {
				t.Error(err)
			}
			claims <- ok
		}(i)
	}
	wg.Wait()
	close(claims)
	count := 0
	for ok := range claims {
		if ok {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("claimed lease %d times", count)
	}
	ok, err := s.SaveWallet("lease-user", cfg.EngineProjectID, cfg.EngineURL, "wrong-owner", walletInfo{ID: "bad", Address: "0x0000000000000000000000000000000000000001"})
	if err != nil || ok {
		t.Fatal("wrong lease can write wallet")
	}
}

func TestWalletAmbiguousFailureRecovery(t *testing.T) {
	s := testStore(t)
	e := fakeEngine(t)
	e.failAfterCreate = true
	cfg := walletTestConfig(e)
	_, err := s.Create(user{ID: "retry-user", Username: "Retry", CreatedAt: "now", PasswordHash: "hash"}, "retry")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	service := &walletService{store: s, engine: newWalletEngine(cfg), ctx: ctx}
	service.provision("retry-user")
	w, err := s.ReadWallet("retry-user", cfg.EngineProjectID, cfg.EngineURL)
	if err != nil || w.Status != "retrying" {
		t.Fatal("upstream failure did not remain retryable")
	}
	service.provision("retry-user")
	e.mu.Lock()
	calls := e.calls
	e.mu.Unlock()
	if calls != 1 {
		t.Fatal("backoff/lease did not block immediate retry")
	}
	_, err = s.query(`MATCH (w:Wallet {key:$key}) SET w.lease_until=0,w.next_attempt_at=0 RETURN w.key`, map[string]interface{}{"key": walletKey("retry-user", cfg.EngineProjectID, cfg.EngineURL)})
	if err != nil {
		t.Fatal(err)
	}
	service.provision("retry-user")
	w, err = s.ReadWallet("retry-user", cfg.EngineProjectID, cfg.EngineURL)
	if err != nil || w.Status != "ready" {
		t.Fatal("wallet could not recover")
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if len(e.wallets) != 1 || e.calls != 2 {
		t.Fatal("lost upstream response created a second managed wallet")
	}
}

func TestWalletResponseValidation(t *testing.T) {
	for _, kind := range []string{"wrong_project", "wrong_user", "wrong_provider", "external_custody", "bad_address", "zero_address", "empty_id", "unauthorized", "redirect"} {
		t.Run(kind, func(t *testing.T) {
			redirectCalls := 0
			target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { redirectCalls++; w.WriteHeader(200) }))
			defer target.Close()
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				wallet := engineWallet{ID: "wallet-id", AppID: fakeProject, UserID: "player", AuthProvider: walletAuthProvider, Address: "0x0000000000000000000000000000000000000001", WalletCustody: "managed", WalletType: "managed_user", Status: "active"}
				switch kind {
				case "wrong_project":
					wallet.AppID = "other"
				case "wrong_user":
					wallet.UserID = "other"
				case "wrong_provider":
					wallet.AuthProvider = "other"
				case "external_custody":
					wallet.WalletCustody = "external"
				case "bad_address":
					wallet.Address = "bad"
				case "zero_address":
					wallet.Address = "0x0000000000000000000000000000000000000000"
				case "empty_id":
					wallet.ID = ""
				case "unauthorized":
					w.WriteHeader(403)
					_, _ = w.Write([]byte(fakeEngineKey))
					return
				case "redirect":
					http.Redirect(w, r, target.URL, 307)
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"wallet": wallet})
			}))
			defer server.Close()
			engine := newWalletEngine(config{EngineURL: server.URL, EngineAPIKey: fakeEngineKey, EngineProjectID: fakeProject})
			_, err := engine.ensure(context.Background(), "player")
			if err == nil {
				t.Fatal("invalid upstream response accepted")
			}
			if strings.Contains(err.Error(), fakeEngineKey) {
				t.Fatal("error leaked credential")
			}
			if redirectCalls != 0 {
				t.Fatal("redirect received the server credential")
			}
		})
	}
}

func TestWalletConfiguration(t *testing.T) {
	t.Setenv("JWT_SECRET", strings.Repeat("x", 64))
	t.Setenv("JWT_TTL", "1h")
	t.Setenv("APP_ENV", "production")
	t.Setenv("ENGINE_API_KEY", fakeEngineKey)
	t.Setenv("ENGINE_PROJECT_ID", fakeProject)
	for _, invalid := range []string{"http://engine.example", "https://user:password@engine.example", "https://engine.example?key=secret", "https:///missing-host", "https://engine.example#fragment"} {
		t.Setenv("ENGINE_BASE_URL", invalid)
		if _, err := loadConfig(); err == nil {
			t.Fatal("unsafe Engine URL accepted")
		}
	}
	t.Setenv("ENGINE_BASE_URL", "https://engine.example")
	if _, err := loadConfig(); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENGINE_PROJECT_ID", "")
	if _, err := loadConfig(); err == nil {
		t.Fatal("unbound Engine project accepted")
	}
	t.Setenv("ENGINE_API_KEY", "")
	if _, err := loadConfig(); err != nil {
		t.Fatal("disabled wallet integration must still allow local auth tests")
	}
}
