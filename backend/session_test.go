package main

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func refreshBody(token string, sequence int) map[string]string {
	return map[string]string{"refresh_token": token, "request_id": fmt.Sprintf("%032x", sequence)}
}

func sessionToken(t *testing.T, body map[string]any) string {
	t.Helper()
	token, ok := body["refresh_token"].(string)
	if !ok || !validRefreshToken(token) {
		t.Fatal("missing or invalid refresh token")
	}
	remaining, ok := body["refresh_expires_in"].(float64)
	if !ok || remaining < float64(refreshLifetime.Seconds())-3 || remaining > float64(refreshLifetime.Seconds()) {
		t.Fatal("refresh session should last 30 days")
	}
	return token
}

func TestRefreshLifecycle(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	status, initial, _ := request(t, app, "POST", "/api/v1/auth/register", creds("refreshplayer", "password123"), "")
	requireStatus(t, status, 201)
	first := sessionToken(t, initial)
	owner := initial["user"].(map[string]any)["id"].(string)
	// Refresh tokens must never be usable as access JWTs.
	status, _, _ = request(t, app, "GET", "/api/v1/auth/me", nil, first)
	requireStatus(t, status, 401)
	status, logged, _ := request(t, app, "POST", "/api/v1/auth/login", creds("refreshplayer", "password123"), "")
	requireStatus(t, status, 200)
	second := sessionToken(t, logged)
	if first == second || initial["access_token"] == logged["access_token"] {
		t.Fatal("login must renew both tokens")
	}
	status, rotated, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(first, 1), "")
	requireStatus(t, status, 200)
	third := sessionToken(t, rotated)
	if third == first || rotated["user"].(map[string]any)["id"] != owner {
		t.Fatal("refresh lost identity or did not rotate")
	}
	status, _, _ = request(t, app, "GET", "/api/v1/auth/me", nil, rotated["access_token"].(string))
	requireStatus(t, status, 200)
	// Exact retries recover a lost response. Another request cannot reuse the old token.
	status, retried, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(first, 1), "")
	requireStatus(t, status, 200)
	if retried["refresh_token"] != third || retried["refresh_expires_at"] != rotated["refresh_expires_at"] {
		t.Fatal("retry must recover the same token without extending expiry again")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(first, 2), "")
	requireStatus(t, status, 401)
	status, fourth, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(third, 3), "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(first, 1), "")
	requireStatus(t, status, 401)
	// Raw refresh tokens never appear in graph properties.
	r, err := s.query(`MATCH (:User {id:$id})-[:HAS_LOGIN_SESSION]->(s:LoginSession) RETURN s.token_hash,s.previous_hash`, map[string]interface{}{"id": owner})
	if err != nil {
		t.Fatal(err)
	}
	for r.Next() {
		for i := 0; i < 2; i++ {
			value, _ := r.Record().GetByIndex(i)
			if text, ok := value.(string); ok && len(text) != 64 {
				t.Fatal("session did not store a SHA-256 digest")
			}
		}
	}
	// Logging out one device does not revoke another device's independent login.
	status, _, _ = request(t, app, "POST", "/api/v1/auth/logout", map[string]string{"refresh_token": fourth["refresh_token"].(string)}, "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(fourth["refresh_token"].(string), 4), "")
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(second, 5), "")
	requireStatus(t, status, 200)
}

func TestRefreshExpiryPersistenceAndMigration(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	status, initial, _ := request(t, app, "POST", "/api/v1/auth/register", creds("expirysession", "password123"), "")
	requireStatus(t, status, 201)
	token := sessionToken(t, initial)
	now := time.Now().Unix()
	_, err := s.query(`MATCH (s:LoginSession {token_hash:$hash}) SET s.expires_at=$expires`, map[string]interface{}{"hash": refreshHash(token), "expires": now + 1})
	if err != nil {
		t.Fatal(err)
	}
	status, renewed, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(token, 1), "")
	requireStatus(t, status, 200)
	newToken := sessionToken(t, renewed)
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	otherApp := testApp(t, other)
	status, _, _ = request(t, otherApp, "POST", "/api/v1/auth/refresh", refreshBody(token, 1), "")
	requireStatus(t, status, 200)
	_, err = other.query(`MATCH (s:LoginSession {token_hash:$hash}) SET s.expires_at=$expires`, map[string]interface{}{"hash": refreshHash(newToken), "expires": time.Now().Unix() - 1})
	if err != nil {
		t.Fatal(err)
	}
	status, _, _ = request(t, otherApp, "POST", "/api/v1/auth/refresh", refreshBody(newToken, 2), "")
	requireStatus(t, status, 401)
	// A valid legacy access token can upgrade; expired/forged tokens cannot.
	status, _, _ = request(t, app, "POST", "/api/v1/auth/session", map[string]any{}, initial["access_token"].(string))
	requireStatus(t, status, 200)
	u := initial["user"].(map[string]any)
	claims := jwt.RegisteredClaims{Subject: u["id"].(string), Issuer: issuer, Audience: jwt.ClaimStrings{audience}, ExpiresAt: jwt.NewNumericDate(time.Now().Add(-time.Hour))}
	expired, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(testConfig().Secret)
	if err != nil {
		t.Fatal(err)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/auth/session", map[string]any{}, expired)
	requireStatus(t, status, 401)
}

func TestRefreshConcurrentRotation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	status, initial, _ := request(t, app, "POST", "/api/v1/auth/register", creds("concurrentsession", "password123"), "")
	requireStatus(t, status, 201)
	token := sessionToken(t, initial)
	var wg sync.WaitGroup
	results := make(chan int, 8)
	for i := 1; i <= 8; i++ {
		wg.Go(func() {
			status, _, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(token, i), "")
			results <- status
		})
	}
	wg.Wait()
	close(results)
	winners := 0
	for status := range results {
		if status == 200 {
			winners++
		} else if status != 401 {
			t.Fatalf("rotation status %d", status)
		}
	}
	if winners != 1 {
		t.Fatalf("concurrent rotation accepted %d different requests", winners)
	}
}

func TestRefreshValidationAndLogoutRecovery(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	for _, body := range []any{`{}`, refreshBody("not-a-token", 1), map[string]string{"refresh_token": strings.Repeat("a", 43), "request_id": "bad"}} {
		status, _, _ := request(t, app, "POST", "/api/v1/auth/refresh", body, "")
		requireStatus(t, status, 401)
	}
	status, initial, _ := request(t, app, "POST", "/api/v1/auth/register", creds("logoutsession", "password123"), "")
	requireStatus(t, status, 201)
	token := sessionToken(t, initial)
	status, next, _ := request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(token, 1), "")
	requireStatus(t, status, 200)
	// If logout races a refresh response, its old credential still revokes the successor.
	status, _, _ = request(t, app, "POST", "/api/v1/auth/logout", map[string]string{"refresh_token": token}, "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(next["refresh_token"].(string), 2), "")
	requireStatus(t, status, 401)
}
