package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

func testStore(t *testing.T) *graphStore {
	t.Helper()
	url := os.Getenv("FALKORDB_TEST_URL")
	if url == "" {
		t.Skip("set FALKORDB_TEST_URL to run real FalkorDB integration tests")
	}
	id := make([]byte, 8)
	_, _ = rand.Read(id)
	s, err := openStore(url, "rescene_test_"+hex.EncodeToString(id))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := s.graph.Delete(); err != nil {
			t.Error(err)
		}
		_ = s.Close()
	})
	return s
}
func testConfig() config {
	return config{Secret: []byte(strings.Repeat("test-secret-", 4)), TokenTTL: time.Hour}
}
func testApp(t *testing.T, s userStore) *fiber.App {
	t.Helper()
	app, err := newApp(s, testConfig(), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = app.Shutdown() })
	return app
}
func request(t *testing.T, app *fiber.App, method, path string, body any, token string) (int, map[string]any, http.Header) {
	t.Helper()
	var raw []byte
	if text, ok := body.(string); ok {
		raw = []byte(text)
	} else if body != nil {
		var err error
		raw, err = json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := app.Test(req, fiber.TestConfig{Timeout: 10 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	content, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	if err = json.Unmarshal(content, &result); err != nil {
		t.Fatalf("non-JSON response status %d", res.StatusCode)
	}
	if strings.Contains(string(content), "password_hash") {
		t.Fatal("password hash exposed")
	}
	return res.StatusCode, result, res.Header
}
func creds(name, password string) map[string]any {
	return map[string]any{"username": name, "password": password, "accept_policies": true, "terms_version": legalPolicyVersion, "privacy_version": legalPolicyVersion}
}
func requireStatus(t *testing.T, got, want int) {
	t.Helper()
	if got != want {
		t.Fatalf("status %d; want %d", got, want)
	}
}

func TestAccountLifecycle(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	status, body, headers := request(t, app, "POST", "/api/v1/auth/register", creds("RePlayer", "a secure password!"), "")
	requireStatus(t, status, 201)
	if headers.Get("Cache-Control") != "no-store" {
		t.Fatal("session must not be cached")
	}
	token := body["access_token"].(string)
	account := body["user"].(map[string]any)
	stored, err := s.ByUsername("replayer")
	if err != nil {
		t.Fatal(err)
	}
	if stored.PasswordHash == "a secure password!" || bcrypt.CompareHashAndPassword([]byte(stored.PasswordHash), []byte("a secure password!")) != nil {
		t.Fatal("password not hashed correctly")
	}
	status, me, _ := request(t, app, "GET", "/api/v1/auth/me", nil, token)
	requireStatus(t, status, 200)
	if me["user"].(map[string]any)["id"] != account["id"] {
		t.Fatal("JWT subject did not identify account")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/auth/register", creds("REPLAYER", "different password"), "")
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/login", creds(" rePLAYER ", "a secure password!"), "")
	requireStatus(t, status, 200)
	status, bad, _ := request(t, app, "POST", "/api/v1/auth/login", creds("replayer", "wrong password"), "")
	requireStatus(t, status, 401)
	status, missing, _ := request(t, app, "POST", "/api/v1/auth/login", creds("NobodyHere", "wrong password"), "")
	requireStatus(t, status, 401)
	if fmt.Sprint(bad) != fmt.Sprint(missing) {
		t.Fatal("login enumerates users")
	}
	// A second connection simulates a restart: accounts and original hashes survive.
	s2, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	account2, err := s2.ByID(stored.ID)
	if err != nil || account2.PasswordHash != stored.PasswordHash {
		t.Fatal("account was not persisted")
	}
	status, _, _ = request(t, app, "GET", "/healthz", nil, "")
	requireStatus(t, status, 200)
}

func TestValidationAndLimits(t *testing.T) {
	s := testStore(t)
	cases := []any{`{`, `null`, `{"username":"valid","password":"password123","admin":true}`, `{"username":"valid","password":"password123"} {}`, creds("bad'name", "password123"), creds("ab", "password123"), creds("valid", "short"), creds("valid", strings.Repeat("x", 73)), creds("valid", strings.Repeat("界", 25))}
	for i, body := range cases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			app := testApp(t, s)
			status, _, _ := request(t, app, "POST", "/api/v1/auth/register", body, "")
			requireStatus(t, status, 400)
		})
	}
	app := testApp(t, s)
	for i := 0; i < 6; i++ {
		status, _, headers := request(t, app, "POST", "/api/v1/auth/register", creds("rateuser", "short"), "")
		if i == 5 {
			requireStatus(t, status, 429)
			if headers.Get("Retry-After") == "" {
				t.Fatal("missing retry delay")
			}
		}
	}
	status, _, _ := request(t, app, "GET", "/missing", nil, "")
	requireStatus(t, status, 404)
}

func TestJWTRejection(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	_, body, _ := request(t, app, "POST", "/api/v1/auth/register", creds("jwtuser", "password123"), "")
	id := body["user"].(map[string]any)["id"].(string)
	validClaims := func() jwt.RegisteredClaims {
		return jwt.RegisteredClaims{Subject: id, Issuer: issuer, Audience: jwt.ClaimStrings{audience}, ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)), IssuedAt: jwt.NewNumericDate(time.Now())}
	}
	for _, kind := range []string{"missing", "garbage", "forged", "expired", "no_expiry", "issuer", "audience", "algorithm", "no_subject", "deleted_user", "future"} {
		t.Run(kind, func(t *testing.T) {
			claims := validClaims()
			method := jwt.SigningMethodHS256
			secret := testConfig().Secret
			switch kind {
			case "forged":
				secret = []byte("an attacker key with sufficient bytes")
			case "expired":
				claims.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Minute))
			case "no_expiry":
				claims.ExpiresAt = nil
			case "issuer":
				claims.Issuer = "other"
			case "audience":
				claims.Audience = jwt.ClaimStrings{"other"}
			case "algorithm":
				method = jwt.SigningMethodHS384
			case "no_subject":
				claims.Subject = ""
			case "deleted_user":
				claims.Subject = "nonexistent"
			case "future":
				claims.IssuedAt = jwt.NewNumericDate(time.Now().Add(time.Hour))
			}
			token, err := jwt.NewWithClaims(method, claims).SignedString(secret)
			if err != nil {
				t.Fatal(err)
			}
			if kind == "missing" {
				token = ""
			}
			if kind == "garbage" {
				token = "garbage"
			}
			status, _, _ := request(t, app, "GET", "/api/v1/auth/me", nil, token)
			requireStatus(t, status, 401)
		})
	}
}

func TestConcurrentRegistration(t *testing.T) {
	s := testStore(t)
	var wg sync.WaitGroup
	results := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			// Independent graph clients ensure this tests database atomicity,
			// not just the process-local decoder lock.
			other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
			if err != nil {
				results <- err
				return
			}
			defer other.Close()
			_, err = other.Create(user{ID: fmt.Sprint(i), Username: "Concurrent", CreatedAt: "now", PasswordHash: "hash"}, "concurrent")
			results <- err
		}(i)
	}
	wg.Wait()
	close(results)
	created, duplicate := 0, 0
	for err := range results {
		if err == nil {
			created++
		} else if err == errDuplicate {
			duplicate++
		} else {
			t.Error(err)
		}
	}
	if created != 1 || duplicate != 7 {
		t.Fatalf("created %d duplicates %d", created, duplicate)
	}
}

func TestConfiguration(t *testing.T) {
	t.Setenv("DATA_DIR", t.TempDir())
	t.Setenv("APP_ENV", "development")
	t.Setenv("JWT_SECRET", "")
	t.Setenv("JWT_TTL", "1h")
	one, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	two, err := loadConfig()
	if err != nil || !bytes.Equal(one.Secret, two.Secret) {
		t.Fatal("development signing key must survive restart")
	}
	t.Setenv("APP_ENV", "production")
	if _, err := loadConfig(); err == nil {
		t.Fatal("production accepted missing secret")
	}
	t.Setenv("JWT_SECRET", "short")
	if _, err := loadConfig(); err == nil {
		t.Fatal("short secret accepted")
	}
	t.Setenv("JWT_SECRET", strings.Repeat("x", 64))
	t.Setenv("JWT_TTL", "0s")
	if _, err := loadConfig(); err == nil {
		t.Fatal("invalid expiry accepted")
	}
}
