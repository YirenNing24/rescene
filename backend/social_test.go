package main

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func socialAccounts(t *testing.T) (*graphStore, string, string, string) {
	t.Helper()
	s := testStore(t)
	ids := []string{strings.Repeat("1", 32), strings.Repeat("2", 32), strings.Repeat("3", 32)}
	for i, id := range ids {
		_, err := s.Create(user{ID: id, Username: []string{"SceneAlice", "SceneBree", "SceneCleo"}[i], CreatedAt: time.Now().UTC().Format(time.RFC3339), PasswordHash: "fixture"}, strings.ToLower([]string{"SceneAlice", "SceneBree", "SceneCleo"}[i]))
		if err != nil {
			t.Fatal(err)
		}
	}
	return s, ids[0], ids[1], ids[2]
}
func TestSocialGraphCountsPresenceAndTopFive(t *testing.T) {
	s, a, b, _ := socialAccounts(t)
	if err := s.FollowPlayer(a, b, true); err != nil {
		t.Fatal(err)
	}
	if err := s.FollowPlayer(a, b, true); err != nil {
		t.Fatal(err)
	}
	counts, err := s.SocialCounts(a)
	if err != nil || counts.Following != 1 || counts.Friends != 0 {
		t.Fatal("bad following", counts, err)
	}
	if _, err = s.SendMessage(a, b, strings.Repeat("a", 32), "Hello", time.Now().UnixMilli()); err != errSocialDenied {
		t.Fatal("one-way follow permitted private chat", err)
	}
	if err = s.FollowPlayer(b, a, true); err != nil {
		t.Fatal(err)
	}
	if err = s.SetPresence(b, strings.Repeat("a", 32), true, "lobby", time.Now().UnixMilli()); err != nil {
		t.Fatal(err)
	}
	peers, err := s.SocialPlayers(a, "friends", "", "", "", true, 5)
	if err != nil || len(peers) != 1 || !peers[0].Online {
		t.Fatal("online friend absent", peers, err)
	}
	if err = s.SetPresence(b, strings.Repeat("a", 32), true, "lobby", time.Now().Add(-91*time.Second).UnixMilli()); err != nil {
		t.Fatal(err)
	}
	peers, err = s.SocialPlayers(a, "friends", "", "", "", true, 5)
	if err != nil || len(peers) != 0 {
		t.Fatal("stale friend still online", peers, err)
	}
	// Independent devices do not mark each other offline.
	_ = s.SetPresence(b, strings.Repeat("b", 32), true, "lobby", time.Now().UnixMilli())
	_ = s.SetPresence(b, strings.Repeat("a", 32), false, "", time.Now().UnixMilli())
	peers, err = s.SocialPlayers(a, "friends", "", "", "", true, 5)
	if err != nil || len(peers) != 1 {
		t.Fatal("one device hid another", peers, err)
	}
	for i := 4; i < 11; i++ {
		id := fmt.Sprintf("%032x", i)
		_, err = s.Create(user{ID: id, Username: fmt.Sprintf("Friend%02d", i), CreatedAt: "fixture", PasswordHash: "fixture"}, fmt.Sprintf("friend%02d", i))
		if err != nil {
			t.Fatal(err)
		}
		_ = s.FollowPlayer(a, id, true)
		_ = s.FollowPlayer(id, a, true)
		_ = s.SetPresence(id, strings.Repeat("a", 32), true, "lobby", time.Now().UnixMilli())
	}
	_, err = s.SendMessage(a, b, strings.Repeat("a", 32), "Most recent chat", time.Now().UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	peers, err = s.SocialPlayers(a, "friends", "", "", "", true, 5)
	if err != nil || len(peers) != 5 || peers[0].ID != b {
		t.Fatal("top five should prioritize recent conversations", peers, err)
	}
	counts, err = s.SocialCounts(a)
	if err != nil || counts.Friends != 8 || counts.Following != 8 || counts.Followers != 8 {
		t.Fatal("counts differ", counts, err)
	}
	search, err := s.SocialPlayers(a, "search", "scen", "", "", false, 51)
	if err != nil || len(search) != 2 {
		t.Fatal("username search", search, err)
	}
}
func TestPrivateMessageRetryReadCursorAndBlocks(t *testing.T) {
	s, a, b, c := socialAccounts(t)
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	now := time.Now().UnixMilli()
	id := strings.Repeat("a", 32)
	first, err := s.SendMessage(a, b, id, "Hello 🎵", now)
	if err != nil || first.Seq != 1 {
		t.Fatal("send failed", first, err)
	}
	same, err := s.SendMessage(a, b, id, "Hello 🎵", now+100)
	if err != nil || same != first {
		t.Fatal("retry duplicated message", same, err)
	}
	if _, err = s.SendMessage(a, b, id, "Changed text", now); err != errMessageConflict {
		t.Fatal("changed message reused ID", err)
	}
	inbox, err := s.Conversations(b)
	if err != nil || len(inbox) != 1 || inbox[0].Unread != 1 {
		t.Fatal("unread missing", inbox, err)
	}
	inbox, err = s.Conversations(a)
	if err != nil || inbox[0].Unread != 0 {
		t.Fatal("own send counted unread", inbox, err)
	}
	messages, _, err := s.Messages(c, b, 0, 0)
	if err != nil || len(messages) != 0 {
		t.Fatal("third party read private messages", messages, err)
	}
	_ = s.ReadMessages(b, a, first.Seq)
	_ = s.ReadMessages(b, a, 0)
	inbox, err = s.Conversations(b)
	if err != nil || inbox[0].Unread != 0 {
		t.Fatal("read cursor went backward", inbox, err)
	}
	if err = s.BlockPlayer(b, a, true); err != nil {
		t.Fatal(err)
	}
	if err = s.FollowPlayer(a, b, true); err != errSocialDenied {
		t.Fatal("blocked follow accepted", err)
	}
	if _, err = s.SendMessage(a, b, strings.Repeat("b", 32), "Blocked message", now); err != errSocialDenied {
		t.Fatal("blocked chat accepted", err)
	}
	same, err = s.SendMessage(a, b, id, "Hello 🎵", now)
	if err != nil || same != first {
		t.Fatal("lost send did not reconcile after block", err)
	}
	counts, _ := s.SocialCounts(a)
	if counts.Friends != 0 || counts.Following != 0 || counts.Followers != 0 {
		t.Fatal("block did not remove follow edges", counts)
	}
	blocked, err := s.SocialPlayers(b, "blocked", "", "", "", false, 51)
	if err != nil || len(blocked) != 1 || !blocked[0].Blocked {
		t.Fatal("block list absent", blocked, err)
	}
	_ = s.BlockPlayer(b, a, false)
	peers, err := s.SocialPlayers(a, "peer", "", "", b, false, 1)
	if err != nil || peers[0].Friend {
		t.Fatal("unblock silently restored friendship", peers, err)
	}
}
func TestMessagePaginationAndConcurrentRetry(t *testing.T) {
	s, a, b, _ := socialAccounts(t)
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	id := strings.Repeat("f", 32)
	var wg sync.WaitGroup
	for index := range 8 {
		writer := s
		if index%2 == 1 {
			writer = other
		}
		wg.Go(func() {
			if _, err := writer.SendMessage(a, b, id, "Exactly once", time.Now().UnixMilli()); err != nil {
				t.Error(err)
			}
		})
	}
	wg.Wait()
	for i := 1; i < 75; i++ {
		if _, err := s.SendMessage(a, b, fmt.Sprintf("%032x", i), "Page", time.Now().UnixMilli()); err != nil {
			t.Fatal(err)
		}
	}
	messages, more, err := s.Messages(b, a, 0, 0)
	if err != nil || !more || len(messages) != 50 || messages[0].Seq != 26 || messages[49].Seq != 75 {
		t.Fatal("latest page wrong", len(messages), more, err)
	}
	older, more, err := s.Messages(b, a, 0, 26)
	if err != nil || more || len(older) != 25 || older[0].Seq != 1 {
		t.Fatal("history page wrong", len(older), more, err)
	}
	newer, more, err := s.Messages(b, a, 1, 0)
	if err != nil || !more || len(newer) != 50 || newer[0].Seq != 2 || newer[49].Seq != 51 {
		t.Fatal("incremental page skipped messages", len(newer), more, err)
	}
	_ = s.ReadMessages(b, a, 99999)
	inbox, err := s.Conversations(b)
	if err != nil || inbox[0].Unread != 75 {
		t.Fatal("future cursor swallowed unread", inbox, err)
	}
}
func TestSocialAPIValidationAndParticipantIsolation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	a, aid := photoLogin(t, app, "SocialAlice")
	b, bid := photoLogin(t, app, "SocialBree")
	c, _ := photoLogin(t, app, "SocialCleo")
	status, _, _ := request(t, app, "GET", "/api/v1/social", nil, "")
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "GET", "/api/v1/social/players?kind=search&q=so", nil, a)
	requireStatus(t, status, 400)
	status, body, _ := request(t, app, "GET", "/api/v1/social/players?kind=search&q=social", nil, a)
	requireStatus(t, status, 200)
	if len(body["players"].([]any)) != 2 {
		t.Fatal("search did not exclude self")
	}
	for _, pair := range [][3]string{{a, bid, "follow"}, {b, aid, "follow"}} {
		status, _, _ = request(t, app, "POST", "/api/v1/social/players/"+pair[1]+"/"+pair[2], map[string]any{"enabled": true}, pair[0])
		requireStatus(t, status, 200)
	}
	status, body, _ = request(t, app, "POST", "/api/v1/social/conversations/"+bid+"/messages", map[string]any{"request_id": strings.Repeat("c", 32), "text": "Hello there"}, a)
	requireStatus(t, status, 200)
	status, body, _ = request(t, app, "GET", "/api/v1/social/conversations/"+aid, nil, c)
	requireStatus(t, status, 200)
	if len(body["messages"].([]any)) != 0 {
		t.Fatal("conversation leaked to another account")
	}
	status, body, _ = request(t, app, "GET", "/api/v1/social", nil, b)
	requireStatus(t, status, 200)
	if body["social"].(map[string]any)["unread"].(float64) != 1 {
		t.Fatal("summary unread wrong")
	}
	for _, text := range []string{"", strings.Repeat("a", 501), "bad\x01message"} {
		status, _, _ = request(t, app, "POST", "/api/v1/social/conversations/"+bid+"/messages", map[string]any{"request_id": strings.Repeat("b", 32), "text": text}, a)
		requireStatus(t, status, 400)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/social/players/"+aid+"/follow", map[string]any{"enabled": true}, a)
	requireStatus(t, status, 400)
}
