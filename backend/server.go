package main

import (
	"bytes"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/limiter"
	"github.com/gofiber/fiber/v3/middleware/recover"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

const issuer = "rescene-rhythm-api"
const audience = "rescene-rhythm-game"

var usernamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{3,24}$`)

const legalPolicyVersion = "2026-11-11"

type credentials struct {
	Username       string `json:"username"`
	Password       string `json:"password"`
	AcceptPolicies bool   `json:"accept_policies"`
	TermsVersion   string `json:"terms_version"`
	PrivacyVersion string `json:"privacy_version"`
}
type api struct {
	eventRewards *starlightService
	store        userStore
	config       config
	cost         int
	dummyHash    []byte
	wallets      *walletService
	publications *publicationService
	replaySlots  chan struct{}
	mediaSlots   chan struct{}
	marketplace  *marketplaceService
	starlight    *starlightService
	shop         *shopService
	admin        *adminSystem
}

func failure(c fiber.Ctx, status int, code, message string) error {
	return c.Status(status).JSON(fiber.Map{"error": fiber.Map{"code": code, "message": message}})
}

func newApp(store userStore, cfg config, cost int) (*fiber.App, error) {
	dummy, err := bcrypt.GenerateFromPassword([]byte("unused-dummy-password"), cost)
	if err != nil {
		return nil, err
	}
	a := &api{store: store, config: cfg, cost: cost, dummyHash: dummy, replaySlots: make(chan struct{}, 2), mediaSlots: make(chan struct{}, 2)}
	a.marketplace = newMarketplaceService(cfg)
	a.wallets, err = startWalletService(store, cfg)
	if err != nil {
		return nil, err
	}
	a.publications, err = startPublicationService(store, cfg)
	if err != nil {
		_ = a.wallets.close()
		return nil, err
	}
	a.starlight, err = startStarlightService(store, cfg)
	if err != nil {
		_ = a.wallets.close()
		_ = a.publications.close()
		return nil, err
	}
	a.shop, err = startShopService(store, cfg)
	if err != nil {
		_ = a.wallets.close()
		_ = a.publications.close()
		_ = a.starlight.close()
		return nil, err
	}
	a.eventRewards, err = startEventRewards(store, cfg)
	if err != nil {
		_ = a.wallets.close()
		_ = a.publications.close()
		_ = a.starlight.close()
		_ = a.shop.close()
		return nil, err
	}
	app := fiber.New(fiber.Config{BodyLimit: profileUploadLimit, ReadTimeout: 20 * time.Second, WriteTimeout: 25 * time.Second, IdleTimeout: 30 * time.Second,
		ErrorHandler: func(c fiber.Ctx, err error) error {
			var pe progressError
			if errors.As(err, &pe) {
				return failure(c, pe.status, "progression_error", pe.message)
			}
			status := 500
			var fe *fiber.Error
			if errors.As(err, &fe) {
				status = fe.Code
			}
			if status >= 500 {
				log.Printf("request failed: %v", err)
				return failure(c, status, "server_error", "The server could not complete your request.")
			}
			return failure(c, status, "request_error", fiber.ErrBadRequest.Message)
		}})
	app.Use(recover.New())
	app.Use(func(c fiber.Ctx) error {
		if a.config.EdgeSecret != "" && subtle.ConstantTimeCompare([]byte(c.Get("X-Remine-Edge")), []byte(a.config.EdgeSecret)) != 1 {
			return fiber.ErrNotFound
		}
		return c.Next()
	})
	app.Use(func(c fiber.Ctx) error {
		if strings.HasPrefix(c.Path(), "/api/admin/v1/") {
			if c.Path() != "/api/admin/v1/assets" && len(c.Body()) > 65536 {
				return fiber.ErrRequestEntityTooLarge
			}
			return c.Next()
		}
		if isProfileUpload(c) {
			return c.Next()
		}
		if len(c.Body()) > 1048576 {
			return failure(c, 413, "body_limit", "Request is too large.")
		}
		if len(c.Body()) > 4096 && !(c.Method() == "POST" && strings.HasPrefix(c.Path(), "/api/v1/runs/") && strings.HasSuffix(c.Path(), "/complete")) {
			return failure(c, 413, "body_limit", "Request is too large.")
		}
		return c.Next()
	})
	app.Hooks().OnPreShutdown(a.wallets.close)
	app.Hooks().OnPreShutdown(a.publications.close)
	app.Hooks().OnPreShutdown(a.starlight.close)
	app.Hooks().OnPreShutdown(a.shop.close)
	app.Hooks().OnPreShutdown(a.eventRewards.close)
	app.Use(func(c fiber.Ctx) error {
		c.Set("Cache-Control", "no-store")
		c.Set("X-Content-Type-Options", "nosniff")
		return c.Next()
	})
	app.Get("/download", func(c fiber.Ctx) error {
		path := os.Getenv("APK_RELEASE_PATH")
		if path == "" {
			return fiber.ErrNotFound
		}
		if _, e := os.Stat(path); e != nil {
			return fiber.ErrNotFound
		}
		c.Set("Content-Type", "application/vnd.android.package-archive")
		c.Set("Content-Disposition", `attachment; filename="RESCENE-Rhythm.apk"`)
		return c.SendFile(path)
	})
	app.Get("/healthz", func(c fiber.Ctx) error {
		if err := store.Ping(); err != nil {
			return failure(c, 503, "unavailable", "Database unavailable.")
		}
		return c.JSON(fiber.Map{"status": "ok"})
	})
	limit := func(max int, window time.Duration) fiber.Handler {
		return limiter.New(limiter.Config{Max: max, Expiration: window, KeyGenerator: func(c fiber.Ctx) string {
			if a.config.EdgeSecret != "" {
				if ip := net.ParseIP(c.Get("X-Remine-Client-IP")); ip != nil {
					return ip.String()
				}
			}
			return c.IP()
		}, LimitReached: func(c fiber.Ctx) error {
			return failure(c, 429, "rate_limited", "Too many attempts. Please wait a little and try again.")
		}})
	}
	socialLimit := func(max int) fiber.Handler {
		return limiter.New(limiter.Config{Max: max, Expiration: time.Minute, KeyGenerator: func(c fiber.Ctx) string { return c.Locals("user").(user).ID }, LimitReached: func(c fiber.Ctx) error {
			return failure(c, 429, "rate_limited", "Please wait a moment before trying again.")
		}})
	}
	app.Post("/api/v1/auth/register", limit(5, 10*time.Minute), a.register)
	app.Post("/api/v1/auth/login", limit(15, time.Minute), a.login)
	app.Post("/api/v1/auth/recover", limit(5, 15*time.Minute), a.recoverAccount)
	app.Post("/api/v1/auth/refresh", limit(60, time.Minute), a.refreshSession)
	app.Post("/api/v1/auth/logout", limit(60, time.Minute), a.logoutSession)
	app.Post("/api/v1/auth/session", limit(15, time.Minute), a.authenticate, func(c fiber.Ctx) error {
		return a.session(c, c.Locals("user").(user), 200)
	})
	app.Get("/api/v1/auth/me", a.authenticate, func(c fiber.Ctx) error { return c.JSON(fiber.Map{"user": a.walletUser(c.Locals("user").(user))}) })
	progress := app.Group("/api/v1", a.authenticate)
	progress.Get("/progression", a.getProgress)
	progress.Get("/events", a.getEvents)
	progress.Get("/mastery/:song", a.getMastery)
	progress.Post("/mastery/:song/:mission/claim", limit(30, time.Minute), a.claimMastery)
	progress.Post("/events/:event/missions/:mission/claim", limit(30, time.Minute), a.claimEvent)
	progress.Get("/account/security", a.accountSecurity)
	progress.Post("/account/recovery-codes", socialLimit(5), a.generateRecoveryCodes)
	progress.Post("/account/password", socialLimit(5), a.changePassword)
	progress.Post("/daily-login/claim", limit(30, time.Minute), a.claimDailyLogin)
	progress.Get("/records", a.getRecords)
	progress.Get("/leaderboard-publication", a.getPublication)
	progress.Get("/leaderboards", limit(90, time.Minute), a.getLeaderboard)
	progress.Get("/players/:id", limit(90, time.Minute), a.getPlayer)
	progress.Get("/players/:id/media/:key", limit(300, time.Minute), a.profilePhoto)
	progress.Get("/profile/media", a.profileMedia)
	progress.Get("/coop", socialLimit(60), a.getCoop)
	progress.Post("/coop/invite", socialLimit(10), a.inviteCoop)
	progress.Post("/coop/:id/action", socialLimit(30), a.actionCoop)
	progress.Post("/coop/:id/claim", socialLimit(30), a.claimCoop)
	progress.Get("/challenges", socialLimit(60), a.challenges)
	progress.Post("/challenges", socialLimit(10), a.createChallenge)
	progress.Post("/challenges/:id", socialLimit(30), a.challengeAction)
	progress.Get("/social/events", socialLimit(60), a.socialEvents)
	progress.Post("/social/conversations/:id/typing", socialLimit(30), a.socialTyping)
	progress.Get("/social", socialLimit(120), a.social)
	progress.Post("/reports", socialLimit(10), a.reportPlayer)
	progress.Get("/social/players", socialLimit(90), a.socialPlayers)
	progress.Post("/social/players/:id/:action", socialLimit(45), a.socialAction)
	progress.Post("/social/presence", socialLimit(30), a.presence)
	progress.Get("/social/conversations/:id", socialLimit(120), a.conversation)
	progress.Post("/social/conversations/:id/messages", socialLimit(60), a.sendMessage)
	progress.Post("/social/conversations/:id/read", socialLimit(120), a.readMessages)
	progress.Post("/profile/media/:kind", limit(30, time.Minute), a.changeProfilePhoto)
	progress.Put("/profile/media/:kind/:key", limit(30, time.Minute), a.changeProfilePhoto)
	progress.Delete("/profile/media/:kind/:key", limit(30, time.Minute), a.changeProfilePhoto)
	progress.Get("/wallet", a.walletStatus)
	progress.Get("/marketplace", limit(60, time.Minute), a.getMarketplace)
	progress.Get("/starlight", limit(60, time.Minute), a.getStarlight)
	progress.Get("/shop/catalog", limit(60, time.Minute), a.shopCatalog)
	progress.Get("/inventory", limit(90, time.Minute), a.getInventory)
	progress.Post("/shop/purchase", limit(15, time.Minute), a.buyItem)
	progress.Post("/collection/quote", limit(60, time.Minute), a.quotePulseCard)
	progress.Post("/collection/action", limit(15, time.Minute), a.actPulseCard)
	progress.Post("/collection/enhance", limit(15, time.Minute), a.enhanceCard)
	progress.Post("/collection/equip", limit(30, time.Minute), a.equipMemberCard)
	progress.Post("/inventory/consume", limit(15, time.Minute), a.consumeItem)
	progress.Post("/wallet/provision", limit(6, time.Minute), a.walletStatus)
	progress.Post("/runs", limit(30, time.Minute), a.startRun)
	progress.Post("/runs/:id/abandon", limit(30, time.Minute), a.abandonRun)
	progress.Post("/runs/:id/complete", limit(60, time.Minute), a.completeRun)
	progress.Post("/missions/:id/claim", limit(30, time.Minute), a.claimMission)
	progress.Post("/progression/equip", limit(30, time.Minute), a.equipCosmetic)
	if err := a.installAdmin(app); err != nil {
		return nil, err
	}
	app.Use(func(c fiber.Ctx) error { return failure(c, 404, "not_found", "Endpoint not found.") })
	return app, nil
}

func readCredentials(c fiber.Ctx) (credentials, error) {
	var data credentials
	if strings.Split(c.Get("Content-Type"), ";")[0] != "application/json" {
		return data, errors.New("Send username and password as JSON.")
	}
	decoder := json.NewDecoder(bytes.NewReader(c.Body()))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&data); err != nil {
		return data, errors.New("Invalid username or password request.")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return data, errors.New("Send one JSON object.")
	}
	data.Username = strings.TrimSpace(data.Username)
	if !usernamePattern.MatchString(data.Username) {
		return data, errors.New("Username must be 3–24 letters, numbers or underscores.")
	}
	if !utf8.ValidString(data.Password) || len(data.Password) > 72 || utf8.RuneCountInString(data.Password) < 8 {
		return data, errors.New("Password must be at least 8 characters and no more than 72 bytes.")
	}
	return data, nil
}

func (a *api) register(c fiber.Ctx) error {
	data, err := readCredentials(c)
	if err != nil {
		return failure(c, 400, "invalid_input", err.Error())
	}
	if !data.AcceptPolicies || data.TermsVersion != legalPolicyVersion || data.PrivacyVersion != legalPolicyVersion {
		return failure(c, 400, "policy_agreement_required", "Please review and accept the current Terms & Conditions and Privacy Policy. Update the app if this option is missing.")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(data.Password), a.cost)
	if err != nil {
		return err
	}
	id := make([]byte, 16)
	if _, err = rand.Read(id); err != nil {
		return err
	}
	u, err := a.store.Create(user{ID: hex.EncodeToString(id), Username: data.Username, CreatedAt: time.Now().UTC().Format(time.RFC3339), PasswordHash: string(hash), TermsVersion: legalPolicyVersion, PrivacyVersion: legalPolicyVersion, LegalAcceptedAt: time.Now().UTC().Format(time.RFC3339)}, strings.ToLower(data.Username))
	if errors.Is(err, errDuplicate) {
		return failure(c, 409, "username_taken", "That username is already taken.")
	}
	if err != nil {
		return err
	}
	return a.session(c, u, 201)
}
func (a *api) login(c fiber.Ctx) error {
	data, err := readCredentials(c)
	if err != nil {
		return failure(c, 400, "invalid_input", err.Error())
	}
	u, err := a.store.ByUsername(strings.ToLower(data.Username))
	if errors.Is(err, errNotFound) {
		_ = bcrypt.CompareHashAndPassword(a.dummyHash, []byte(data.Password))
		return failure(c, 401, "invalid_credentials", "Incorrect username or password.")
	}
	if err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(data.Password)) != nil {
		return failure(c, 401, "invalid_credentials", "Incorrect username or password.")
	}
	return a.session(c, u, 200)
}
func (a *api) session(c fiber.Ctx, u user, status int) error {
	store, ok := a.store.(sessionStore)
	if !ok {
		return failure(c, 503, "unavailable", "Persistent login is unavailable.")
	}
	refresh, err := newRefreshToken()
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	expires := now.Add(refreshLifetime).Unix()
	if err = store.CreateSession(u.ID, refreshHash(refresh), now.Unix(), expires); err != nil {
		return err
	}
	return a.sessionResponse(c, u, status, refresh, expires)
}
func (a *api) authenticate(c fiber.Ctx) error {
	parts := strings.Fields(c.Get("Authorization"))
	unauthorized := func() error {
		c.Set("WWW-Authenticate", `Bearer realm="rescene"`)
		return failure(c, 401, "unauthorized", "Your session has expired. Please log in again.")
	}
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return unauthorized()
	}
	claims := &accessClaims{}
	token, err := jwt.ParseWithClaims(parts[1], claims, func(_ *jwt.Token) (any, error) { return a.config.Secret, nil }, jwt.WithValidMethods([]string{"HS256"}), jwt.WithIssuer(issuer), jwt.WithAudience(audience), jwt.WithExpirationRequired(), jwt.WithIssuedAt())
	if err != nil || !token.Valid || claims.Subject == "" {
		return unauthorized()
	}
	u, err := a.store.ByID(claims.Subject)
	if errors.Is(err, errNotFound) {
		return unauthorized()
	}
	if err != nil {
		return err
	}
	c.Locals("user", u)
	if claims.PasswordVersion != u.PasswordVersion {
		return unauthorized()
	}
	if a.admin != nil {
		if err := a.admin.playerGate(c, u.ID); err != nil {
			return err
		}
		rows, err := a.admin.db.adminRows(`MATCH(u:User {id:$id}) RETURN coalesce(u.admin_sessions_after,0)`, map[string]interface{}{"id": u.ID}, "after")
		if err != nil {
			return err
		}
		if len(rows) > 0 && adminInt(rows[0]["after"]) > 0 && (claims.IssuedAt == nil || claims.IssuedAt.Unix() <= adminInt(rows[0]["after"])/1000) {
			return unauthorized()
		}
	}
	started := time.Now()
	err = c.Next()
	if a.admin != nil {
		a.admin.telemetry(c, err, time.Since(started))
	}
	return err
}
