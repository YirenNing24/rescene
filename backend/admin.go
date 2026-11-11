package main

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/limiter"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type adminSystem struct {
	api     *api
	db      *graphStore
	key     []byte
	owner   string
	cacheMu sync.RWMutex
	flags   map[string]any
	cacheAt time.Time
	nonceMu sync.Mutex
	nonces  map[string]int64
}
type adminIdentity struct {
	Email string `json:"email"`
	Role  string `json:"role"`
	MFA   bool   `json:"mfa"`
}

func randomAdminID() string { b := make([]byte, 16); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func (s *graphStore) adminRows(query string, params map[string]interface{}, columns ...string) ([]map[string]any, error) {
	r, e := s.query(query, params)
	if e != nil {
		return nil, e
	}
	out := []map[string]any{}
	for r.Next() {
		row := map[string]any{}
		for i, k := range columns {
			v, _ := r.Record().GetByIndex(i)
			row[k] = v
		}
		out = append(out, row)
	}
	return out, nil
}
func adminJSON(v any) string { b, _ := json.Marshal(v); return string(b) }
func adminDecode(s any) map[string]any {
	out := map[string]any{}
	if raw, ok := s.(string); ok {
		_ = json.Unmarshal([]byte(raw), &out)
	}
	return out
}
func adminInt(v any) int64 {
	switch n := v.(type) {
	case int64:
		return n
	case float64:
		return int64(n)
	case json.Number:
		x, _ := n.Int64()
		return x
	case string:
		x, _ := strconv.ParseInt(n, 10, 64)
		return x
	case int:
		return int64(n)
	}
	return 0
}
func (a *api) installAdmin(app *fiber.App) error {
	if len(a.config.AdminKey) < 32 {
		return nil
	}
	db, ok := a.store.(*graphStore)
	if !ok {
		return nil
	}
	s := &adminSystem{api: a, db: db, key: []byte(a.config.AdminKey), owner: strings.ToLower(a.config.AdminOwner), flags: map[string]any{}}
	a.admin = s
	for _, spec := range []struct{ label, key string }{{"AdminIdentity", "email"}, {"AdminDocument", "key"}, {"AdminOperation", "id"}, {"AdminAudit", "id"}, {"AdminEvent", "id"}, {"AdminMedia", "key"}} {
		_, err := db.query("CREATE INDEX FOR (n:"+spec.label+") ON (n."+spec.key+")", nil)
		if err != nil && !strings.Contains(err.Error(), "already") {
			return err
		}
	}
	if s.owner != "" {
		_, err := db.query(`MERGE(a:AdminIdentity {email:$email}) ON CREATE SET a.role='owner',a.status='active',a.created_at=$now RETURN a.email`, map[string]interface{}{"email": s.owner, "now": time.Now().UnixMilli()})
		if err != nil {
			return err
		}
	}
	if a.config.AdminBootstrap != "" {
		hash, e := bcrypt.GenerateFromPassword([]byte(a.config.AdminBootstrap), 12)
		if e != nil {
			return e
		}
		_, e = db.query(`MATCH(a:AdminIdentity {email:$email}) WHERE coalesce(a.access_hash,'')='' SET a.access_hash=$hash`, map[string]interface{}{"email": s.owner, "hash": string(hash)})
		if e != nil {
			return e
		}
	}
	g := app.Group("/api/admin/v1", s.authorize)
	g.Post("/login", limiter.New(limiter.Config{Max: 8, Expiration: time.Minute, KeyGenerator: func(c fiber.Ctx) string { return c.Get("X-Admin-IP") }}), s.login)
	g.Get("/session", s.session)
	g.Post("/mfa/enroll", s.enrollMFA)
	g.Post("/mfa/verify", limiter.New(limiter.Config{Max: 6, Expiration: time.Minute, KeyGenerator: func(c fiber.Ctx) string { return c.Get("X-Admin-Email") }}), s.verifyMFA)
	g.Post("/logout", s.logout)
	g.Get("/reports/:id/photo", s.reportPhoto)
	g.Get("/overview", s.overview)
	g.Get("/players", s.players)
	g.Get("/players/:id", s.player)
	g.Get("/players/:id/media/:key", a.profilePhoto)
	g.Get("/players/:id/inventory", s.playerInventory)
	g.Get("/catalog", s.catalog)
	g.Get("/contracts", s.contracts)
	g.Get("/chain", s.chain)
	g.Get("/rules", s.rules)
	g.Get("/data/:kind", s.data)
	g.Get("/documents/:group", s.documents)
	g.Post("/documents/:group", s.saveDocument)
	g.Post("/documents/:group/:id/restore/:revision", s.restoreDocument)
	g.Post("/operations", s.propose)
	g.Post("/operations/:id/:action", s.operationAction)
	g.Get("/operations/:id", s.operationDetail)
	g.Get("/identities", s.identities)
	g.Post("/identities", s.saveIdentity)
	g.Post("/assets", s.uploadAsset)
	g.Get("/assets/:key", s.asset)
	g.Get("/export/:kind", s.export)
	return nil
}
func (s *adminSystem) authorize(c fiber.Ctx) error {
	ts, e := strconv.ParseInt(c.Get("X-Admin-Time"), 10, 64)
	email := strings.ToLower(c.Get("X-Admin-Email"))
	nonce := c.Get("X-Admin-Nonce")
	if e != nil || abs(int(time.Now().Unix()-ts)) > 60 || len(email) > 200 || !strings.Contains(email, "@") || len(nonce) < 16 {
		return failure(c, 401, "admin_gateway", "Verified administrator access is required.")
	}
	sum := sha256.Sum256(c.Body())
	signed := c.Method() + "\n" + c.OriginalURL() + "\n" + email + "\n" + c.Get("X-Admin-Time") + "\n" + nonce + "\n" + hex.EncodeToString(sum[:])
	mac := hmac.New(sha256.New, s.key)
	_, _ = mac.Write([]byte(signed))
	sig, _ := hex.DecodeString(c.Get("X-Admin-Signature"))
	if !hmac.Equal(sig, mac.Sum(nil)) {
		return failure(c, 401, "admin_gateway", "Invalid gateway signature.")
	}
	s.nonceMu.Lock()
	if s.nonces == nil {
		s.nonces = map[string]int64{}
	}
	now := time.Now().Unix()
	for k, expiry := range s.nonces {
		if expiry < now {
			delete(s.nonces, k)
		}
	}
	nonceKey := email + "/" + nonce
	if _, seen := s.nonces[nonceKey]; seen {
		s.nonceMu.Unlock()
		return failure(c, 401, "replayed_gateway", "Gateway proof was already used.")
	}
	s.nonces[nonceKey] = now + 120
	s.nonceMu.Unlock()
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) WHERE a.status='active' RETURN a.role,coalesce(a.totp,'')`, map[string]interface{}{"email": email}, "role", "totp")
	if e != nil {
		return e
	}
	if len(rows) == 0 {
		return failure(c, 403, "not_invited", "This verified email has not been invited as an administrator.")
	}
	identity := adminIdentity{Email: email, Role: fmt.Sprint(rows[0]["role"])}
	token, err := jwt.Parse(c.Cookies("__Host-remine_admin_step"), func(_ *jwt.Token) (any, error) { return s.key, nil }, jwt.WithValidMethods([]string{"HS256"}), jwt.WithAudience("remine-admin-step"), jwt.WithExpirationRequired())
	if err == nil && token.Valid {
		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			identity.MFA = claims["sub"] == email
		}
	}
	c.Locals("admin", identity)
	c.Set("Cache-Control", "no-store")
	path := c.Path()
	authRoute := strings.HasSuffix(path, "/login") || strings.HasSuffix(path, "/session") || strings.Contains(path, "/mfa/") || strings.HasSuffix(path, "/logout")
	if !authRoute && !identity.MFA {
		return failure(c, 428, "mfa_required", "Complete authenticator verification to continue.")
	}
	if c.Method() != "GET" && !authRoute {
		if identity.Role == "analyst" {
			return failure(c, 403, "read_only", "Your role is read-only.")
		}
		id := randomAdminID()
		_, e = s.db.query(`CREATE(a:AdminAudit {id:$id,email:$email,role:$role,path:$path,method:$method,at:$now,status:0})`, map[string]interface{}{"id": id, "email": email, "role": identity.Role, "path": path, "method": c.Method(), "now": time.Now().UnixMilli()})
		if e != nil {
			return e
		}
		err := c.Next()
		status := c.Response().StatusCode()
		if err != nil {
			status = 500
		}
		_, auditErr := s.db.query(`MATCH(a:AdminAudit {id:$id}) SET a.status=$status`, map[string]interface{}{"id": id, "status": status})
		if auditErr != nil {
			return auditErr
		}
		return err
	}
	return c.Next()
}
func (s *adminSystem) who(c fiber.Ctx) adminIdentity { return c.Locals("admin").(adminIdentity) }
func (s *adminSystem) require(c fiber.Ctx, roles ...string) error {
	id := s.who(c)
	if id.Role == "owner" {
		return nil
	}
	for _, role := range roles {
		if id.Role == role {
			return nil
		}
	}
	return progressError{403, "Your administrator role cannot perform this action."}
}
func (s *adminSystem) session(c fiber.Ctx) error {
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) RETURN coalesce(a.totp,'')`, map[string]interface{}{"email": s.who(c).Email}, "totp")
	if e != nil {
		return e
	}
	return c.JSON(fiber.Map{"admin": s.who(c), "mfa_enrolled": len(rows) > 0 && rows[0]["totp"] != "", "environment": adminNetworkName(s.api.config.StarlightChainID), "chain_id": s.api.config.StarlightChainID, "server_time": time.Now().UTC(), "version": "1.0.0"})
}
func (s *adminSystem) crypt(raw string, encrypt bool) (string, error) {
	key := sha256.Sum256(s.key)
	block, _ := aes.NewCipher(key[:])
	g, _ := cipher.NewGCM(block)
	if encrypt {
		nonce := make([]byte, g.NonceSize())
		_, _ = rand.Read(nonce)
		return hex.EncodeToString(g.Seal(nonce, nonce, []byte(raw), nil)), nil
	}
	data, e := hex.DecodeString(raw)
	if e != nil || len(data) < g.NonceSize() {
		return "", errors.New("invalid encrypted secret")
	}
	out, e := g.Open(nil, data[:g.NonceSize()], data[g.NonceSize():], nil)
	return string(out), e
}
func (s *adminSystem) enrollMFA(c fiber.Ctx) error {
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) RETURN coalesce(a.totp,'')`, map[string]interface{}{"email": s.who(c).Email}, "totp")
	if e != nil {
		return e
	}
	if len(rows) > 0 && rows[0]["totp"] != "" {
		return failure(c, 409, "already_enrolled", "An authenticator is already enrolled.")
	}
	b := make([]byte, 20)
	_, _ = rand.Read(b)
	secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
	enc, _ := s.crypt(secret, true)
	_, e = s.db.query(`MATCH(a:AdminIdentity {email:$email}) SET a.pending_totp=$secret,a.pending_until=$until`, map[string]interface{}{"email": s.who(c).Email, "secret": enc, "until": time.Now().Add(10 * time.Minute).Unix()})
	if e != nil {
		return e
	}
	return c.JSON(fiber.Map{"secret": secret, "uri": "otpauth://totp/REMINE:" + s.who(c).Email + "?secret=" + secret + "&issuer=REMINE", "expires_in": 600})
}
func verifyAdminTOTP(secret, code string, at time.Time) bool {
	if len(code) != 6 {
		return false
	}
	key, e := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	if e != nil {
		return false
	}
	for d := int64(-1); d <= 1; d++ {
		b := make([]byte, 8)
		binary.BigEndian.PutUint64(b, uint64(at.Unix()/30+d))
		mac := hmac.New(sha1.New, key)
		_, _ = mac.Write(b)
		hash := mac.Sum(nil)
		o := hash[len(hash)-1] & 15
		n := (binary.BigEndian.Uint32(hash[o:o+4]) & 0x7fffffff) % 1000000
		if hmac.Equal([]byte(fmt.Sprintf("%06d", n)), []byte(code)) {
			return true
		}
	}
	return false
}
func (s *adminSystem) verifyMFA(c fiber.Ctx) error {
	var body struct {
		Code string `json:"code"`
	}
	if json.Unmarshal(c.Body(), &body) != nil {
		return fiber.ErrBadRequest
	}
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) RETURN coalesce(a.totp,''),coalesce(a.pending_totp,''),coalesce(a.pending_until,0),coalesce(a.last_totp,'')`, map[string]interface{}{"email": s.who(c).Email}, "totp", "pending", "until", "last")
	if e != nil || len(rows) == 0 {
		return fiber.ErrForbidden
	}
	row := rows[0]
	encrypted := fmt.Sprint(row["totp"])
	enrolling := encrypted == ""
	if enrolling {
		if adminInt(row["until"]) < time.Now().Unix() {
			return failure(c, 400, "expired", "Restart authenticator enrollment.")
		}
		encrypted = fmt.Sprint(row["pending"])
	}
	secret, e := s.crypt(encrypted, false)
	if e != nil || !verifyAdminTOTP(secret, body.Code, time.Now()) || row["last"] == body.Code {
		return failure(c, 401, "invalid_code", "Invalid or recently used authenticator code.")
	}
	claimed, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) WHERE coalesce(a.last_totp,'')<>$code SET a.totp=$secret,a.last_totp=$code,a.pending_totp='',a.pending_until=0 RETURN a.email`, map[string]interface{}{"email": s.who(c).Email, "secret": encrypted, "code": body.Code}, "email")
	if e == nil && len(claimed) == 0 {
		return failure(c, 401, "invalid_code", "This authenticator code was already used.")
	}
	if e != nil {
		return e
	}
	claims := jwt.MapClaims{"sub": s.who(c).Email, "aud": "remine-admin-step", "exp": time.Now().Add(2 * time.Hour).Unix(), "iat": time.Now().Unix()}
	token, e := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(s.key)
	if e != nil {
		return e
	}
	c.Cookie(&fiber.Cookie{Name: "__Host-remine_admin_step", Value: token, Secure: true, HTTPOnly: true, SameSite: "Strict", Path: "/", MaxAge: 7200})
	return c.JSON(fiber.Map{"verified": true})
}
func (s *adminSystem) logout(c fiber.Ctx) error {
	c.Cookie(&fiber.Cookie{Name: "__Host-remine_admin_auth", Value: "", Secure: true, HTTPOnly: true, SameSite: "Strict", Path: "/", MaxAge: -1})
	c.Cookie(&fiber.Cookie{Name: "__Host-remine_admin_step", Value: "", Secure: true, HTTPOnly: true, SameSite: "Strict", Path: "/", MaxAge: -1})
	return c.JSON(fiber.Map{"logged_out": true})
}
func (s *adminSystem) overview(c fiber.Ctx) error {
	counts := map[string]int64{}
	for key, query := range map[string]string{"players": "MATCH(n:User) RETURN count(n)", "wallets": "MATCH(n:Wallet) RETURN count(n)", "scores": "MATCH(n:PersonalBest) RETURN count(n)", "online": "MATCH(u:User)-[:HAS_PRESENCE]->(n:Presence) WHERE n.until>" + strconv.FormatInt(time.Now().UnixMilli(), 10) + " RETURN count(DISTINCT u)", "orders": "MATCH(n:ShopOperation) RETURN count(n)", "pending_orders": "MATCH(n:ShopOperation) WHERE n.status='pending' RETURN count(n)", "pending_payouts": "MATCH(n:StarlightPayout) WHERE n.status<>'confirmed' RETURN count(n)", "pending_scores": "MATCH(n:LeaderboardPublication) WHERE n.status<>'confirmed' RETURN count(n)", "events": "MATCH(n:AdminEvent) RETURN count(n)", "proposals": "MATCH(n:AdminOperation) WHERE n.status='proposed' RETURN count(n)", "reports": "MATCH(n:AdminDocument {group:'reports'}) WHERE n.status<>'resolved' RETURN count(n)"} {
		r, e := s.db.adminRows(query, nil, "count")
		if e != nil {
			return e
		}
		if len(r) > 0 {
			counts[key] = adminInt(r[0]["count"])
		}
	}
	rows, e := s.db.adminRows(`MATCH(u:User) OPTIONAL MATCH(u)-[:HAS_PROGRESSION]->(p:Progression) RETURN u.id,u.username,u.created_at,coalesce(p.payload,'') ORDER BY u.created_at DESC LIMIT 1000`, nil, "id", "username", "created_at", "progression")
	if e != nil {
		return e
	}
	var xp, earned, clears, active int64
	days := map[string]int{}
	for _, r := range rows {
		p := adminDecode(r["progression"])
		xp += adminInt(p["xp"])
		earned += adminInt(p["starlight"])
		clears += adminInt(p["clears"])
		if a, ok := p["active"].(map[string]any); ok && adminInt(a["started_at"]) > time.Now().Add(-2*time.Hour).UnixMilli() {
			active++
		}
		day := fmt.Sprint(r["created_at"])
		if len(day) >= 10 {
			days[day[:10]]++
		}
	}
	return c.JSON(fiber.Map{"counts": counts, "totals": fiber.Map{"xp": xp, "starlight_earned": earned, "clears": clears, "active_runs": active}, "registration_days": days, "aggregation_limit": 1000, "players_scanned": len(rows), "fresh_at": time.Now().UTC(), "telemetry_since": "Admin telemetry begins at deployment; historical retention is unavailable."})
}
func (s *adminSystem) players(c fiber.Ctx) error {
	q := strings.ToLower(strings.TrimSpace(c.Query("q")))
	offset, _ := strconv.Atoi(c.Query("offset", "0"))
	offset = max(0, min(offset, 100000))
	rows, e := s.db.adminRows(`MATCH(u:User) OPTIONAL MATCH(u)-[:HAS_PROGRESSION]->(p:Progression) OPTIONAL MATCH(u)-[:HAS_WALLET]->(w:Wallet) WITH u,p,w WHERE $q='' OR u.username_key CONTAINS $q OR u.id=$q OR toLower(coalesce(w.address,''))=$q RETURN u.id,u.username,u.created_at,coalesce(u.admin_status,'active'),coalesce(u.profile_media,''),coalesce(p.payload,''),coalesce(w.address,'') ORDER BY u.created_at DESC SKIP $offset LIMIT 51`, map[string]interface{}{"q": q, "offset": offset}, "id", "username", "created_at", "status", "media", "progression", "wallet")
	if e != nil {
		return e
	}
	more := len(rows) > 50
	if more {
		rows = rows[:50]
	}
	for _, r := range rows {
		r["media"] = adminDecode(r["media"])
		r["progression"] = adminDecode(r["progression"])
	}
	return c.JSON(fiber.Map{"rows": rows, "has_more": more, "offset": offset})
}
func (s *adminSystem) player(c fiber.Ctx) error {
	id := c.Params("id")
	u, e := s.api.store.ByID(id)
	if e != nil {
		return fiber.ErrNotFound
	}
	p, _, e := s.db.ReadProgress(id)
	if e != nil {
		return e
	}
	p.normalize(time.Now())
	records, e := s.db.ReadBests(id)
	if e != nil {
		return e
	}
	media, e := s.db.ReadProfileMedia(id)
	if e != nil {
		return e
	}
	friends, _ := s.db.SocialCounts(id)
	relations, _ := s.db.adminRows(`MATCH(u:User {id:$id})-[r:FOLLOWS|BLOCKS]-(v:User) RETURN v.id,v.username,type(r),startNode(r).id`, map[string]interface{}{"id": id}, "id", "username", "relationship", "source")
	wallet, _ := s.db.ReadWallet(id, s.api.config.EngineProjectID, s.api.config.EngineURL)
	sessions, _ := s.db.adminRows(`MATCH(:User {id:$id})-[:HAS_LOGIN_SESSION]->(l:LoginSession) RETURN l.created_at*1000,l.expires_at*1000`, map[string]interface{}{"id": id}, "created_at", "expires_at")
	return c.JSON(fiber.Map{"user": u, "progression": progressionView(p, time.Now()), "raw_progression": p, "records": records, "media": mediaView(id, media), "social_counts": friends, "relationships": relations, "sessions": sessions, "wallet": wallet})
}
func (s *adminSystem) playerInventory(c fiber.Ctx) error {
	u, e := s.api.store.ByID(c.Params("id"))
	if e != nil {
		return fiber.ErrNotFound
	}
	c.Locals("user", u)
	return s.api.getInventory(c)
}

var adminGroups = map[string]bool{"settings": true, "catalog": true, "missions": true, "calendars": true, "events": true, "announcements": true, "notes": true, "reports": true, "assets": true, "alerts": true, "releases": true, "supply-policy": true, "chart-releases": true, "backups": true, "support": true, "privacy": true}

func (s *adminSystem) documents(c fiber.Ctx) error {
	g := c.Params("group")
	if !adminGroups[g] {
		return fiber.ErrNotFound
	}
	r, e := s.db.adminRows(`MATCH(d:AdminDocument {group:$group}) RETURN d.id,d.name,d.status,d.revision,d.updated_at,d.updated_by,d.value ORDER BY d.updated_at DESC LIMIT 200`, map[string]interface{}{"group": g}, "id", "name", "status", "revision", "updated_at", "updated_by", "value")
	if e != nil {
		return e
	}
	for _, row := range r {
		row["value"] = adminDecode(row["value"])
	}
	return c.JSON(fiber.Map{"rows": r})
}
func (s *adminSystem) saveDocument(c fiber.Ctx) error {
	g := c.Params("group")
	if !adminGroups[g] {
		return fiber.ErrNotFound
	}
	if err := s.require(c, adminDocumentRole(g)); err != nil {
		return err
	}
	if g == "settings" || g == "privacy" {
		if err := s.require(c, "operations"); err != nil {
			return err
		}
	}
	var body struct {
		ID       string         `json:"id"`
		Name     string         `json:"name"`
		Status   string         `json:"status"`
		Revision int64          `json:"revision"`
		Reason   string         `json:"reason"`
		Value    map[string]any `json:"value"`
	}
	if json.Unmarshal(c.Body(), &body) != nil || len(body.Name) < 2 || len(body.Name) > 120 || len(body.Reason) < 5 || len(c.Body()) > 65536 {
		return failure(c, 400, "invalid_document", "Name, reason, and a valid JSON value are required.")
	}
	if body.ID == "" {
		body.ID = randomAdminID()
	}
	if !validHex(body.ID, 16) {
		return fiber.ErrBadRequest
	}
	if !map[string]bool{"draft": true, "published": true, "archived": true, "resolved": true}[body.Status] {
		return fiber.ErrBadRequest
	}
	if g == "settings" {
		if e := validateAdminSettings(body.Value); e != nil {
			return failure(c, 400, "invalid_settings", e.Error())
		}
	}
	params := map[string]interface{}{"key": g + "/" + body.ID, "group": g, "id": body.ID, "name": body.Name, "status": body.Status, "revision": body.Revision, "next": body.Revision + 1, "value": adminJSON(body.Value), "email": s.who(c).Email, "now": time.Now().UnixMilli(), "history": randomAdminID(), "reason": body.Reason}
	r, e := s.db.adminRows(`MERGE(d:AdminDocument {key:$key}) ON CREATE SET d.revision=0,d.group=$group,d.id=$id WITH d WHERE d.revision=$revision CREATE(h:AdminRevision {id:$history,document:$key,revision:$revision,value:coalesce(d.value,'{}'),name:coalesce(d.name,''),status:coalesce(d.status,'draft'),at:$now,actor:$email,reason:$reason}) SET d.name=$name,d.status=$status,d.revision=$next,d.value=$value,d.updated_at=$now,d.updated_by=$email RETURN d.id,d.revision`, params, "id", "revision")
	if e != nil {
		return e
	}
	if len(r) == 0 {
		return failure(c, 409, "revision_conflict", "This document changed. Refresh before saving.")
	}
	s.cacheMu.Lock()
	s.cacheAt = time.Time{}
	s.cacheMu.Unlock()
	return c.JSON(r[0])
}
func validateAdminSettings(v map[string]any) error {
	for k, val := range v {
		switch k {
		case "maintenance", "purchases_paused", "runs_paused", "uploads_paused", "social_paused":
			if _, ok := val.(bool); !ok {
				return fmt.Errorf("%s must be true or false", k)
			}
		default:
			return fmt.Errorf("%s is not a live-editable setting; use a versioned release proposal", k)
		}
	}
	return nil
}
func (s *adminSystem) restoreDocument(c fiber.Ctx) error {
	g := c.Params("group")
	if !adminGroups[g] {
		return fiber.ErrNotFound
	}
	r, e := s.db.adminRows(`MATCH(h:AdminRevision {document:$key,revision:$revision}) RETURN h.value,h.name,h.status`, map[string]interface{}{"key": g + "/" + c.Params("id"), "revision": adminInt(c.Params("revision"))}, "value", "name", "status")
	if e != nil || len(r) == 0 {
		return fiber.ErrNotFound
	}
	return c.JSON(fiber.Map{"restored_draft": r[0], "message": "Review this historical value and save with the current revision to restore."})
}
func (s *adminSystem) liveFlags() map[string]any {
	s.cacheMu.RLock()
	if time.Since(s.cacheAt) < 3*time.Second {
		out := s.flags
		s.cacheMu.RUnlock()
		return out
	}
	s.cacheMu.RUnlock()
	r, e := s.db.adminRows(`MATCH(d:AdminDocument {group:'settings',status:'published'}) RETURN d.value ORDER BY d.updated_at`, nil, "value")
	out := map[string]any{}
	if e != nil {
		s.cacheMu.RLock()
		defer s.cacheMu.RUnlock()
		return s.flags
	}
	if e == nil {
		for _, row := range r {
			for k, v := range adminDecode(row["value"]) {
				out[k] = v
			}
		}
	}
	s.cacheMu.Lock()
	s.flags = out
	s.cacheAt = time.Now()
	s.cacheMu.Unlock()
	return out
}
func (s *adminSystem) playerGate(c fiber.Ctx, id string) error {
	r, e := s.db.adminRows(`MATCH(u:User {id:$id}) RETURN coalesce(u.admin_status,'active'),coalesce(u.social_restricted,false),coalesce(u.upload_restricted,false)`, map[string]interface{}{"id": id}, "status", "social", "uploads")
	if e != nil {
		return e
	}
	if len(r) > 0 && r[0]["status"] == "suspended" {
		return failure(c, 403, "account_suspended", "This account is suspended. Contact support.")
	}
	f := s.liveFlags()
	path := c.Path()
	if f["maintenance"] == true && c.Method() != "GET" {
		return failure(c, 503, "maintenance", "The game is undergoing maintenance.")
	}
	if strings.Contains(path, "/shop/purchase") && f["purchases_paused"] == true {
		return failure(c, 503, "shop_paused", "Purchases are temporarily paused.")
	}
	if path == "/api/v1/runs" && f["runs_paused"] == true {
		return failure(c, 503, "runs_paused", "New runs are temporarily paused.")
	}
	if c.Method() != "GET" && strings.Contains(path, "/profile/media") && (f["uploads_paused"] == true || len(r) > 0 && r[0]["uploads"] == true) {
		return failure(c, 403, "uploads_restricted", "Photo uploads are restricted.")
	}
	if c.Method() != "GET" && strings.Contains(path, "/social/") && (f["social_paused"] == true || len(r) > 0 && r[0]["social"] == true) {
		return failure(c, 403, "social_restricted", "Social interactions are restricted.")
	}
	return nil
}
func (s *adminSystem) telemetry(c fiber.Ctx, requestErr error, elapsed time.Duration) {
	id := ""
	if u, ok := c.Locals("user").(user); ok {
		id = u.ID
	}
	path := c.Path()
	if !strings.HasPrefix(path, "/api/v1/") || c.Method() == "GET" {
		return
	}
	status := c.Response().StatusCode()
	if requestErr != nil {
		status = 500
		var pe progressError
		var fe *fiber.Error
		if errors.As(requestErr, &pe) {
			status = pe.status
		} else if errors.As(requestErr, &fe) {
			status = fe.Code
		}
	}
	_, _ = s.db.query(`CREATE(e:AdminEvent {id:$id,owner:$owner,path:$path,status:$status,at:$at,day:$day,latency_ms:$latency})`, map[string]interface{}{"id": randomAdminID(), "owner": id, "path": path, "status": status, "at": time.Now().UnixMilli(), "day": time.Now().UTC().Format("2006-01-02"), "latency": elapsed.Milliseconds()})
}

func (s *adminSystem) data(c fiber.Ctx) error {
	kind := c.Params("kind")
	params := map[string]interface{}{}
	var q string
	var cols []string
	switch kind {
	case "charts":
		out := []any{}
		keys := []string{}
		for key := range rewardCharts {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			ch := rewardCharts[key]
			out = append(out, fiber.Map{"id": key, "song_id": ch.SongID, "name": ch.Title, "difficulty": ch.Difficulty, "revision": ch.Revision, "duration": ch.Duration, "units": ch.Units})
		}
		return c.JSON(fiber.Map{"rows": out, "source": "Embedded authoritative chart catalog"})
	case "scores":
		q = `MATCH(u:User)-[:HAS_PERSONAL_BEST]->(b:PersonalBest) RETURN b.key,u.id,u.username,b.song_id,b.difficulty,b.score,b.max_combo,b.accuracy,b.achieved_at,coalesce(b.quarantined,false) ORDER BY b.score DESC LIMIT 250`
		cols = []string{"id", "player_id", "player", "song_id", "difficulty", "score", "combo", "accuracy", "at", "quarantined"}
	case "wallets":
		q = `MATCH(w:Wallet) RETURN w.key,w.owner,w.address,w.status,w.attempts,w.error_code,w.next_attempt_at ORDER BY w.status LIMIT 250`
		cols = []string{"id", "player_id", "address", "status", "attempts", "error", "next_retry"}
	case "social":
		q = `MATCH(u:User)-[r:FOLLOWS|BLOCKS]->(v:User) RETURN u.id,u.username,v.id,v.username,type(r),r.created_at ORDER BY r.created_at DESC LIMIT 250`
		cols = []string{"player_id", "player", "peer_id", "peer", "relationship", "at"}
	case "activity", "analytics":
		q = `MATCH(e:AdminEvent) RETURN e.id,e.owner,e.path,e.status,e.at,e.day,e.latency_ms ORDER BY e.at DESC LIMIT 500`
		cols = []string{"id", "player_id", "action", "status", "at", "day", "latency_ms"}
	case "audit":
		q = `MATCH(a:AdminAudit) RETURN a.id,a.email,a.role,a.method,a.path,a.at,a.status ORDER BY a.at DESC LIMIT 250`
		cols = []string{"id", "actor", "role", "method", "action", "at", "status"}
	case "history":
		q = `MATCH(h:AdminRevision) RETURN h.id,h.document,h.revision,h.value,h.name,h.status,h.at,h.actor,h.reason ORDER BY h.at DESC LIMIT 200`
		cols = []string{"id", "document", "revision", "value", "name", "status", "at", "actor", "reason"}
	case "operations", "minting":
		q = `MATCH(o:AdminOperation) RETURN o.id,o.kind,o.actor,o.status,o.reason,o.payload,o.result,o.created_at,o.updated_at ORDER BY o.created_at DESC LIMIT 250`
		cols = []string{"id", "kind", "actor", "status", "reason", "payload", "result", "created_at", "updated_at"}
	case "runs", "decks", "refinement", "cards":
		r, e := s.db.adminRows(`MATCH(u:User)-[:HAS_PROGRESSION]->(p:Progression) RETURN u.id,u.username,p.payload LIMIT 1000`, nil, "player_id", "player", "payload")
		if e != nil {
			return e
		}
		out := []any{}
		for _, row := range r {
			p := adminDecode(row["payload"])
			switch kind {
			case "runs":
				if v, ok := p["active"].(map[string]any); ok {
					v["player_id"] = row["player_id"]
					v["player"] = row["player"]
					v["status"] = "active"
					if adminInt(v["started_at"]) < time.Now().Add(-2*time.Hour).UnixMilli() {
						v["status"] = "expired"
					}
					out = append(out, v)
				}
			case "decks":
				if v, ok := p["active"].(map[string]any); ok {
					out = append(out, fiber.Map{"player_id": row["player_id"], "player": row["player"], "run_id": v["id"], "set_id": v["set_id"], "deck": v["deck"], "deck_ids": v["deck_ids"]})
				}
			default:
			}
		}
		if kind == "refinement" || kind == "cards" {
			r, e := s.db.adminRows(`MATCH(j:ShopOperation) RETURN j.key,j.owner,j.payload,j.status,j.created_at ORDER BY j.created_at DESC LIMIT 250`, nil, "id", "player_id", "payload", "status", "at")
			if e != nil {
				return e
			}
			for _, v := range r {
				p := adminDecode(v["payload"])
				job, ok := p["job"].(map[string]any)
				if ok {
					for k, val := range job {
						if k != "request_id" {
							v[k] = val
						}
					}
				}
				v["payload"] = p
				out = append(out, v)
			}
		}
		return c.JSON(fiber.Map{"rows": out, "source": "Retained game state and operations; raw replay history is not stored."})
	case "transactions", "recovery":
		out := []map[string]any{}
		for _, spec := range []struct {
			label   string
			columns []string
			query   string
		}{{"shop", []string{"id", "player_id", "status", "payload", "at", "next_retry", "lease_until"}, `MATCH(j:ShopOperation) RETURN j.key,j.owner,j.status,j.payload,j.created_at,j.next_at,j.lease_until ORDER BY j.created_at DESC LIMIT 200`}, {"payout", []string{"id", "player_id", "status", "amount", "transaction_hash", "engine_id", "error", "next_retry", "lease_until"}, `MATCH(j:StarlightPayout) RETURN j.key,j.owner,j.status,j.amount,j.tx_hash,j.engine_id,j.error_code,j.next_attempt_at,j.lease_until ORDER BY j.created_at DESC LIMIT 200`}, {"score", []string{"id", "player_id", "status", "payload", "transaction_hash", "engine_id", "error", "next_retry", "lease_until"}, `MATCH(j:LeaderboardPublication) RETURN j.key,j.owner,j.status,j.payload,j.tx_hash,j.engine_id,j.error_code,j.next_attempt_at,j.lease_until ORDER BY j.created_at DESC LIMIT 200`}} {
			rows, e := s.db.adminRows(spec.query, nil, spec.columns...)
			if e != nil {
				return e
			}
			for _, row := range rows {
				row["type"] = spec.label
				if p, ok := row["payload"].(string); ok {
					row["payload"] = adminDecode(p)
				}
				out = append(out, row)
			}
		}
		return c.JSON(fiber.Map{"rows": out, "limit_per_queue": 200})
	case "skills":
		return c.JSON(fiber.Map{"rows": []any{fiber.Map{"name": "Overture", "effect": "First momentum bar fill", "ranks": "20 / 40 / 60 / 80 / 100%"}, fiber.Map{"name": "Spotlight", "effect": "Every 30 consecutive PERFECT heads", "ranks": "+3 / 3.5 / 4 / 4.5 / 5%"}, fiber.Map{"name": "Second Wind", "effect": "Low HP recovery after PERFECT streak", "ranks": "15 / 14 / 13 / 12 / 10 heads"}, fiber.Map{"name": "Encore", "effect": "PERFECT hits in final 20%", "ranks": "+1 / 1.5 / 2 / 2.5 / 3%"}, fiber.Map{"name": "Resonance", "effect": "Unbroken sustain with PERFECT head", "ranks": "+2 / 2.5 / 3 / 3.5 / 4%"}, fiber.Map{"name": "Overdrive", "effect": "PERFECT hits at 5×", "ranks": "+0.5 / 0.75 / 1 / 1.25 / 1.5%"}}, "source": "Current game rules. Changes require coordinated game/backend release."})
	case "items":
		out := []any{fiber.Map{"id": "energy_drink", "name": "Energy Drink", "token_id": 0, "price": 100, "effect": "Up to +5 energy", "mint_type": "ERC-1155 stock"}}
		for i, member := range pulseMembers {
			out = append(out, fiber.Map{"id": fmt.Sprintf("legacy_scene_%02d", i+1), "name": member + " · First Scene", "token_id": i + 1, "price": 450, "mint_type": "ERC-1155 stock", "effect": "Cosmetic collectible"})
		}
		for _, card := range memberCards {
			out = append(out, fiber.Map{"id": card.ID, "name": card.Member + " · reserved PULSE product", "token_id": card.TokenID, "status": "reserved", "mint_type": "Unavailable through stock minting; unique PULSE issuance needs deployment"})
		}
		for _, m := range cardMaterials {
			out = append(out, fiber.Map{"id": m.ID, "name": m.Name, "token_id": m.TokenID, "price": m.Price, "xp": m.XP, "mint_type": "ERC-1155 material"})
		}
		return c.JSON(fiber.Map{"rows": out})
	case "health":
		started := time.Now()
		err := s.db.Ping()
		status := "healthy"
		if err != nil {
			status = "unavailable"
		}
		return c.JSON(fiber.Map{"rows": []any{fiber.Map{"name": "Game database", "status": status, "latency_ms": time.Since(started).Milliseconds()}, fiber.Map{"name": "Managed wallets", "status": s.api.config.EngineAPIKey != ""}, fiber.Map{"name": "STARL rewards", "status": s.api.config.StarlightEnabled}, fiber.Map{"name": "Marketplace", "status": s.api.config.MarketplaceEnabled}, fiber.Map{"name": "Commerce", "status": s.api.config.ShopEnabled}, fiber.Map{"name": "PULSE VERSION 2", "status": s.api.config.PulseRouter != ""}}, "fresh_at": time.Now().UTC()})
	case "launch":
		return c.JSON(fiber.Map{"rows": []any{fiber.Map{"name": "PULSE router configured", "ready": s.api.config.PulseRouter != "", "detail": s.api.config.PulseRouter}, fiber.Map{"name": "STARL payouts", "ready": s.api.config.StarlightEnabled}, fiber.Map{"name": "Shop enabled", "ready": s.api.config.ShopEnabled}, fiber.Map{"name": "Card checkout", "ready": s.api.config.CardsEnabled}, fiber.Map{"name": "Material definitions", "ready": true, "detail": "Reserved IDs 11, 12, 13"}, fiber.Map{"name": "Supply/reissue policy enforcement", "ready": false, "detail": "Owner decision and contract enforcement required before public LE sales"}}, "source": "Readiness checks; no launch transactions have been submitted by this page."})
	default:
		return fiber.ErrNotFound
	}
	rows, e := s.db.adminRows(q, params, cols...)
	if e != nil {
		return e
	}
	for _, r := range rows {
		for _, k := range []string{"payload", "result", "value"} {
			if v, ok := r[k].(string); ok {
				r[k] = adminDecode(v)
			}
		}
	}
	if kind == "analytics" {
		players := map[string]bool{}
		days := map[string]int{}
		var failures, complete, latency int64
		for _, r := range rows {
			if id, ok := r["player_id"].(string); ok && id != "" {
				players[id] = true
			}
			days[fmt.Sprint(r["day"])]++
			if adminInt(r["status"]) >= 400 {
				failures++
			}
			if strings.HasSuffix(fmt.Sprint(r["action"]), "/complete") && adminInt(r["status"]) < 400 {
				complete++
			}
			latency += adminInt(r["latency_ms"])
		}
		avg := int64(0)
		if len(rows) > 0 {
			avg = latency / int64(len(rows))
		}
		return c.JSON(fiber.Map{"rows": rows, "metrics": fiber.Map{"events": len(rows), "unique_players": len(players), "errors": failures, "completions": complete, "average_latency_ms": avg}, "days": days, "source": "Most recent 500 authenticated mutation events. This retained window is not a full historical cohort.", "fresh_at": time.Now().UTC()})
	}
	return c.JSON(fiber.Map{"rows": rows, "fresh_at": time.Now().UTC()})
}
func (s *adminSystem) export(c fiber.Ctx) error {
	c.Set("Content-Disposition", `attachment; filename="remine-`+c.Params("kind")+`.json"`)
	return s.data(c)
}
func (s *adminSystem) contracts(c fiber.Ctx) error {
	cfg := s.api.config
	out := []any{}
	for _, v := range []struct {
		Name, Address, Kind string
		Actions             []string
	}{{"RESCENE Starlight", cfg.StarlightToken, "ERC-20", []string{"transfer_starl", "approve_allowance"}}, {"Game items", cfg.MarketplaceCollection, "ERC-1155", []string{"mint_item"}}, {"Marketplace", cfg.MarketplaceAddress, "MarketplaceV3", []string{"listing_create", "listing_update", "listing_cancel"}}, {"Reward distributor", cfg.StarlightDistributor, "StarlightRewards", []string{"compensate_starl"}}, {"Verified leaderboard", cfg.LeaderboardAddress, "ResceneLeaderboard", []string{"leaderboard_pause", "leaderboard_unpause", "board_enable"}}, {"Energy Drink router", cfg.ShopRouter, "EnergyDrinkShop", []string{}}, {"First Scene router", cfg.LegacyCardsRouter, "MemberCardShop", []string{}}, {"PULSE cards", cfg.PulseRouter, "PulseCards VERSION 2", []string{"generate_card", "pulse_sales"}}} {
		out = append(out, fiber.Map{"name": v.Name, "address": v.Address, "kind": v.Kind, "chain_id": cfg.StarlightChainID, "configured": v.Address != "", "actions": v.Actions, "explorer": adminContractExplorer(cfg.StarlightChainID, v.Address)})
	}
	return c.JSON(fiber.Map{"rows": out, "immutable": "Router prices, signer/treasury bindings, and minted card traits require compatible contracts, not a catalog edit."})
}
func (s *adminSystem) chain(c fiber.Ctx) error {
	cfg := s.api.config
	ctx, cancel := context.WithTimeout(c.Context(), 10*time.Second)
	defer cancel()
	client := newStarlightClient(cfg)
	balance, e := client.balance(ctx, cfg.StarlightTreasury)
	if e != nil {
		return failure(c, 503, "chain_unavailable", "Treasury RPC data is temporarily unavailable.")
	}
	var native string
	e = client.p.rpc(ctx, "eth_getBalance", []any{cfg.StarlightTreasury, "latest"}, &native)
	if e != nil {
		return e
	}
	total, e := client.call(ctx, cfg.StarlightToken, selector("totalSupply()"))
	if e != nil {
		return e
	}
	supply, e := uint256Hex(total)
	if e != nil {
		return e
	}
	return c.JSON(fiber.Map{"treasury": cfg.StarlightTreasury, "starlight_balance": formatStarlight(balance), "total_supply": formatStarlight(supply), "gas_balance_hex": native, "chain_id": cfg.StarlightChainID, "checked_at": time.Now().UTC()})
}
func (s *adminSystem) identities(c fiber.Ctx) error {
	if e := s.require(c); e != nil {
		return e
	}
	r, e := s.db.adminRows(`MATCH(a:AdminIdentity) RETURN a.email,a.role,a.status,a.created_at,coalesce(a.totp,'')<>''`, nil, "email", "role", "status", "created_at", "mfa_enrolled")
	if e != nil {
		return e
	}
	return c.JSON(fiber.Map{"rows": r})
}
func (s *adminSystem) saveIdentity(c fiber.Ctx) error {
	if e := s.require(c); e != nil {
		return e
	}
	var b struct{ Email, Role, Status, Reason string }
	if json.Unmarshal(c.Body(), &b) != nil || !strings.Contains(b.Email, "@") || len(b.Reason) < 5 || !map[string]bool{"owner": true, "operations": true, "economy": true, "content": true, "support": true, "analyst": true}[b.Role] || !map[string]bool{"active": true, "revoked": true}[b.Status] {
		return fiber.ErrBadRequest
	}
	b.Email = strings.ToLower(b.Email)
	if b.Email == s.owner && (b.Role != "owner" || b.Status != "active") {
		return failure(c, 409, "owner_protected", "The initial owner cannot revoke their own access.")
	}
	_, e := s.db.query(`MERGE(a:AdminIdentity {email:$email}) ON CREATE SET a.created_at=$now SET a.role=$role,a.status=$status`, map[string]interface{}{"email": b.Email, "role": b.Role, "status": b.Status, "now": time.Now().UnixMilli()})
	if e != nil {
		return e
	}
	key := randomAdminID() + randomAdminID()
	hash, e := bcrypt.GenerateFromPassword([]byte(key), 12)
	if e != nil {
		return e
	}
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email}) WHERE coalesce(a.access_hash,'')='' SET a.access_hash=$hash RETURN a.email`, map[string]interface{}{"email": b.Email, "hash": string(hash)}, "email")
	if e != nil {
		return e
	}
	if len(rows) == 0 {
		return c.JSON(fiber.Map{"saved": true, "message": "Existing administrator updated; the access key is unchanged."})
	}
	return c.JSON(fiber.Map{"saved": true, "access_key": key, "message": "New access key shown once. Store and share it privately."})
}
func (s *adminSystem) uploadAsset(c fiber.Ctx) error {
	if e := s.require(c, "content"); e != nil {
		return e
	}
	raw, e := normalizeProfileImage(c.Body(), false)
	if e != nil {
		return failure(c, 400, "invalid_image", "Upload a valid JPG/PNG within the game photo limits.")
	}
	key := randomAdminID()
	dir := filepath.Join(s.api.mediaDirectory(), "admin")
	if e = os.MkdirAll(dir, 0700); e != nil {
		return e
	}
	if e = os.WriteFile(filepath.Join(dir, key+".jpg"), raw, 0600); e != nil {
		return e
	}
	_, e = s.db.query(`CREATE(d:AdminDocument {key:$key,id:$id,group:'assets',name:$name,status:'published',revision:1,value:$value,updated_at:$now,updated_by:$actor})`, map[string]interface{}{"key": "assets/" + key, "id": key, "name": "Image " + key[:8], "value": adminJSON(fiber.Map{"path": "/api/assets/" + key, "bytes": len(raw), "content_hash": hashHex(raw)}), "now": time.Now().UnixMilli(), "actor": s.who(c).Email})
	if e != nil {
		return e
	}
	return c.JSON(fiber.Map{"id": key, "url": "/api/assets/" + key})
}
func (s *adminSystem) asset(c fiber.Ctx) error {
	if !validHex(c.Params("key"), 16) {
		return fiber.ErrNotFound
	}
	raw, e := os.ReadFile(filepath.Join(s.api.mediaDirectory(), "admin", c.Params("key")+".jpg"))
	if e != nil {
		return fiber.ErrNotFound
	}
	c.Set("Content-Type", "image/jpeg")
	return c.Send(raw)
}

type adminProposal struct {
	ID      string         `json:"id"`
	Kind    string         `json:"kind"`
	Reason  string         `json:"reason"`
	Payload map[string]any `json:"payload"`
}

var adminKinds = map[string]string{"suspend": "support", "restore": "support", "revoke_sessions": "support", "restrict_uploads": "support", "restrict_social": "support", "grant_xp": "operations", "grant_energy": "operations", "quarantine_photo": "support", "restore_photo": "support", "quarantine_score": "operations", "restore_score": "operations", "retry_job": "operations", "mint_item": "economy", "generate_card": "economy", "compensate_starl": "economy", "transfer_starl": "economy", "approve_allowance": "economy", "leaderboard_pause": "operations", "leaderboard_unpause": "operations", "board_enable": "operations", "pulse_sales": "economy", "listing_cancel": "economy", "listing_create": "economy", "listing_update": "economy"}

func (s *adminSystem) propose(c fiber.Ctx) error {
	var b adminProposal
	if json.Unmarshal(c.Body(), &b) != nil || len(b.Reason) < 8 || len(b.Reason) > 1000 {
		return failure(c, 400, "reason_required", "Describe the reason for this operation (8–1,000 characters).")
	}
	role, ok := adminKinds[b.Kind]
	if !ok {
		return failure(c, 400, "unsupported_operation", "This action is not supported.")
	}
	if e := s.require(c, role); e != nil {
		return e
	}
	if !validHex(b.ID, 16) {
		return failure(c, 400, "request_id_required", "A unique request ID is required.")
	}
	if b.Payload == nil {
		return fiber.ErrBadRequest
	}
	if _, chain := b.Payload["private_key"]; chain {
		return fiber.ErrBadRequest
	}
	roll := ""
	if b.Kind == "generate_card" {
		member, rarity := adminInt(b.Payload["member"]), adminInt(b.Payload["rarity"])
		if b.Payload["member"] == nil || b.Payload["rarity"] == nil || member < 0 || member > 4 || rarity < 0 || rarity > 5 || !validHex(fmt.Sprint(b.Payload["recipient"]), 20) {
			return fiber.ErrBadRequest
		}
		score, recovery, skill, err := rollCardTraits(int(rarity))
		if err != nil {
			return err
		}
		roll = adminJSON(map[string]any{"score_bp": score, "recovery_bp": recovery, "skill": skill})
	}
	r, e := s.db.adminRows(`MERGE(o:AdminOperation {id:$id}) ON CREATE SET o.kind=$kind,o.actor=$actor,o.reason=$reason,o.payload=$payload,o.card_roll=$roll,o.status='proposed',o.created_at=$now,o.updated_at=$now,o.result='{}' RETURN o.kind,o.actor,o.payload,o.status,o.reason`, map[string]interface{}{"id": b.ID, "kind": b.Kind, "actor": s.who(c).Email, "reason": b.Reason, "payload": adminJSON(b.Payload), "roll": roll, "now": time.Now().UnixMilli()}, "kind", "actor", "payload", "status", "reason")
	if e != nil {
		return e
	}
	if len(r) == 0 || r[0]["actor"] != s.who(c).Email || r[0]["kind"] != b.Kind || r[0]["payload"] != adminJSON(b.Payload) || r[0]["reason"] != b.Reason {
		return failure(c, 409, "operation_conflict", "This operation ID already has another immutable intent.")
	}
	return c.JSON(fiber.Map{"id": b.ID, "status": r[0]["status"], "message": "Review this immutable intent before execution. Nothing has been changed or signed."})
}
func (s *adminSystem) operationDetail(c fiber.Ctx) error {
	r, e := s.db.adminRows(`MATCH(o:AdminOperation {id:$id}) RETURN o.id,o.kind,o.actor,o.reason,o.status,o.payload,o.result,o.created_at,o.updated_at,coalesce(o.card_roll,'')`, map[string]interface{}{"id": c.Params("id")}, "id", "kind", "actor", "reason", "status", "payload", "result", "created_at", "updated_at", "card_roll")
	if e != nil {
		return e
	}
	if len(r) == 0 {
		return fiber.ErrNotFound
	}
	r[0]["payload"] = adminDecode(r[0]["payload"])
	r[0]["result"] = adminDecode(r[0]["result"])
	r[0]["card_roll"] = adminDecode(r[0]["card_roll"])
	return c.JSON(r[0])
}
func (s *adminSystem) operationAction(c fiber.Ctx) error {
	id := c.Params("id")
	r, e := s.db.adminRows(`MATCH(o:AdminOperation {id:$id}) RETURN o.kind,o.actor,o.payload,o.status,o.result`, map[string]interface{}{"id": id}, "kind", "actor", "payload", "status", "result")
	if e != nil {
		return e
	}
	if len(r) == 0 {
		return fiber.ErrNotFound
	}
	row := r[0]
	kind := fmt.Sprint(row["kind"])
	if e = s.require(c, adminKinds[kind]); e != nil {
		return e
	}
	action := c.Params("action")
	if action == "cancel" {
		_, e = s.db.query(`MATCH(o:AdminOperation {id:$id,status:'proposed'}) SET o.status='cancelled',o.updated_at=$now`, map[string]interface{}{"id": id, "now": time.Now().UnixMilli()})
		if e != nil {
			return e
		}
		return s.operationDetail(c)
	}
	if action == "refresh" {
		if e = s.refreshAdminChain(c, id, kind, adminDecode(row["result"])); e != nil {
			return e
		}
		return s.operationDetail(c)
	}
	if action != "execute" && action != "simulate" {
		return fiber.ErrNotFound
	}
	payload := adminDecode(row["payload"])
	spec, chain, e := s.adminChainSpec(kind, id, payload)
	if e != nil {
		return failure(c, 409, "operation_not_ready", e.Error())
	}
	if !chain {
		if e = s.validateAdminLocal(kind, payload); e != nil {
			return failure(c, 409, "validation_failed", e.Error())
		}
	}
	if action == "simulate" {
		if chain {
			ctx, cancel := context.WithTimeout(c.Context(), 12*time.Second)
			defer cancel()
			if e = s.simulateAdminChain(ctx, spec); e != nil {
				return failure(c, 409, "simulation_failed", e.Error())
			}
		}
		return c.JSON(fiber.Map{"simulated": true, "chain_action": chain, "review": spec, "message": "Validation complete. Execution still requires an explicit confirmation."})
	}
	if row["status"] != "proposed" {
		return s.operationDetail(c)
	}
	claims, e := s.db.adminRows(`MATCH(o:AdminOperation {id:$id,status:'proposed'}) SET o.status='executing',o.executor=$actor,o.updated_at=$now RETURN o.id`, map[string]interface{}{"id": id, "actor": s.who(c).Email, "now": time.Now().UnixMilli()}, "id")
	if e != nil {
		return e
	}
	if len(claims) == 0 {
		return failure(c, 409, "operation_busy", "This operation is already being handled.")
	}
	var result any
	if chain {
		ctx, cancel := context.WithTimeout(c.Context(), 15*time.Second)
		defer cancel()
		result, e = s.executeAdminChain(ctx, id, spec)
	} else {
		result, e = s.executeLocal(id, kind, payload)
	}
	status := "confirmed"
	if chain {
		status = "submitted"
	}
	if e != nil {
		status = "needs_review"
		result = fiber.Map{"error": e.Error(), "spec": spec}
	}
	_, saveErr := s.db.query(`MATCH(o:AdminOperation {id:$id}) SET o.status=$status,o.result=$result,o.updated_at=$now`, map[string]interface{}{"id": id, "status": status, "result": adminJSON(result), "now": time.Now().UnixMilli()})
	if saveErr != nil {
		return saveErr
	}
	return s.operationDetail(c)
}
func (s *adminSystem) executeLocal(op, kind string, p map[string]any) (any, error) {
	id := fmt.Sprint(p["player_id"])
	params := map[string]interface{}{"id": id, "now": time.Now().UnixMilli()}
	var q string
	switch kind {
	case "suspend", "restore":
		status := "suspended"
		if kind == "restore" {
			status = "active"
		}
		params["status"] = status
		q = `MATCH(u:User {id:$id}) SET u.admin_status=$status RETURN u.id`
	case "revoke_sessions":
		q = `MATCH(u:User {id:$id}) SET u.admin_sessions_after=$now WITH u OPTIONAL MATCH(u)-[:HAS_LOGIN_SESSION]->(l:LoginSession) DETACH DELETE l RETURN u.id`
	case "restrict_uploads", "restrict_social":
		value, ok := p["restricted"].(bool)
		if !ok {
			return nil, errors.New("restricted must be true or false")
		}
		params["restricted"] = value
		field := "upload_restricted"
		if kind == "restrict_social" {
			field = "social_restricted"
		}
		q = `MATCH(u:User {id:$id}) SET u.` + field + `=$restricted RETURN u.id`
	case "quarantine_photo", "restore_photo":
		key := fmt.Sprint(p["photo_id"])
		if !validHex(key, 16) || !validHex(id, 16) {
			return nil, errors.New("valid player/photo IDs are required")
		}
		params["key"] = id + "/" + key
		params["hidden"] = kind == "quarantine_photo"
		q = `MATCH(u:User {id:$id}) MERGE(m:AdminMedia {key:$key}) SET m.hidden=$hidden,m.updated_at=$now RETURN u.id`
	case "quarantine_score", "restore_score":
		params["key"] = fmt.Sprint(p["score_id"])
		params["hidden"] = kind == "quarantine_score"
		q = `MATCH(b:PersonalBest {key:$key}) SET b.quarantined=$hidden RETURN b.key`
	case "retry_job":
		typ := fmt.Sprint(p["job_type"])
		label := map[string]string{"shop": "ShopOperation", "payout": "StarlightPayout", "score": "LeaderboardPublication", "wallet": "Wallet"}[typ]
		if label == "" {
			return nil, errors.New("select a valid queue")
		}
		params["key"] = fmt.Sprint(p["job_id"])
		field := "next_attempt_at"
		if typ == "shop" {
			field = "next_at"
		}
		q = `MATCH(j:` + label + ` {key:$key}) WHERE coalesce(j.lease_until,0)<=$now AND j.status<>'confirmed' SET j.` + field + `=0 RETURN j.key`
	case "grant_xp", "grant_energy":
		amount := adminInt(p["amount"])
		if amount < 1 || amount > 100000 {
			return nil, errors.New("amount must be 1–100000")
		}
		if kind == "grant_energy" && amount > 15 {
			return nil, errors.New("energy grant cannot exceed 15")
		}
		for i := 0; i < 8; i++ {
			progress, version, e := s.db.ReadProgress(id)
			if e != nil {
				return nil, e
			}
			progress.normalize(time.Now())
			marker := "admin_" + op
			if progress.Claimed[marker] {
				return fiber.Map{"already_applied": true}, nil
			}
			progress.Claimed[marker] = true
			if kind == "grant_xp" {
				progress.XP += amount
			} else {
				progress.Energy.Current = min(energyCap, progress.Energy.Current+int(amount))
				if progress.Energy.Current == energyCap {
					progress.Energy.NextAt = 0
				}
			}
			done, e := s.db.WriteProgress(id, version, progress)
			if e != nil {
				return nil, e
			}
			if done {
				return fiber.Map{"player_id": id, "amount": amount, "kind": kind}, nil
			}
		}
		return nil, errors.New("player state is busy; operation requires reconciliation")
	default:
		return nil, errors.New("unsupported local operation")
	}
	r, e := s.db.adminRows(q, params, "id")
	if e != nil {
		return nil, e
	}
	if len(r) == 0 {
		return nil, errors.New("target was not found or still holds an active lease")
	}
	return fiber.Map{"applied": true, "target": r[0]["id"]}, nil
}

// Only link an explorer when its chain-specific address route is known.
func adminContractExplorer(chain int64, address string) string {
	if address == "" {
		return ""
	}
	if chain == 421614 {
		return "https://sepolia.arbiscan.io/address/" + address
	}
	return ""
}

func adminNetworkName(chain int64) string {
	if chain == 99901 {
		return "Elysium Mainnet"
	}
	if chain == 421614 {
		return "Arbitrum Sepolia"
	}
	return fmt.Sprintf("Chain %d", chain)
}
