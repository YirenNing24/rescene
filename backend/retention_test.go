package main

import (
	"sync"
	"testing"
	"time"
)

func TestMasteryVerifiedClearAndClaimOnce(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "masteryalice")
	other, _ := progressAccount(t, app, "masterybree")
	chart := firstChart()
	status, _, _ := request(t, app, "POST", "/api/v1/mastery/"+chart.SongID+"/easy/claim", map[string]any{}, token)
	requireStatus(t, status, 409)
	run := startTestRun(t, app, token, chart)
	ageRun(t, s, id, chart)
	bad := perfectResult(chart, run)
	bad.Score = 1
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", bad, token)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart, run), token)
	requireStatus(t, status, 200)
	status, data, _ := request(t, app, "GET", "/api/v1/mastery/"+chart.SongID, nil, token)
	requireStatus(t, status, 200)
	view := data["mastery"].(map[string]any)
	if view["completed"].(float64) != 3 {
		t.Fatalf("wrong mastery: %v", view)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/mastery/"+chart.SongID+"/easy/claim", map[string]any{}, other)
	requireStatus(t, status, 409)
	before, _, _ := s.ReadProgress(id)
	var wg sync.WaitGroup
	awards := make(chan bool, 6)
	for i := 0; i < 6; i++ {
		wg.Go(func() {
			code, out, _ := request(t, app, "POST", "/api/v1/mastery/"+chart.SongID+"/easy/claim", map[string]any{}, token)
			requireStatus(t, code, 200)
			awards <- out["reward"].(map[string]any)["already_claimed"] != true
		})
	}
	wg.Wait()
	close(awards)
	n := 0
	for x := range awards {
		if x {
			n++
		}
	}
	after, _, _ := s.ReadProgress(id)
	if n != 1 || after.XP-before.XP != 40 || after.Starlight-before.Starlight != 20 {
		t.Fatal("mastery double claim or wrong reward")
	}
}
func TestWeeklyDuetRequiresBothFriendsAndClaimsOnce(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	ta, a := progressAccount(t, app, "duetalice")
	tb, b := progressAccount(t, app, "duetbree")
	tc, _ := progressAccount(t, app, "duetcleo")
	status, _, _ := request(t, app, "POST", "/api/v1/coop/invite", map[string]string{"player_id": b}, ta)
	requireStatus(t, status, 409)
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	status, data, _ := request(t, app, "POST", "/api/v1/coop/invite", map[string]string{"player_id": b}, ta)
	requireStatus(t, status, 200)
	id := data["id"].(string)
	status, _, _ = request(t, app, "POST", "/api/v1/coop/"+id+"/action", map[string]string{"action": "accept"}, tc)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/coop/"+id+"/action", map[string]string{"action": "accept"}, tb)
	requireStatus(t, status, 200)
	week := weekKey(time.Now())
	editProgress(t, s, a, func(p *progression) { w := weekState(p, week); w.Clears = 6; w.Perfect = 1000 })
	path := "/api/v1/coop/" + id + "/claim"
	status, _, _ = request(t, app, "POST", path, map[string]string{"goal": "clears"}, ta)
	requireStatus(t, status, 409)
	editProgress(t, s, b, func(p *progression) { w := weekState(p, week); w.Clears = 1; w.Perfect = 10 })
	status, data, _ = request(t, app, "GET", "/api/v1/coop", nil, ta)
	requireStatus(t, status, 200)
	if len(data["duets"].([]any)) != 1 {
		t.Fatal(data)
	}
	status, _, _ = request(t, app, "POST", path, map[string]string{"goal": "clears"}, tc)
	requireStatus(t, status, 404)
	status, _, _ = request(t, app, "POST", path, map[string]string{"goal": "clears"}, ta)
	requireStatus(t, status, 200)
	status, data, _ = request(t, app, "POST", path, map[string]string{"goal": "clears"}, ta)
	requireStatus(t, status, 200)
	if data["reward"].(map[string]any)["already_claimed"] != true {
		t.Fatal("claim repeated")
	}
	status, _, _ = request(t, app, "POST", path, map[string]string{"goal": "clears"}, tb)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/coop/invite", map[string]string{"player_id": b}, ta)
	requireStatus(t, status, 409)
}
func TestRivalUsesVerifiedCurrentFriendScore(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	_, a := progressAccount(t, app, "rivalalice")
	_, b := progressAccount(t, app, "rivalbree")
	_, c := progressAccount(t, app, "rivalcleo")
	chart := firstChart()
	for _, v := range []struct {
		id    string
		score int
	}{{a, 100000}, {b, 200000}, {c, 150000}} {
		p, n, e := s.ReadProgress(v.id)
		if e != nil {
			t.Fatal(e)
		}
		p.rankedBest = &personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: v.score, MaxCombo: 1, RunID: "00000000000000000000000000000000", AchievedAt: time.Now().UnixMilli()}
		if ok, e := s.WriteProgress(v.id, n, p); e != nil || !ok {
			t.Fatal(e)
		}
	}
	target, err := s.rivalTarget(a, chart)
	if err != nil || target == nil || target.Kind != "personal" || target.Score != 100000 {
		t.Fatalf("personal target: %+v %v", target, err)
	}
	_ = s.FollowPlayer(a, b, true)
	_ = s.FollowPlayer(b, a, true)
	target, err = s.rivalTarget(a, chart)
	if err != nil || target == nil || target.Kind != "friend" || target.UserID != b {
		t.Fatalf("friend target: %+v %v", target, err)
	}
	_ = s.BlockPlayer(a, b, true)
	target, err = s.rivalTarget(a, chart)
	if err != nil || target == nil || target.Kind != "personal" {
		t.Fatalf("blocked friend leaked: %+v %v", target, err)
	}
}
func TestWeeklySpotlightRotationAndClaims(t *testing.T) {
	now := time.Now().UTC()
	start := weekStart(now)
	theme := weeklyTheme(start)
	id := weeklyEventID(start)
	if len(theme.Songs) == 0 || weeklyTheme(start.Add(7*24*time.Hour)).Name == theme.Name {
		t.Fatal("weekly theme did not rotate")
	}
	var p progression
	song := theme.Songs[0]
	tickets := eventTickets(song, start.Add(time.Hour))
	run := runTicket{SongID: song, StartedAt: start.Add(time.Hour).UnixMilli(), Events: tickets}
	for i := 0; i < 3; i++ {
		advanceEvents(&p, run, runResult{Counts: map[string]int{"PERFECT": 100, "MISS": 0}}, start.Add(2*time.Hour))
	}
	milestones := weeklyMissions(p, id, start, now)
	if !milestones[0].Claimable || !milestones[1].Claimable {
		t.Fatalf("weekly missions: %+v", milestones)
	}
	if weeklyMissions(p, id, start, start.Add(9*24*time.Hour))[0].Claimable {
		t.Fatal("old weekly claims never expired")
	}
	s := testStore(t)
	app := testApp(t, s)
	token, user := progressAccount(t, app, "weeklyalice")
	editProgress(t, s, user, func(p *progression) { e := eventStateID(p, id); e.Clears = 3; e.Perfect = 300 })
	path := "/api/v1/events/" + id + "/missions/weekly_clears/claim"
	status, _, _ := request(t, app, "POST", path, map[string]any{}, token)
	requireStatus(t, status, 200)
	status, data, _ := request(t, app, "POST", path, map[string]any{}, token)
	requireStatus(t, status, 200)
	if data["reward"].(map[string]any)["already_claimed"] != true {
		t.Fatal("weekly reward duplicated")
	}
}
func TestMasterySeedsExistingVerifiedBests(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "legacyplayer")
	chart := firstChart()
	p, v, err := s.ReadProgress(id)
	if err != nil {
		t.Fatal(err)
	}
	p.rankedBest = &personalBest{Verification: 2, SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: 900000, Accuracy: 92, MaxCombo: chart.Units, RunID: "00000000000000000000000000000000", AchievedAt: time.Now().UnixMilli()}
	if ok, err := s.WriteProgress(id, v, p); err != nil || !ok {
		t.Fatal(err)
	}
	status, data, _ := request(t, app, "GET", "/api/v1/mastery/"+chart.SongID, nil, token)
	requireStatus(t, status, 200)
	if data["mastery"].(map[string]any)["completed"].(float64) != 3 {
		t.Fatal("verified historical best was not imported")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/mastery/"+chart.SongID+"/easy/claim", map[string]any{}, token)
	requireStatus(t, status, 200)
	p, _, err = s.ReadProgress(id)
	if err != nil || !p.MasterySeeded || !p.Mastery[chart.SongID].Claimed["easy"] {
		t.Fatal("mastery import/claim was not durable")
	}
}
