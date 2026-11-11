package main

import (
	"encoding/json"
	"errors"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/gofiber/fiber/v3"
)

const presenceLifetime = 90 * time.Second

type socialPlayer struct {
	ID         string `json:"id"`
	Username   string `json:"username"`
	Avatar     any    `json:"avatar"`
	Following  bool   `json:"following"`
	FollowsYou bool   `json:"follows_you"`
	Friend     bool   `json:"friend"`
	Online     bool   `json:"online"`
	Blocked    bool   `json:"blocked_by_me"`
	CanChat    bool   `json:"can_chat"`
	Activity   string `json:"activity"`
	LastActive int64  `json:"-"`
	LastChat   int64  `json:"-"`
}
type socialCounts struct {
	Followers int64 `json:"followers"`
	Following int64 `json:"following"`
	Friends   int64 `json:"friends"`
}
type directMessage struct {
	ID     string `json:"id"`
	Sender string `json:"sender_id"`
	Text   string `json:"text"`
	Seq    int64  `json:"seq"`
	At     int64  `json:"sent_at"`
}
type conversationView struct {
	Peer     socialPlayer `json:"peer"`
	LastText string       `json:"last_text"`
	LastAt   int64        `json:"last_at"`
	Unread   int64        `json:"unread"`
	Seq      int64        `json:"seq"`
}
type socialStore interface {
	SocialPlayers(string, string, string, string, string, bool, int) ([]socialPlayer, error)
	SocialCounts(string) (socialCounts, error)
	FollowPlayer(string, string, bool) error
	BlockPlayer(string, string, bool) error
	SetPresence(string, string, bool, string, int64) error
	Conversations(string) ([]conversationView, error)
	Messages(string, string, int64, int64) ([]directMessage, bool, error)
	SendMessage(string, string, string, string, int64) (directMessage, error)
	ReadMessages(string, string, int64) error
}

var errSocialDenied = errors.New("social action unavailable")
var errMessageConflict = errors.New("message ID already used")

func conversationKey(one, two string) string {
	if one > two {
		one, two = two, one
	}
	return one + "_" + two
}
func (s *graphStore) SocialCounts(owner string) (socialCounts, error) {
	// Separate adjacency counts avoid a followers × following Cartesian product.
	counts := [3]int64{}
	for i, pattern := range []string{`MATCH(v:User)-[:FOLLOWS]->(u:User {id:$owner})`, `MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User)`, `MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User)-[:FOLLOWS]->(u)`} {
		rows, err := s.query(pattern+` RETURN count(DISTINCT v)`, map[string]interface{}{"owner": owner})
		if err != nil {
			return socialCounts{}, err
		}
		if !rows.Next() {
			return socialCounts{}, errNotFound
		}
		value, _ := rows.Record().GetByIndex(0)
		counts[i] = value.(int64)
	}
	return socialCounts{counts[0], counts[1], counts[2]}, nil
}
func (s *graphStore) SocialPlayers(owner, kind, search, cursor, peer string, onlineOnly bool, limit int) ([]socialPlayer, error) {
	filter := map[string]string{"friends": "outgoing>0 AND incoming>0", "following": "outgoing>0", "followers": "incoming>0", "search": "v.username_key STARTS WITH $search", "blocked": "blocked>0", "peer": "v.id=$peer"}[kind]
	if filter == "" {
		return nil, errSocialDenied
	}
	hideBlocked := " AND blocked=0 AND hidden=0"
	if kind == "peer" || kind == "blocked" {
		hideBlocked = ""
	}
	onlineFilter := ""
	if onlineOnly {
		onlineFilter = " WHERE until>$now AND outgoing>0 AND incoming>0 AND blocked=0 AND hidden=0 "
	}
	ordering := "v.username_key"
	if onlineOnly {
		ordering = "chat_at DESC,seen DESC,v.username_key"
	}
	base := map[string]string{
		"friends":   `MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User)-[:FOLLOWS]->(u)`,
		"following": `MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User)`,
		"followers": `MATCH(v:User)-[:FOLLOWS]->(u:User {id:$owner})`,
		"blocked":   `MATCH(u:User {id:$owner})-[:BLOCKS]->(v:User)`,
		"peer":      `MATCH(u:User {id:$owner}),(v:User {id:$peer})`,
		"search":    `MATCH(u:User {id:$owner}),(v:User) WHERE v.username_key STARTS WITH $search WITH u,v`,
	}[kind]
	query := base + ` WHERE u.id<>v.id AND v.username_key>$cursor
 OPTIONAL MATCH(u)-[f:FOLLOWS]->(v) OPTIONAL MATCH(v)-[r:FOLLOWS]->(u)
 OPTIONAL MATCH(u)-[b:BLOCKS]->(v) OPTIONAL MATCH(v)-[bb:BLOCKS]->(u)
 WITH u,v,count(DISTINCT f) AS outgoing,count(DISTINCT r) AS incoming,count(DISTINCT b) AS blocked,count(DISTINCT bb) AS hidden
 WHERE (` + filter + `)` + hideBlocked + ` AND v.username_key>$cursor
 OPTIONAL MATCH(v)-[:HAS_PRESENCE]->(p:Presence)
 WITH u,v,outgoing,incoming,blocked,hidden,max(coalesce(p.until,0)) AS until,max(coalesce(p.seen,0)) AS seen
 OPTIONAL MATCH(c:Conversation) WHERE c.key=CASE WHEN u.id<v.id THEN u.id+'_'+v.id ELSE v.id+'_'+u.id END
 WITH v,outgoing,incoming,blocked,hidden,until,seen,coalesce(c.last_at,0) AS chat_at` + onlineFilter + `
 RETURN v.id,v.username,coalesce(v.profile_media,''),outgoing,incoming,blocked,hidden,until,seen,chat_at
 ORDER BY ` + ordering + ` LIMIT $limit`
	rows, err := s.query(query, map[string]interface{}{"owner": owner, "search": search, "cursor": cursor, "peer": peer, "now": time.Now().UnixMilli(), "limit": limit})
	if err != nil {
		return nil, err
	}
	out := []socialPlayer{}
	for rows.Next() {
		r := rows.Record()
		v := make([]any, 10)
		for i := range v {
			v[i], _ = r.GetByIndex(i)
		}
		player := socialPlayer{ID: v[0].(string), Username: v[1].(string), Following: v[3].(int64) > 0, FollowsYou: v[4].(int64) > 0, Blocked: v[5].(int64) > 0, LastActive: v[8].(int64), LastChat: v[9].(int64)}
		player.Friend = player.Following && player.FollowsYou && !player.Blocked && v[6].(int64) == 0
		player.CanChat = player.Friend
		player.Online = player.Friend && v[7].(int64) > time.Now().UnixMilli()
		if raw, ok := v[2].(string); ok && raw != "" {
			var media profileMedia
			if json.Unmarshal([]byte(raw), &media) == nil && media.Avatar != "" {
				player.Avatar = mediaView(player.ID, media)["avatar"]
			}
		}
		if player.Online {
			player.Activity = "online"
		}
		out = append(out, player)
	}
	return out, nil
}
func (s *graphStore) FollowPlayer(owner, peer string, follow bool) error {
	if !follow {
		_, err := s.query(`MATCH(u:User {id:$owner})-[r:FOLLOWS]->(v:User {id:$peer}) DELETE r`, map[string]interface{}{"owner": owner, "peer": peer})
		return err
	}
	rows, err := s.query(`MATCH(u:User {id:$owner}),(v:User {id:$peer}) WHERE u<>v
 OPTIONAL MATCH(u)-[b:BLOCKS]-(v) WITH u,v,count(b) AS blocked WHERE blocked=0
 MERGE(u)-[r:FOLLOWS]->(v) ON CREATE SET r.created_at=$now RETURN v.id`, map[string]interface{}{"owner": owner, "peer": peer, "now": time.Now().UnixMilli()})
	if err != nil {
		return err
	}
	if !rows.Next() {
		return errSocialDenied
	}
	return nil
}
func (s *graphStore) BlockPlayer(owner, peer string, block bool) error {
	if !block {
		_, err := s.query(`MATCH(u:User {id:$owner})-[b:BLOCKS]->(v:User {id:$peer}) DELETE b`, map[string]interface{}{"owner": owner, "peer": peer})
		return err
	}
	rows, err := s.query(`MATCH(u:User {id:$owner}),(v:User {id:$peer}) WHERE u<>v MERGE(u)-[:BLOCKS]->(v)
 WITH u,v OPTIONAL MATCH(u)-[f:FOLLOWS]-(v) DELETE f RETURN v.id`, map[string]interface{}{"owner": owner, "peer": peer})
	if err != nil {
		return err
	}
	if !rows.Next() {
		return errSocialDenied
	}
	return nil
}
func (s *graphStore) SetPresence(owner, device string, online bool, activity string, now int64) error {
	if _, err := s.query(`MATCH(u:User {id:$owner})-[:HAS_PRESENCE]->(p:Presence) WHERE p.until<$old DETACH DELETE p`, map[string]interface{}{"owner": owner, "old": now - int64((5 * time.Minute).Milliseconds())}); err != nil {
		return err
	}
	until := int64(0)
	if online {
		until = now + presenceLifetime.Milliseconds()
	}
	_, err := s.query(`MATCH(u:User {id:$owner}) MERGE(u)-[:HAS_PRESENCE]->(p:Presence {key:$key}) SET p.until=$until,p.seen=$now,p.activity=$activity`, map[string]interface{}{"owner": owner, "key": owner + "_" + device, "until": until, "now": now, "activity": activity})
	return err
}
func (s *graphStore) Conversations(owner string) ([]conversationView, error) {
	rows, err := s.query(`MATCH(c:Conversation) WHERE c.a=$owner OR c.b=$owner
 OPTIONAL MATCH(c)-[:HAS_MESSAGE]->(m:DirectMessage) WHERE m.sender<>$owner AND m.seq>CASE WHEN c.a=$owner THEN coalesce(c.read_a,0) ELSE coalesce(c.read_b,0) END
 RETURN CASE WHEN c.a=$owner THEN c.b ELSE c.a END,c.last_text,c.last_at,count(m),c.seq ORDER BY c.last_at DESC LIMIT 50`, map[string]interface{}{"owner": owner})
	if err != nil {
		return nil, err
	}
	out := []conversationView{}
	for rows.Next() {
		r := rows.Record()
		v := make([]any, 5)
		for i := range v {
			v[i], _ = r.GetByIndex(i)
		}
		peer, err := s.SocialPlayers(owner, "peer", "", "", v[0].(string), false, 1)
		if err != nil {
			return nil, err
		}
		if len(peer) == 0 {
			continue
		}
		text := []rune(v[1].(string))
		if len(text) > 100 {
			text = text[:100]
		}
		out = append(out, conversationView{peer[0], string(text), v[2].(int64), v[3].(int64), v[4].(int64)})
	}
	return out, nil
}
func (s *graphStore) Messages(owner, peer string, after, before int64) ([]directMessage, bool, error) {
	order := "DESC"
	predicate := ""
	if after > 0 {
		order = "ASC"
		predicate = " AND m.seq>$after"
	}
	if before > 0 {
		predicate = " AND m.seq<$before"
	}
	rows, err := s.query(`MATCH(c:Conversation {key:$key})-[:HAS_MESSAGE]->(m:DirectMessage) WHERE (c.a=$owner OR c.b=$owner)`+predicate+` RETURN m.key,m.sender,m.body,m.seq,m.at ORDER BY m.seq `+order+` LIMIT 51`, map[string]interface{}{"key": conversationKey(owner, peer), "owner": owner, "after": after, "before": before})
	if err != nil {
		return nil, false, err
	}
	out := []directMessage{}
	for rows.Next() {
		r := rows.Record()
		v := make([]any, 5)
		for i := range v {
			v[i], _ = r.GetByIndex(i)
		}
		out = append(out, directMessage{v[0].(string), v[1].(string), v[2].(string), v[3].(int64), v[4].(int64)})
	}
	more := len(out) > 50
	if more {
		out = out[:50]
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Seq < out[j].Seq })
	return out, more, nil
}
func (s *graphStore) SendMessage(owner, peer, requestID, text string, now int64) (directMessage, error) {
	key := conversationKey(owner, peer)
	messageKey := key + "_" + owner + "_" + requestID
	// Recover an already committed send even when friendship changed afterward.
	existing, err := s.query(`MATCH(m:DirectMessage {key:$id}) RETURN m.sender,m.body,m.seq,m.at`, map[string]interface{}{"id": messageKey})
	if err != nil {
		return directMessage{}, err
	}
	if existing.Next() {
		r := existing.Record()
		sender, _ := r.GetByIndex(0)
		body, _ := r.GetByIndex(1)
		seq, _ := r.GetByIndex(2)
		at, _ := r.GetByIndex(3)
		if body != text || sender != owner {
			return directMessage{}, errMessageConflict
		}
		return directMessage{messageKey, owner, text, seq.(int64), at.(int64)}, nil
	}
	a, b := owner, peer
	if a > b {
		a, b = b, a
	}
	rows, err := s.query(`MATCH(u:User {id:$owner})-[:FOLLOWS]->(v:User {id:$peer})-[:FOLLOWS]->(u)
 OPTIONAL MATCH(u)-[block:BLOCKS]-(v) WITH u,v,count(block) AS blocked WHERE blocked=0
 MERGE(c:Conversation {key:$key}) ON CREATE SET c.a=$a,c.b=$b,c.seq=0,c.read_a=0,c.read_b=0
 MERGE(c)-[:HAS_MESSAGE]->(m:DirectMessage {key:$id})
 ON CREATE SET m.sender=$owner,m.body=$text,m.seq=c.seq+1,m.at=$now,c.seq=c.seq+1,c.last_text=$text,c.last_at=$now
 RETURN m.sender,m.body,m.seq,m.at`, map[string]interface{}{"owner": owner, "peer": peer, "key": key, "a": a, "b": b, "id": messageKey, "text": text, "now": now})
	if err != nil {
		return directMessage{}, err
	}
	if !rows.Next() {
		return directMessage{}, errSocialDenied
	}
	r := rows.Record()
	sender, _ := r.GetByIndex(0)
	body, _ := r.GetByIndex(1)
	seq, _ := r.GetByIndex(2)
	at, _ := r.GetByIndex(3)
	if sender != owner || body != text {
		return directMessage{}, errMessageConflict
	}
	return directMessage{messageKey, owner, text, seq.(int64), at.(int64)}, nil
}
func (s *graphStore) ReadMessages(owner, peer string, seq int64) error {
	_, err := s.query(`MATCH(c:Conversation {key:$key}) WHERE (c.a=$owner OR c.b=$owner) AND $seq<=c.seq
 SET c.read_a=CASE WHEN c.a=$owner AND c.read_a<$seq THEN $seq ELSE c.read_a END,c.read_b=CASE WHEN c.b=$owner AND c.read_b<$seq THEN $seq ELSE c.read_b END`, map[string]interface{}{"key": conversationKey(owner, peer), "owner": owner, "seq": seq})
	return err
}
func (a *api) social(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	counts, err := s.SocialCounts(owner)
	if err != nil {
		return err
	}
	online, err := s.SocialPlayers(owner, "friends", "", "", "", true, 5)
	if err != nil {
		return err
	}
	threads, err := s.Conversations(owner)
	if err != nil {
		return err
	}
	unread := int64(0)
	for _, thread := range threads {
		unread += thread.Unread
	}
	return c.JSON(fiber.Map{"social": fiber.Map{"counts": counts, "online_friends": online, "conversations": threads, "unread": unread}})
}
func (a *api) socialPlayers(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	kind := c.Query("kind", "friends")
	q := strings.ToLower(strings.TrimSpace(c.Query("q")))
	cursor := strings.ToLower(c.Query("cursor"))
	if kind != "friends" && kind != "following" && kind != "followers" && kind != "search" && kind != "blocked" {
		return fiber.ErrBadRequest
	}
	if kind == "search" && !usernamePattern.MatchString(q) {
		return failure(c, 400, "invalid_search", "Search at least three username characters.")
	}
	if cursor != "" && !usernamePattern.MatchString(cursor) {
		return fiber.ErrBadRequest
	}
	players, err := s.SocialPlayers(c.Locals("user").(user).ID, kind, q, cursor, "", false, 51)
	if err != nil {
		return err
	}
	next := ""
	if len(players) > 50 {
		players = players[:50]
		next = strings.ToLower(players[49].Username)
	}
	return c.JSON(fiber.Map{"players": players, "next_cursor": next})
}
func (a *api) socialAction(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	peer := c.Params("id")
	if !validHex(peer, 16) || owner == peer {
		return failure(c, 400, "invalid_player", "Choose another player.")
	}
	if _, err := a.store.ByID(peer); errors.Is(err, errNotFound) {
		return fiber.ErrNotFound
	} else if err != nil {
		return err
	}
	var body struct {
		Enabled bool `json:"enabled"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	var err error
	if c.Params("action") == "follow" {
		err = s.FollowPlayer(owner, peer, body.Enabled)
	} else if c.Params("action") == "block" {
		err = s.BlockPlayer(owner, peer, body.Enabled)
	} else {
		return fiber.ErrNotFound
	}
	if errors.Is(err, errSocialDenied) {
		return failure(c, 403, "social_unavailable", "This player is unavailable.")
	}
	if err != nil {
		return err
	}
	players, err := s.SocialPlayers(owner, "peer", "", "", peer, false, 1)
	if err != nil {
		return err
	}
	a.notifyPlayer(peer, "relationship", owner)
	a.notifyPlayer(owner, "sync", peer)
	return c.JSON(fiber.Map{"player": players[0]})
}
func (a *api) presence(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	var body struct {
		Device   string `json:"device_id"`
		Online   bool   `json:"online"`
		Activity string `json:"activity"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(body.Device, 16) || (body.Activity != "lobby" && body.Activity != "playing" && body.Activity != "") {
		return fiber.ErrBadRequest
	}
	if err := s.SetPresence(c.Locals("user").(user).ID, body.Device, body.Online, body.Activity, time.Now().UnixMilli()); err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true, "expires_in": 90})
}
func (a *api) conversation(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	peer := c.Params("id")
	if !validHex(peer, 16) || owner == peer {
		return fiber.ErrBadRequest
	}
	players, err := s.SocialPlayers(owner, "peer", "", "", peer, false, 1)
	if err != nil {
		return err
	}
	if len(players) == 0 {
		return fiber.ErrNotFound
	}
	after, e1 := strconv.ParseInt(c.Query("after", "0"), 10, 64)
	before, e2 := strconv.ParseInt(c.Query("before", "0"), 10, 64)
	if e1 != nil || e2 != nil || after < 0 || before < 0 || after > 0 && before > 0 {
		return fiber.ErrBadRequest
	}
	messages, more, err := s.Messages(owner, peer, after, before)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"peer": players[0], "messages": messages, "has_more": more})
}
func (a *api) sendMessage(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	peer := c.Params("id")
	var body struct {
		ID   string `json:"request_id"`
		Text string `json:"text"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	body.Text = strings.TrimSpace(body.Text)
	if !validHex(peer, 16) || peer == owner || !validHex(body.ID, 16) || !utf8.ValidString(body.Text) || len(body.Text) > 2000 || utf8.RuneCountInString(body.Text) > 500 || body.Text == "" {
		return failure(c, 400, "invalid_message", "Send a message of 1–500 characters.")
	}
	for _, r := range body.Text {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return fiber.ErrBadRequest
		}
	}
	message, err := s.SendMessage(owner, peer, body.ID, body.Text, time.Now().UnixMilli())
	if errors.Is(err, errSocialDenied) {
		return failure(c, 403, "friends_only", "Follow each other to chat. Messaging is unavailable if either player has blocked the other.")
	}
	if errors.Is(err, errMessageConflict) {
		return failure(c, 409, "message_conflict", "This message ID belongs to different text.")
	}
	if err != nil {
		return err
	}
	a.notifyPlayer(peer, "message", owner)
	a.notifyPlayer(owner, "sync", peer)
	return c.JSON(fiber.Map{"message": message})
}
func (a *api) readMessages(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	peer := c.Params("id")
	var body struct {
		Seq int64 `json:"seq"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(peer, 16) || peer == owner || body.Seq < 0 {
		return fiber.ErrBadRequest
	}
	if err := s.ReadMessages(owner, peer, body.Seq); err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true})
}
