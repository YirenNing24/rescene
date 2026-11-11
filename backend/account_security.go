package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gofiber/fiber/v3"
	"golang.org/x/crypto/bcrypt"
)

type accountSecurityStore interface {
	RecoveryCount(string) (int64, error)
	SaveRecoveryCodes(string, string, []string) (bool, error)
	ChangePassword(string, string, string) (bool, error)
	RecoverPassword(string, string, string) (bool, error)
}

func (s *graphStore) ValidateLoginSession(owner, hash string, version int64) (bool, error) {
	rows, err := s.query(`MATCH(u:User {id:$owner})-[:HAS_LOGIN_SESSION]->(l:LoginSession {token_hash:$hash}) WHERE coalesce(u.password_version,0)=$version AND l.expires_at>$now RETURN u.id`, map[string]interface{}{"owner": owner, "hash": hash, "version": version, "now": time.Now().Unix()})
	if err != nil {
		return false, err
	}
	return rows.Next(), nil
}

func validPassword(password string) bool {
	return utf8.ValidString(password) && utf8.RuneCountInString(password) >= 8 && len(password) <= 72
}
func recoveryDigest(code string) string {
	normalized := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(code), "-", ""))
	if !validHex(normalized, 16) {
		return ""
	}
	hash := sha256.Sum256([]byte(normalized))
	return hex.EncodeToString(hash[:])
}
func (s *graphStore) RecoveryCount(owner string) (int64, error) {
	rows, err := s.query(`MATCH(u:User {id:$owner}) RETURN size(coalesce(u.recovery_hashes,[]))`, map[string]interface{}{"owner": owner})
	if err != nil {
		return 0, err
	}
	if !rows.Next() {
		return 0, errNotFound
	}
	v, _ := rows.Record().GetByIndex(0)
	return v.(int64), nil
}
func (s *graphStore) SaveRecoveryCodes(owner, hash string, codes []string) (bool, error) {
	rows, err := s.query(`MATCH(u:User {id:$owner,password_hash:$hash}) SET u.recovery_hashes=$codes RETURN u.id`, map[string]interface{}{"owner": owner, "hash": hash, "codes": codes})
	if err != nil {
		return false, err
	}
	return rows.Next(), nil
}
func (s *graphStore) ChangePassword(owner, previous, next string) (bool, error) {
	rows, err := s.query(`MATCH(u:User {id:$owner,password_hash:$previous}) SET u.password_hash=$next,u.password_version=coalesce(u.password_version,0)+1 WITH u OPTIONAL MATCH(u)-[:HAS_LOGIN_SESSION]->(l:LoginSession) DETACH DELETE l RETURN DISTINCT u.id`, map[string]interface{}{"owner": owner, "previous": previous, "next": next})
	if err != nil {
		return false, err
	}
	return rows.Next(), nil
}
func (s *graphStore) RecoverPassword(username, code, next string) (bool, error) {
	rows, err := s.query(`MATCH(u:User {username_key:$username}) WHERE $code IN coalesce(u.recovery_hashes,[]) SET u.password_hash=$next,u.password_version=coalesce(u.password_version,0)+1,u.recovery_hashes=[v IN u.recovery_hashes WHERE v<>$code] WITH u OPTIONAL MATCH(u)-[:HAS_LOGIN_SESSION]->(l:LoginSession) DETACH DELETE l RETURN DISTINCT u.id`, map[string]interface{}{"username": username, "code": code, "next": next})
	if err != nil {
		return false, err
	}
	return rows.Next(), nil
}
func (a *api) accountSecurity(c fiber.Ctx) error {
	store, ok := a.store.(accountSecurityStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	count, err := store.RecoveryCount(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"security": fiber.Map{"recovery_codes_remaining": count}})
}
func (a *api) generateRecoveryCodes(c fiber.Ctx) error {
	store, ok := a.store.(accountSecurityStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	var body struct {
		Password string `json:"password"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	u := c.Locals("user").(user)
	if !validPassword(body.Password) || bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(body.Password)) != nil {
		return failure(c, 403, "invalid_password", "Your current password is incorrect.")
	}
	codes, hashes := []string{}, []string{}
	for range 8 {
		raw := make([]byte, 16)
		if _, err := rand.Read(raw); err != nil {
			return err
		}
		value := hex.EncodeToString(raw)
		code := value[:8] + "-" + value[8:16] + "-" + value[16:24] + "-" + value[24:]
		codes = append(codes, code)
		hashes = append(hashes, recoveryDigest(code))
	}
	saved, err := store.SaveRecoveryCodes(u.ID, u.PasswordHash, hashes)
	if err != nil {
		return err
	}
	if !saved {
		return failure(c, 409, "account_changed", "Your password changed. Log in again.")
	}
	return c.JSON(fiber.Map{"recovery_codes": codes, "message": "Save these codes privately. Each works once. Previous codes are now invalid."})
}
func (a *api) changePassword(c fiber.Ctx) error {
	store, ok := a.store.(accountSecurityStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	var body struct {
		Current string `json:"current_password"`
		Next    string `json:"new_password"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	u := c.Locals("user").(user)
	if !validPassword(body.Next) {
		return failure(c, 400, "invalid_password", "Use 8 or more characters, up to 72 UTF-8 bytes.")
	}
	if !validPassword(body.Current) || bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(body.Current)) != nil {
		return failure(c, 403, "invalid_password", "Your current password is incorrect.")
	}
	next, err := bcrypt.GenerateFromPassword([]byte(body.Next), a.cost)
	if err != nil {
		return err
	}
	saved, err := store.ChangePassword(u.ID, u.PasswordHash, string(next))
	if err != nil {
		return err
	}
	if !saved {
		return failure(c, 409, "account_changed", "Your password changed. Log in again.")
	}
	return c.JSON(fiber.Map{"ok": true, "message": "Password changed. Log in again on your devices."})
}
func (a *api) recoverAccount(c fiber.Ctx) error {
	store, ok := a.store.(accountSecurityStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	var body struct {
		Username string `json:"username"`
		Code     string `json:"recovery_code"`
		Next     string `json:"new_password"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	body.Username = strings.ToLower(strings.TrimSpace(body.Username))
	digest := recoveryDigest(body.Code)
	if !validPassword(body.Next) {
		return failure(c, 400, "invalid_password", "Use 8 or more characters, up to 72 UTF-8 bytes.")
	}
	if !usernamePattern.MatchString(body.Username) || digest == "" {
		return failure(c, 401, "invalid_recovery", "The username or recovery code is incorrect or already used.")
	}
	next, err := bcrypt.GenerateFromPassword([]byte(body.Next), a.cost)
	if err != nil {
		return err
	}
	saved, err := store.RecoverPassword(body.Username, digest, string(next))
	if errors.Is(err, errNotFound) || err == nil && !saved {
		return failure(c, 401, "invalid_recovery", "The username or recovery code is incorrect or already used.")
	}
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true, "message": "Password reset. Log in with your new password."})
}
