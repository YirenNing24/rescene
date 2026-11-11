package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"io"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func adminRequest(t *testing.T, app *fiber.App, cfg config, email, method, path string, body any, mfa bool) (int, map[string]any) {
	t.Helper()
	var raw []byte
	if body != nil {
		raw, _ = json.Marshal(body)
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	ts := fmt.Sprint(time.Now().Unix())
	nonce := randomAdminID()
	hash := sha256.Sum256(raw)
	mac := hmac.New(sha256.New, []byte(cfg.AdminKey))
	mac.Write([]byte(strings.Join([]string{method, path, email, ts, nonce, hex.EncodeToString(hash[:])}, "\n")))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Admin-Time", ts)
	req.Header.Set("X-Admin-Email", email)
	req.Header.Set("X-Admin-Nonce", nonce)
	req.Header.Set("X-Admin-Signature", hex.EncodeToString(mac.Sum(nil)))
	if mfa {
		token, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{"sub": email, "aud": "remine-admin-step", "exp": time.Now().Add(time.Hour).Unix()}).SignedString([]byte(cfg.AdminKey))
		req.Header.Set("Cookie", "__Host-remine_admin_step="+token)
	}
	res, e := app.Test(req, fiber.TestConfig{Timeout: 10 * time.Second})
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	var out map[string]any
	if json.Unmarshal(b, &out) != nil {
		t.Fatalf("bad JSON %d %s", res.StatusCode, b)
	}
	return res.StatusCode, out
}
func TestAdminGatewayMFAAndRoles(t *testing.T) {
	s := testStore(t)
	cfg := testConfig()
	cfg.AdminKey = strings.Repeat("g", 64)
	cfg.AdminOwner = "owner@example.com"
	cfg.AdminBootstrap = "fixture-access-key"
	app, e := newApp(s, cfg, bcrypt.MinCost)
	if e != nil {
		t.Fatal(e)
	}
	defer app.Shutdown()
	status, _, _ := request(t, app, "GET", "/api/admin/v1/session", nil, "")
	if status != 401 {
		t.Fatal("unsigned gateway accepted", status)
	}
	status, _ = adminRequest(t, app, cfg, cfg.AdminOwner, "GET", "/api/admin/v1/overview", nil, false)
	if status != 428 {
		t.Fatal("MFA bypass", status)
	}
	status, result := adminRequest(t, app, cfg, cfg.AdminOwner, "GET", "/api/admin/v1/overview", nil, true)
	if status != 200 {
		t.Fatal(status, result)
	}
	status, result = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/login", map[string]any{"key": cfg.AdminBootstrap}, false)
	if status != 200 {
		t.Fatal(status, result)
	}
	_, e = s.query(`CREATE(a:AdminIdentity {email:'analyst@example.com',role:'analyst',status:'active'})`, nil)
	if e != nil {
		t.Fatal(e)
	}
	status, result = adminRequest(t, app, cfg, "analyst@example.com", "POST", "/api/admin/v1/documents/settings", map[string]any{"name": "Controls", "reason": "fixture test", "status": "published", "revision": 0, "value": map[string]any{"maintenance": true}}, true)
	if status != 403 {
		t.Fatal("role bypass", status, result)
	}
}
func TestAdminDocumentCASAndOperationIdempotency(t *testing.T) {
	s := testStore(t)
	cfg := testConfig()
	cfg.AdminKey = strings.Repeat("d", 64)
	cfg.AdminOwner = "owner@example.com"
	app, e := newApp(s, cfg, bcrypt.MinCost)
	if e != nil {
		t.Fatal(e)
	}
	defer app.Shutdown()
	doc := map[string]any{"id": randomAdminID(), "name": "Test controls", "reason": "Fixture validation", "status": "published", "revision": 0, "value": map[string]any{"runs_paused": true}}
	status, v := adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/documents/settings", doc, true)
	if status != 200 {
		t.Fatal(status, v)
	}
	status, v = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/documents/settings", doc, true)
	if status != 409 {
		t.Fatal("stale save accepted", status, v)
	}
	p := map[string]any{"id": randomAdminID(), "kind": "suspend", "reason": "Fixture moderation test", "payload": map[string]any{"player_id": strings.Repeat("0", 32)}}
	for i := 0; i < 2; i++ {
		status, v = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/operations", p, true)
		if status != 200 {
			t.Fatal(status, v)
		}
	}
	p["kind"] = "restore"
	status, v = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/operations", p, true)
	if status != 409 {
		t.Fatal("intent changed", status, v)
	}
}
func TestAdminTOTPAndAllowlist(t *testing.T) {
	if !verifyAdminTOTP("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "287082", time.Unix(59, 0)) {
		t.Fatal("RFC6238 vector rejected")
	}
	if verifyAdminTOTP("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "000000", time.Unix(59, 0)) {
		t.Fatal("wrong code accepted")
	}
	s := &adminSystem{api: &api{config: config{}}}
	if _, _, e := s.adminChainSpec("generate_card", randomAdminID(), nil); e == nil {
		t.Fatal("unconfigured generation accepted")
	}
	if _, _, e := s.adminChainSpec("pulse_sales", randomAdminID(), map[string]any{"enabled": true}); e == nil {
		t.Fatal("unbounded sales accepted")
	}
	if e := validateAdminSettings(map[string]any{"xp_multiplier": 2.0}); e == nil {
		t.Fatal("unsupported live setting accepted")
	}
}

func TestAdminPlayerActionsAndSessionEnforcement(t *testing.T) {
	s := testStore(t)
	cfg := testConfig()
	cfg.AdminKey = strings.Repeat("p", 64)
	cfg.AdminOwner = "owner@example.com"
	app, e := newApp(s, cfg, bcrypt.MinCost)
	if e != nil {
		t.Fatal(e)
	}
	defer app.Shutdown()
	token, id := progressAccount(t, app, "adminplayertest")
	admin := &adminSystem{api: &api{store: s, config: cfg}, db: s, key: []byte(cfg.AdminKey), flags: map[string]any{}}
	p := map[string]any{"player_id": id, "amount": float64(30)}
	op := randomAdminID()
	for i := 0; i < 2; i++ {
		if _, e := admin.executeLocal(op, "grant_xp", p); e != nil {
			t.Fatal(e)
		}
	}
	progress, _, _ := s.ReadProgress(id)
	if progress.XP != 30 {
		t.Fatal("duplicate grant", progress.XP)
	}
	if _, e = admin.executeLocal(randomAdminID(), "suspend", p); e != nil {
		t.Fatal(e)
	}
	status, v, _ := request(t, app, "GET", "/api/v1/progression", nil, token)
	if status != 403 {
		t.Fatal("suspension bypass", status, v)
	}
	if _, e = admin.executeLocal(randomAdminID(), "restore", p); e != nil {
		t.Fatal(e)
	}
	status, v, _ = request(t, app, "GET", "/api/v1/progression", nil, token)
	if status != 200 {
		t.Fatal(status, v)
	}
	if _, e = admin.executeLocal(randomAdminID(), "revoke_sessions", p); e != nil {
		t.Fatal(e)
	}
	status, v, _ = request(t, app, "GET", "/api/v1/progression", nil, token)
	if status != 401 {
		t.Fatal("revoked token accepted", status, v)
	}
}
func TestAdminABIEncodingAndListingPolicy(t *testing.T) {
	addr := "0x" + strings.Repeat("1", 40)
	call, e := buildAdminCall(addr, addr, "mintTo", []string{"address", "uint256", "string", "uint256"}, []string{addr, "11", "ipfs://reviewed", "5"})
	if e != nil || len(call.Data)%64 != 10 || !strings.HasPrefix(call.Data, selector("mintTo(address,uint256,string,uint256)")) {
		t.Fatal(call, e)
	}
	if _, e = buildAdminCall(addr, addr, "test", []string{"uint128"}, []string{"340282366920938463463374607431768211456"}); e == nil {
		t.Fatal("uint128 overflow")
	}
	s := &adminSystem{api: &api{config: config{MarketplaceAddress: addr, MarketplaceCollection: addr, StarlightToken: addr, StarlightTreasury: addr}}}
	p := map[string]any{"token_id": float64(1), "quantity": float64(10), "price": float64(450), "starts_at": float64(time.Now().Unix()), "ends_at": float64(time.Now().Add(time.Hour).Unix())}
	call, e = s.adminListingCall("listing_create", p)
	if e != nil || !strings.HasPrefix(call.Data, selector("createListing((address,uint256,uint256,address,uint256,uint128,uint128,bool))")) {
		t.Fatal(call, e)
	}
	p["price"] = float64(1)
	if _, e = s.adminListingCall("listing_create", p); e == nil {
		t.Fatal("immutable router price bypass")
	}
}

func TestAdminAuthenticatorEnrollmentAndReplay(t *testing.T) {
	s := testStore(t)
	cfg := testConfig()
	cfg.AdminKey = strings.Repeat("m", 64)
	cfg.AdminOwner = "owner@example.com"
	app, e := newApp(s, cfg, bcrypt.MinCost)
	if e != nil {
		t.Fatal(e)
	}
	defer app.Shutdown()
	status, out := adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/mfa/enroll", map[string]any{}, false)
	if status != 200 {
		t.Fatal(status, out)
	}
	secret := out["secret"].(string)
	key, _ := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, uint64(time.Now().Unix()/30))
	mac := hmac.New(sha1.New, key)
	mac.Write(b)
	digest := mac.Sum(nil)
	o := digest[len(digest)-1] & 15
	code := fmt.Sprintf("%06d", (binary.BigEndian.Uint32(digest[o:o+4])&0x7fffffff)%1000000)
	status, out = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/mfa/verify", map[string]any{"code": code}, false)
	if status != 200 {
		t.Fatal(status, out)
	}
	status, out = adminRequest(t, app, cfg, cfg.AdminOwner, "POST", "/api/admin/v1/mfa/verify", map[string]any{"code": code}, false)
	if status != 401 {
		t.Fatal("replayed code accepted", status, out)
	}
	rows, _ := s.adminRows(`MATCH(a:AdminIdentity) RETURN a.totp`, nil, "secret")
	if rows[0]["secret"] == secret || rows[0]["secret"] == "" {
		t.Fatal("authenticator secret is not encrypted")
	}
}

func TestAdminCompatibleLegacyCatalog(t *testing.T) {
	cfg := config{CardsEnabled: true, CardsRouter: "0x" + strings.Repeat("1", 40), LegacyCardsRouter: "0x" + strings.Repeat("1", 40)}
	client := newShopClient(cfg)
	ids := client.itemIDs()
	if len(ids) != 6 || ids[1] != "legacy_scene_01" {
		t.Fatal("legacy deployment advertises incompatible products", ids)
	}
	inventory := client.inventoryIDs()
	if len(inventory) != 6 {
		t.Fatal("duplicate inventory IDs", inventory)
	}
	card, e := client.forItem(ids[1])
	if e != nil || card.cfg.ShopTokenID != 1 || card.firstID(card.cfg.ShopTokenID) != 1 {
		t.Fatal("preflight uses incompatible legacy IDs", e)
	}
}
