package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/golang-jwt/jwt/v5"
)

const refreshLifetime = 30 * 24 * time.Hour

type accessClaims struct {
	jwt.RegisteredClaims
	PasswordVersion int64 `json:"password_version"`
}

type sessionStore interface {
	CreateSession(owner, hash string, now, expires int64) error
	RotateSession(previous, next, requestID string, now, expires int64) (string, int64, error)
	RevokeSession(hash string) error
}

func newRefreshToken() (string, error) {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func refreshHash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func validRefreshToken(token string) bool {
	value, err := base64.RawURLEncoding.DecodeString(token)
	return err == nil && len(value) == 32 && base64.RawURLEncoding.EncodeToString(value) == token
}

func (a *api) rotatedRefresh(token, requestID string) string {
	mac := hmac.New(sha256.New, a.config.Secret)
	_, _ = mac.Write([]byte("rescene/refresh/v1/" + token + "/" + requestID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *graphStore) CreateSession(owner, hash string, now, expires int64) error {
	// Prune only expired sessions belonging to this account. Other devices retain
	// independent sessions; each password login receives a fresh 30-day token.
	if _, err := s.query(`MATCH (:User {id:$owner})-[:HAS_LOGIN_SESSION]->(s:LoginSession) WHERE s.expires_at<=$now DETACH DELETE s`, map[string]interface{}{"owner": owner, "now": now}); err != nil {
		return err
	}
	r, err := s.query(`MATCH (u:User {id:$owner}) CREATE (u)-[:HAS_LOGIN_SESSION]->(s:LoginSession {token_hash:$hash,expires_at:$expires,created_at:$now}) RETURN s.expires_at`, map[string]interface{}{"owner": owner, "hash": hash, "expires": expires, "now": now})
	if err != nil {
		return err
	}
	if !r.Next() {
		return errNotFound
	}
	return nil
}

func (s *graphStore) RotateSession(previous, next, requestID string, now, expires int64) (string, int64, error) {
	params := map[string]interface{}{"previous": previous, "next": next, "request": requestID, "now": now, "expires": expires}
	r, err := s.query(`MATCH (u:User)-[:HAS_LOGIN_SESSION]->(s:LoginSession {token_hash:$previous}) WHERE s.expires_at>$now SET s.token_hash=$next,s.previous_hash=$previous,s.refresh_request=$request,s.expires_at=$expires RETURN u.id,s.expires_at`, params)
	if err != nil {
		return "", 0, err
	}
	if !r.Next() {
		// The client saves its random request ID before sending. An exact retry
		// recovers a lost response without storing any raw token in the graph.
		r, err = s.query(`MATCH (u:User)-[:HAS_LOGIN_SESSION]->(s:LoginSession {previous_hash:$previous}) WHERE s.token_hash=$next AND s.refresh_request=$request AND s.expires_at>$now RETURN u.id,s.expires_at`, params)
		if err != nil {
			return "", 0, err
		}
		if !r.Next() {
			return "", 0, errNotFound
		}
	}
	id, _ := r.Record().GetByIndex(0)
	until, _ := r.Record().GetByIndex(1)
	owner, ok := id.(string)
	expiry, valid := until.(int64)
	if !ok || !valid {
		return "", 0, errors.New("invalid login session")
	}
	return owner, expiry, nil
}

func (s *graphStore) RevokeSession(hash string) error {
	_, err := s.query(`MATCH (s:LoginSession) WHERE s.token_hash=$hash OR s.previous_hash=$hash DETACH DELETE s`, map[string]interface{}{"hash": hash})
	return err
}

func (a *api) sessionResponse(c fiber.Ctx, u user, status int, refresh string, refreshExpires int64) error {
	if store, ok := a.store.(interface {
		ValidateLoginSession(string, string, int64) (bool, error)
	}); ok {
		valid, err := store.ValidateLoginSession(u.ID, refreshHash(refresh), u.PasswordVersion)
		if err != nil {
			return err
		}
		if !valid {
			return failure(c, 401, "session_changed", "Your account credentials changed. Log in again.")
		}
	}
	now := time.Now().UTC()
	id := make([]byte, 16)
	if _, err := rand.Read(id); err != nil {
		return err
	}
	claims := accessClaims{RegisteredClaims: jwt.RegisteredClaims{ID: hex.EncodeToString(id), Subject: u.ID, Issuer: issuer, Audience: jwt.ClaimStrings{audience}, IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(now.Add(a.config.TokenTTL))}, PasswordVersion: u.PasswordVersion}
	access, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(a.config.Secret)
	if err != nil {
		return err
	}
	return c.Status(status).JSON(fiber.Map{"user": a.walletUser(u), "access_token": access, "token_type": "Bearer", "expires_in": int64(a.config.TokenTTL.Seconds()), "refresh_token": refresh, "refresh_expires_at": refreshExpires, "refresh_expires_in": max(int64(0), refreshExpires-now.Unix())})
}

func (a *api) refreshSession(c fiber.Ctx) error {
	var body struct {
		Token     string `json:"refresh_token"`
		RequestID string `json:"request_id"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	requestID, err := hex.DecodeString(body.RequestID)
	if !validRefreshToken(body.Token) || err != nil || len(requestID) != 16 || hex.EncodeToString(requestID) != body.RequestID {
		return failure(c, 401, "invalid_refresh", "Your saved login has expired. Please log in again.")
	}
	store, ok := a.store.(sessionStore)
	if !ok {
		return failure(c, 503, "unavailable", "Persistent login is unavailable.")
	}
	now := time.Now().UTC()
	next := a.rotatedRefresh(body.Token, body.RequestID)
	owner, expires, err := store.RotateSession(refreshHash(body.Token), refreshHash(next), body.RequestID, now.Unix(), now.Add(refreshLifetime).Unix())
	if errors.Is(err, errNotFound) {
		return failure(c, 401, "invalid_refresh", "Your saved login has expired. Please log in again.")
	}
	if err != nil {
		return err
	}
	u, err := a.store.ByID(owner)
	if errors.Is(err, errNotFound) {
		return failure(c, 401, "invalid_refresh", "Your account is no longer available.")
	}
	if err != nil {
		return err
	}
	return a.sessionResponse(c, u, 200, next, expires)
}

func (a *api) logoutSession(c fiber.Ctx) error {
	var body struct {
		Token string `json:"refresh_token"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if validRefreshToken(body.Token) {
		store, ok := a.store.(sessionStore)
		if !ok {
			return failure(c, 503, "unavailable", "Persistent login is unavailable.")
		}
		if err := store.RevokeSession(refreshHash(body.Token)); err != nil {
			return err
		}
	}
	return c.JSON(fiber.Map{"ok": true})
}
