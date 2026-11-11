package main

import (
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
	"testing"
	"time"
)

func authenticatedFixture(t *testing.T, app *fiber.App, name string) (string, string) {
	t.Helper()
	status, data, _ := request(t, app, "POST", "/api/v1/auth/register", creds(name, "password123"), "")
	requireStatus(t, status, 201)
	return data["access_token"].(string), data["user"].(map[string]any)["id"].(string)
}
func TestFriendChallengeInvitationAndAtomicVerifiedScores(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	ta, a := authenticatedFixture(t, app, "challengealice")
	tb, b := authenticatedFixture(t, app, "challengebree")
	tc, _ := authenticatedFixture(t, app, "challengecleo")
	var chart rewardChart
	for _, v := range rewardCharts {
		chart = v
		break
	}
	body := map[string]string{"request_id": strings.Repeat("a", 32), "player_id": b, "song_id": chart.SongID, "difficulty": chart.Difficulty}
	status, _, _ := request(t, app, "POST", "/api/v1/challenges", body, ta)
	requireStatus(t, status, 409)
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	status, data, _ := request(t, app, "POST", "/api/v1/challenges", body, ta)
	requireStatus(t, status, 200)
	id := data["challenge_id"].(string)
	status, again, _ := request(t, app, "POST", "/api/v1/challenges", body, ta)
	requireStatus(t, status, 200)
	if again["challenge_id"] != id {
		t.Fatal("duplicate invitation")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/challenges/"+id, map[string]string{"action": "accept"}, tc)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/challenges/"+id, map[string]string{"action": "accept"}, tb)
	requireStatus(t, status, 200)
	now := time.Now().UnixMilli()
	p, v, err := s.ReadProgress(a)
	if err != nil {
		t.Fatal(err)
	}
	p.rankedBest = &personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: 12345, MaxCombo: 55, RunID: strings.Repeat("b", 32), AchievedAt: now + 1}
	p.challengeStarted = now
	ok, err := s.WriteProgress(a, v, p)
	if err != nil || !ok {
		t.Fatal("atomic challenge write", ok, err)
	}
	status, list, _ := request(t, app, "GET", "/api/v1/challenges", nil, tb)
	requireStatus(t, status, 200)
	rows := list["challenges"].([]any)
	if len(rows) != 1 || rows[0].(map[string]any)["score_a"] != float64(12345) {
		t.Fatal(list)
	}
	// A matching best from BEFORE acceptance must not enter the duel.
	p, v, _ = s.ReadProgress(a)
	p.rankedBest = &personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: 99999, MaxCombo: 99, RunID: strings.Repeat("c", 32), AchievedAt: now + 2}
	p.challengeStarted = 1
	ok, err = s.WriteProgress(a, v, p)
	if err != nil || !ok {
		t.Fatal(ok, err)
	}
	r, e := s.query(`MATCH(c:FriendChallenge {id:$id}) RETURN c.score_a`, map[string]interface{}{"id": id})
	if e != nil || !r.Next() {
		t.Fatal(e)
	}
	score, _ := r.Record().GetByIndex(0)
	if score != int64(12345) {
		t.Fatal("pre-challenge score counted", score)
	}
	status, list, _ = request(t, app, "GET", "/api/v1/challenges", nil, tc)
	requireStatus(t, status, 200)
	if len(list["challenges"].([]any)) != 0 {
		t.Fatal("private challenge leaked")
	}
	_ = fmt.Sprint(a)
}
func TestPlayerReportsCaptureReceivedEvidenceAndRejectThirdParty(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	ta, a := authenticatedFixture(t, app, "reportalice")
	_, b := authenticatedFixture(t, app, "reportbree")
	tc, _ := authenticatedFixture(t, app, "reportcleo")
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	msg, e := s.SendMessage(b, a, strings.Repeat("c", 32), "Offensive fixture", time.Now().UnixMilli())
	if e != nil {
		t.Fatal(e)
	}
	body := map[string]string{"request_id": strings.Repeat("d", 32), "player_id": b, "target_type": "message", "target_id": msg.ID, "reason": "harassment", "details": "Please review"}
	status, _, _ := request(t, app, "POST", "/api/v1/reports", body, tc)
	requireStatus(t, status, 404)
	status, data, _ := request(t, app, "POST", "/api/v1/reports", body, ta)
	requireStatus(t, status, 200)
	status, again, _ := request(t, app, "POST", "/api/v1/reports", body, ta)
	requireStatus(t, status, 200)
	if data["report_id"] != again["report_id"] {
		t.Fatal("duplicate report")
	}
	rows, e := s.query(`MATCH(d:AdminDocument {key:$key}) RETURN d.value`, map[string]interface{}{"key": "reports/" + data["report_id"].(string)})
	if e != nil || !rows.Next() {
		t.Fatal(e)
	}
	v, _ := rows.Record().GetByIndex(0)
	if !strings.Contains(v.(string), "Offensive fixture") {
		t.Fatal("missing evidence")
	}
	body["details"] = "Changed"
	status, _, _ = request(t, app, "POST", "/api/v1/reports", body, ta)
	requireStatus(t, status, 409)
}
func TestSocialEventInboxAndTypingPrivacy(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	ta, a := authenticatedFixture(t, app, "eventalice")
	tb, b := authenticatedFixture(t, app, "eventbree")
	status, initial, _ := request(t, app, "GET", "/api/v1/social/events", nil, tb)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/social/conversations/"+b+"/typing", map[string]any{}, ta)
	requireStatus(t, status, 403)
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	status, _, _ = request(t, app, "POST", "/api/v1/social/conversations/"+b+"/typing", map[string]any{}, ta)
	requireStatus(t, status, 200)
	status, events, _ := request(t, app, "GET", "/api/v1/social/events?cursor="+initial["cursor"].(string), nil, tb)
	requireStatus(t, status, 200)
	values := events["events"].([]any)
	if len(values) != 1 || values[0].(map[string]any)["kind"] != "typing" || values[0].(map[string]any)["peer_id"] != a {
		t.Fatal(events)
	}
}
