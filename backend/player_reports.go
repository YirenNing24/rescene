package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gofiber/fiber/v3"
)

type reportRequest struct {
	ID      string `json:"request_id"`
	Kind    string `json:"target_type"`
	Player  string `json:"player_id"`
	Target  string `json:"target_id"`
	Reason  string `json:"reason"`
	Details string `json:"details"`
}

func (a *api) reportPlayer(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	var body reportRequest
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	body.Details = strings.TrimSpace(body.Details)
	if !validHex(body.ID, 16) || !validHex(body.Player, 16) || body.Player == owner || !utf8.ValidString(body.Details) || len(body.Details) > 1500 {
		return fiber.ErrBadRequest
	}
	if !map[string]bool{"harassment": true, "spam": true, "inappropriate_content": true, "cheating": true, "other": true}[body.Reason] {
		return failure(c, 400, "invalid_reason", "Choose a report reason.")
	}
	raw, _ := json.Marshal(body)
	digest := sha256.Sum256(raw)
	hash := hex.EncodeToString(digest[:])
	ticket := sha256.Sum256([]byte(owner + "/" + body.ID))
	id := hex.EncodeToString(ticket[:16])
	key := "reports/" + id
	prior, err := s.query(`MATCH(d:AdminDocument {key:$key}) RETURN d.request_hash`, map[string]interface{}{"key": key})
	if err != nil {
		return err
	}
	if prior.Next() {
		old, _ := prior.Record().GetByIndex(0)
		if old != hash {
			return failure(c, 409, "report_conflict", "This report ID belongs to another report.")
		}
		return c.JSON(fiber.Map{"report_id": id, "status": "received"})
	}
	peer, err := s.ByID(body.Player)
	if errors.Is(err, errNotFound) {
		return fiber.ErrNotFound
	}
	if err != nil {
		return err
	}
	evidence := map[string]any{"reporter_id": owner, "player_id": peer.ID, "username": peer.Username, "target_type": body.Kind, "target_id": body.Target, "reason": body.Reason, "details": body.Details}
	switch body.Kind {
	case "player":
		if body.Target != "" && body.Target != peer.ID {
			return fiber.ErrBadRequest
		}
	case "photo":
		media, err := s.ReadProfileMedia(peer.ID)
		if err != nil {
			return err
		}
		if !media.contains(body.Target) {
			return failure(c, 404, "photo_missing", "This photo is no longer on that profile.")
		}
		evidence["photo_url"] = "/api/v1/players/" + peer.ID + "/media/" + body.Target
		raw, err := os.ReadFile(filepath.Join(a.mediaDirectory(), peer.ID, body.Target+".jpg"))
		if err != nil {
			return fiber.ErrNotFound
		}
		// Retain the reported normalized photo even if its owner deletes it.
		dir := filepath.Join(a.mediaDirectory(), "report_evidence")
		if err := os.MkdirAll(dir, 0700); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, id+".jpg"), raw, 0600); err != nil {
			return err
		}
		evidence["evidence_url"] = "/api/admin/v1/reports/" + id + "/photo"
		evidence["photo_hash"] = hashHex(raw)
	case "message":
		if len(body.Target) > 180 {
			return fiber.ErrBadRequest
		}
		rows, err := s.query(`MATCH(c:Conversation {key:$key})-[:HAS_MESSAGE]->(m:DirectMessage {key:$target}) WHERE m.sender=$peer AND (c.a=$owner OR c.b=$owner) RETURN m.body,m.at,m.seq`, map[string]interface{}{"key": conversationKey(owner, peer.ID), "target": body.Target, "peer": peer.ID, "owner": owner})
		if err != nil {
			return err
		}
		if !rows.Next() {
			return failure(c, 404, "message_missing", "Choose a received message from this conversation.")
		}
		r := rows.Record()
		text, _ := r.GetByIndex(0)
		at, _ := r.GetByIndex(1)
		seq, _ := r.GetByIndex(2)
		evidence["message"] = text
		evidence["sent_at"] = at
		evidence["sequence"] = seq
	default:
		return fiber.ErrBadRequest
	}
	snapshot, _ := json.Marshal(evidence)
	now := time.Now().UTC()
	day := now.Format("2006-01-02")
	rows, err := s.query(`MATCH(u:User {id:$owner}) OPTIONAL MATCH(old:AdminDocument {key:$key})
 WITH u,old WHERE (old IS NOT NULL AND old.request_hash=$hash) OR (old IS NULL AND (coalesce(u.report_day,'')<>$day OR coalesce(u.report_count,0)<10))
 MERGE(d:AdminDocument {key:$key}) ON CREATE SET d.id=$id,d.group='reports',d.name=$name,d.status='published',d.revision=1,d.updated_at=$now,d.updated_by=$owner,d.value=$value,d.request_hash=$hash,u.report_count=CASE WHEN u.report_day=$day THEN u.report_count+1 ELSE 1 END,u.report_day=$day
 RETURN d.request_hash`, map[string]interface{}{"owner": owner, "key": key, "id": id, "name": "Player report · " + peer.Username, "hash": hash, "value": string(snapshot), "day": day, "now": now.UnixMilli()})
	if err != nil {
		return err
	}
	if !rows.Next() {
		return failure(c, 429, "report_limit", "You have reached today's report limit. You can still block this player.")
	}
	old, _ := rows.Record().GetByIndex(0)
	if old != hash {
		return failure(c, 409, "report_conflict", "This report ID belongs to another report.")
	}
	return c.JSON(fiber.Map{"report_id": id, "status": "received"})
}

func (s *adminSystem) reportPhoto(c fiber.Ctx) error {
	if e := s.require(c, "support"); e != nil {
		return e
	}
	id := c.Params("id")
	if !validHex(id, 16) {
		return fiber.ErrNotFound
	}
	rows, e := s.db.query(`MATCH(d:AdminDocument {key:$key}) RETURN d.id`, map[string]interface{}{"key": "reports/" + id})
	if e != nil {
		return e
	}
	if !rows.Next() {
		return fiber.ErrNotFound
	}
	raw, e := os.ReadFile(filepath.Join(s.api.mediaDirectory(), "report_evidence", id+".jpg"))
	if e != nil {
		return fiber.ErrNotFound
	}
	c.Set("Content-Type", "image/jpeg")
	return c.Send(raw)
}
