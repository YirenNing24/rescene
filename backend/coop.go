package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"github.com/gofiber/fiber/v3"
)

type weeklyContribution struct {
	Clears  int             `json:"clears"`
	Perfect int             `json:"perfect"`
	Claimed map[string]bool `json:"claimed"`
}

func weekStart(t time.Time) time.Time {
	t = t.UTC().Truncate(24 * time.Hour)
	return t.AddDate(0, 0, -(int(t.Weekday())+6)%7)
}
func weekKey(t time.Time) string { return weekStart(t).Format("2006-01-02") }
func weekState(p *progression, key string) *weeklyContribution {
	if p.Coop == nil {
		p.Coop = map[string]*weeklyContribution{}
	}
	w := p.Coop[key]
	if w == nil {
		w = &weeklyContribution{}
		p.Coop[key] = w
	}
	if w.Claimed == nil {
		w.Claimed = map[string]bool{}
	}
	return w
}
func advanceCoop(p *progression, run runTicket, result runResult) {
	w := weekState(p, weekKey(time.UnixMilli(run.StartedAt)))
	w.Clears = min(100, w.Clears+1)
	w.Perfect = min(10000, w.Perfect+result.Counts["PERFECT"])
}
func coopFriendRows(s *graphStore, owner string) ([]map[string]interface{}, error) {
	return s.adminRows(`MATCH(c:CoopDuet) WHERE c.owner=$owner OR c.peer=$owner WITH c MATCH(a:User),(b:User) WHERE a.id=c.owner AND b.id=c.peer OPTIONAL MATCH(a)-[blocked:BLOCKS]-(b) WITH c,a,b,count(blocked) AS blocked_count WHERE blocked_count=0 RETURN c.id,c.owner,c.peer,c.week,c.status,c.created_at,a.username,b.username ORDER BY c.created_at DESC LIMIT 25`, map[string]interface{}{"owner": owner}, "id", "owner", "peer", "week", "status", "created_at", "owner_name", "peer_name")
}
func coopViews(s *graphStore, owner string, now time.Time) ([]fiber.Map, error) {
	rows, err := coopFriendRows(s, owner)
	if err != nil {
		return nil, err
	}
	out := []fiber.Map{}
	for _, r := range rows {
		if r["status"] != "pending" && r["status"] != "active" {
			continue
		}
		if r["status"] == "pending" && fmt.Sprint(r["week"]) != weekKey(now) {
			continue
		}
		start, err := time.Parse("2006-01-02", fmt.Sprint(r["week"]))
		if err != nil || now.Before(start) || !now.Before(start.Add(9*24*time.Hour)) {
			continue
		}
		a, _, err := s.ReadProgress(fmt.Sprint(r["owner"]))
		if err != nil {
			return nil, err
		}
		b, _, err := s.ReadProgress(fmt.Sprint(r["peer"]))
		if err != nil {
			return nil, err
		}
		wa, wb := weekState(&a, fmt.Sprint(r["week"])), weekState(&b, fmt.Sprint(r["week"]))
		mine := wa
		if owner == fmt.Sprint(r["peer"]) {
			mine = wb
		}
		joined := r["status"] == "active" && wa.Clears > 0 && wb.Clears > 0
		goals := []fiber.Map{{"id": "clears", "name": "Together on stage", "description": "Clear 6 songs together. Each friend must clear at least one; up to 5 per friend count.", "target": 6, "progress": min(6, min(5, wa.Clears)+min(5, wb.Clears)), "xp": 150, "starlight": 100, "complete": joined && min(5, wa.Clears)+min(5, wb.Clears) >= 6, "claimed": mine.Claimed["clears"]}, {"id": "perfect", "name": "Perfect together", "description": "Earn 1,000 PERFECT judgments together. Each friend must clear at least one song.", "target": 1000, "progress": min(1000, wa.Perfect+wb.Perfect), "xp": 200, "starlight": 150, "complete": joined && wa.Perfect+wb.Perfect >= 1000, "claimed": mine.Claimed["perfect"]}}
		out = append(out, fiber.Map{"id": r["id"], "owner": r["owner"], "peer": r["peer"], "owner_name": r["owner_name"], "peer_name": r["peer_name"], "week": r["week"], "status": r["status"], "ends_at": start.Add(7 * 24 * time.Hour).Format(time.RFC3339), "claim_ends_at": start.Add(9 * 24 * time.Hour).Format(time.RFC3339), "owner_clears": wa.Clears, "peer_clears": wb.Clears, "goals": goals})
	}
	return out, nil
}
func (a *api) getCoop(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	now := time.Now().UTC()
	views, err := coopViews(s, c.Locals("user").(user).ID, now)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"week": weekKey(now), "server_time": now.Format(time.RFC3339), "duets": views})
}
func (a *api) inviteCoop(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	var body struct {
		Peer string `json:"player_id"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(body.Peer, 16) || body.Peer == owner {
		return fiber.ErrBadRequest
	}
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return err
	}
	id := hex.EncodeToString(random)
	now := time.Now().UTC()
	week := weekKey(now)
	rows, err := s.query(`MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User {id:$peer})-[:FOLLOWS]->(u) OPTIONAL MATCH(u)-[b:BLOCKS]-(v) WITH u,v,count(b) AS blocked WHERE blocked=0 AND (coalesce(u.coop_week,'')<>$week OR coalesce(u.coop_id,'')='') AND (coalesce(v.coop_week,'')<>$week OR coalesce(v.coop_id,'')='') CREATE(c:CoopDuet {id:$id,owner:$owner,peer:$peer,week:$week,status:'pending',created_at:$now}) SET u.coop_week=$week,u.coop_id=$id RETURN c.id`, map[string]interface{}{"owner": owner, "peer": body.Peer, "id": id, "week": week, "now": now.UnixMilli()})
	if err != nil {
		return err
	}
	if !rows.Next() {
		return failure(c, 409, "coop_unavailable", "Choose a mutual friend who is available for this week's duet.")
	}
	a.notifyPlayer(body.Peer, "duet", owner)
	return c.JSON(fiber.Map{"id": id})
}
func (a *api) actionCoop(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	id := c.Params("id")
	if !validHex(id, 16) {
		return fiber.ErrBadRequest
	}
	var body struct {
		Action string `json:"action"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	owner := c.Locals("user").(user).ID
	week := weekKey(time.Now())
	params := map[string]interface{}{"id": id, "owner": owner, "week": week}
	var query string
	switch body.Action {
	case "accept":
		query = `MATCH(c:CoopDuet {id:$id,status:'pending',week:$week}),(u:User),(v:User {id:$owner}) WHERE u.id=c.owner AND v.id=c.peer AND u.coop_id=c.id AND (coalesce(v.coop_week,'')<>$week OR coalesce(v.coop_id,'')='') MATCH(u)-[:FOLLOWS]->(v)-[:FOLLOWS]->(u) OPTIONAL MATCH(u)-[b:BLOCKS]-(v) WITH c,v,count(b) AS blocked WHERE blocked=0 SET v.coop_week=$week,v.coop_id=$id,c.status='active' RETURN c.id,c.owner,c.peer`
	case "decline", "cancel":
		params["status"] = map[string]string{"decline": "declined", "cancel": "cancelled"}[body.Action]
		query = `MATCH(c:CoopDuet {id:$id,status:'pending',week:$week}),(u:User) WHERE u.id=c.owner AND (($status='declined' AND c.peer=$owner) OR ($status='cancelled' AND c.owner=$owner)) SET c.status=$status,u.coop_id=CASE WHEN u.coop_id=c.id THEN '' ELSE u.coop_id END RETURN c.id,c.owner,c.peer`
	default:
		return fiber.ErrBadRequest
	}
	rows, err := s.query(query, params)
	if err != nil {
		return err
	}
	if !rows.Next() {
		return failure(c, 409, "coop_changed", "This invitation is no longer available.")
	}
	for index := 1; index <= 2; index++ {
		value, _ := rows.Record().GetByIndex(index)
		if other, ok := value.(string); ok && other != owner {
			a.notifyPlayer(other, "duet", owner)
		}
	}
	return c.JSON(fiber.Map{"ok": true})
}
func (a *api) claimCoop(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	id := c.Params("id")
	var body struct {
		Goal string `json:"goal"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(id, 16) {
		return fiber.ErrBadRequest
	}
	owner := c.Locals("user").(user).ID
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		views, err := coopViews(s, owner, now)
		if err != nil {
			return nil, err
		}
		for _, view := range views {
			if view["id"] != id || view["status"] != "active" {
				continue
			}
			// Progress from the current CAS snapshot replaces this account's copy read
			// in coopViews. A failed concurrent write retries the entire validation.
			week := view["week"].(string)
			own := weekState(p, week)
			var goals []fiber.Map
			encoded, _ := json.Marshal(view["goals"])
			_ = json.Unmarshal(encoded, &goals)
			for _, goal := range goals {
				if goal["id"] != body.Goal {
					continue
				}
				if own.Claimed[body.Goal] {
					return fiber.Map{"already_claimed": true}, nil
				}
				if goal["complete"] != true || own.Clears < 1 {
					return nil, badProgress("Both friends must contribute and finish the goal first.")
				}
				xp := int(adminInt(goal["xp"]))
				star := int(adminInt(goal["starlight"]))
				if xp <= 0 || star <= 0 {
					return nil, fiber.ErrInternalServerError
				}
				own.Claimed[body.Goal] = true
				p.XP += int64(xp)
				p.Starlight += int64(star)
				return fiber.Map{"xp": xp, "starlight": star, "goal": body.Goal}, nil
			}
		}
		return nil, progressError{404, "Weekly duet not found or expired."}
	})
}
