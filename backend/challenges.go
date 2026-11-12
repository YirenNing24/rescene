package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"time"

	"github.com/gofiber/fiber/v3"
)

// Results are written atomically with replay-verified progression.
// OPTIONAL is necessary: a run with no matching challenge must still commit.
const challengeScoreWriteSafe = `WITH p OPTIONAL MATCH(ch:FriendChallenge) WHERE ch.status='active' AND (ch.sender=$id OR ch.recipient=$id) AND ch.song_id=$song AND ch.difficulty=$difficulty AND ch.revision=$revision AND ch.accepted_at<=$challenge_start AND ch.expires_at>=$achieved
 FOREACH(v IN CASE WHEN ch IS NOT NULL AND ch.sender=$id AND (ch.score_a<$score OR (ch.score_a=$score AND ch.combo_a<$combo)) THEN [1] ELSE [] END | SET ch.score_a=$score,ch.combo_a=$combo,ch.run_a=$run)
 FOREACH(v IN CASE WHEN ch IS NOT NULL AND ch.recipient=$id AND (ch.score_b<$score OR (ch.score_b=$score AND ch.combo_b<$combo)) THEN [1] ELSE [] END | SET ch.score_b=$score,ch.combo_b=$combo,ch.run_b=$run)
 WITH DISTINCT p `

func (a *api) challenges(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	rows, e := s.adminRows(`MATCH(ch:FriendChallenge) WHERE ch.sender=$owner OR ch.recipient=$owner WITH ch MATCH(sender:User),(recipient:User) WHERE sender.id=ch.sender AND recipient.id=ch.recipient RETURN ch.id,ch.sender,ch.recipient,ch.song_id,ch.title,ch.difficulty,ch.revision,ch.status,ch.expires_at,ch.score_a,ch.score_b,ch.combo_a,ch.combo_b,sender.username,recipient.username ORDER BY ch.created_at DESC LIMIT 50`, map[string]interface{}{"owner": owner}, "id", "sender", "recipient", "song_id", "title", "difficulty", "revision", "status", "expires_at", "score_a", "score_b", "combo_a", "combo_b", "sender_name", "recipient_name")
	if e != nil {
		return e
	}
	now := time.Now().UnixMilli()
	for _, v := range rows {
		if (v["status"] == "active" || v["status"] == "pending") && adminInt(v["expires_at"]) < now {
			if v["status"] == "pending" {
				v["status"] = "expired"
			} else {
				v["status"] = "finished"
				sa, sb := adminInt(v["score_a"]), adminInt(v["score_b"])
				v["winner"] = "tie"
				if sa > sb || sa == sb && adminInt(v["combo_a"]) > adminInt(v["combo_b"]) {
					v["winner"] = v["sender"]
				} else if sb > sa || sa == sb && adminInt(v["combo_b"]) > adminInt(v["combo_a"]) {
					v["winner"] = v["recipient"]
				}
				if sa < 0 && sb < 0 {
					v["winner"] = "unplayed"
				}
			}
		}
	}
	return c.JSON(fiber.Map{"challenges": rows})
}
func (a *api) createChallenge(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	var b struct {
		Request    string `json:"request_id"`
		Peer       string `json:"player_id"`
		Song       string `json:"song_id"`
		Difficulty string `json:"difficulty"`
	}
	if e := decodeProgressBody(c, &b); e != nil {
		return e
	}
	if !validHex(b.Request, 16) || !validHex(b.Peer, 16) || owner == b.Peer {
		return fiber.ErrBadRequest
	}
	chart, ok := rewardCharts[b.Song+"/"+b.Difficulty]
	if !ok || songSets[b.Song] == "" {
		return fiber.ErrBadRequest
	}
	raw, _ := json.Marshal(b)
	hash := sha256.Sum256(raw)
	sum := sha256.Sum256([]byte(owner + "/" + b.Request))
	id := hex.EncodeToString(sum[:16])
	digest := hex.EncodeToString(hash[:])
	now := time.Now().UnixMilli()
	rows, e := s.query(`MATCH(u:User {id:$owner}),(v:User {id:$peer}) OPTIONAL MATCH(old:FriendChallenge {id:$id}) OPTIONAL MATCH(u)-[f:FOLLOWS]->(v) OPTIONAL MATCH(v)-[r:FOLLOWS]->(u) OPTIONAL MATCH(u)-[b:BLOCKS]-(v)
 WITH u,v,old,count(DISTINCT f) AS outgoing,count(DISTINCT r) AS incoming,count(DISTINCT b) AS blocked WHERE (old IS NOT NULL AND old.request_hash=$hash) OR (old IS NULL AND outgoing>0 AND incoming>0 AND blocked=0 AND (coalesce(u.challenge_day,'')<>$day OR coalesce(u.challenge_count,0)<5))
 MERGE(ch:FriendChallenge {id:$id}) ON CREATE SET ch.request_hash=$hash,ch.sender=$owner,ch.recipient=$peer,ch.song_id=$song,ch.title=$title,ch.difficulty=$difficulty,ch.revision=$revision,ch.status='pending',ch.created_at=$now,ch.expires_at=$expires,ch.score_a=-1,ch.score_b=-1,ch.combo_a=0,ch.combo_b=0,u.challenge_count=CASE WHEN u.challenge_day=$day THEN u.challenge_count+1 ELSE 1 END,u.challenge_day=$day RETURN ch.id`, map[string]interface{}{"owner": owner, "peer": b.Peer, "id": id, "hash": digest, "song": b.Song, "title": chart.Title, "difficulty": b.Difficulty, "revision": chart.Revision, "now": now, "expires": now + int64((24 * time.Hour).Milliseconds()), "day": time.Now().UTC().Format("2006-01-02")})
	if e != nil {
		return e
	}
	if !rows.Next() {
		return failure(c, 409, "challenge_unavailable", "Choose a mutual friend. Up to five new challenges can be sent each day.")
	}
	a.notifyPlayer(b.Peer, "challenge", owner)
	return c.JSON(fiber.Map{"challenge_id": id})
}
func (a *api) challengeAction(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	id := c.Params("id")
	if !validHex(id, 16) {
		return fiber.ErrBadRequest
	}
	var b struct {
		Action string `json:"action"`
	}
	if e := decodeProgressBody(c, &b); e != nil {
		return e
	}
	target := map[string]string{"accept": "active", "decline": "declined", "cancel": "cancelled"}[b.Action]
	if target == "" {
		return fiber.ErrBadRequest
	}
	role := "ch.recipient=$owner"
	if b.Action == "cancel" {
		role = "ch.sender=$owner"
	}
	now := time.Now().UnixMilli()
	rows, e := s.query(`MATCH(ch:FriendChallenge {id:$id}) WITH ch MATCH(u:User),(v:User) WHERE u.id=ch.sender AND v.id=ch.recipient AND `+role+` AND ch.expires_at>$now AND (ch.status='pending' OR ch.status=$target)
 OPTIONAL MATCH(u)-[f:FOLLOWS]->(v) OPTIONAL MATCH(v)-[r:FOLLOWS]->(u) OPTIONAL MATCH(u)-[b:BLOCKS]-(v)
 WITH ch,count(DISTINCT f) AS outgoing,count(DISTINCT r) AS incoming,count(DISTINCT b) AS blocked WHERE $target<>'active' OR (outgoing>0 AND incoming>0 AND blocked=0)
 SET ch.accepted_at=CASE WHEN ch.status='pending' THEN $now ELSE ch.accepted_at END,ch.expires_at=CASE WHEN ch.status='pending' AND $target='active' THEN $expires ELSE ch.expires_at END,ch.status=$target RETURN ch.sender,ch.recipient`, map[string]interface{}{"owner": owner, "id": id, "now": now, "expires": now + int64((24 * time.Hour).Milliseconds()), "target": target})
	if e != nil {
		return e
	}
	if !rows.Next() {
		return failure(c, 409, "challenge_changed", "This invitation changed, expired or is unavailable.")
	}
	for i := 0; i < 2; i++ {
		peer, _ := rows.Record().GetByIndex(i)
		if peer != owner {
			a.notifyPlayer(peer.(string), "challenge", owner)
		}
	}
	return c.JSON(fiber.Map{"ok": true})
}
