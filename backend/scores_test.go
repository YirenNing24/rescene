package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
)

func traceResult(trace string) runResult {
	r := runResult{Trace: trace, Counts: map[string]int{"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}}
	combo := 0
	for _, unit := range trace {
		kind := map[rune]string{'P': "PERFECT", 'R': "GREAT", 'G': "GOOD", 'M': "MISS"}[unit]
		r.Counts[kind]++
		if unit == 'M' {
			combo = 0
		} else {
			combo++
			r.MaxCombo = max(r.MaxCombo, combo)
		}
	}
	r.Score = momentumScore(trace, len(trace))
	return r
}
func rankedRun(t *testing.T, app *fiber.App, store *graphStore, token, id string, chart rewardChart) string {
	t.Helper()
	status, body, _ := request(t, app, "POST", "/api/v1/runs", map[string]any{"song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}, token)
	requireStatus(t, status, 200)
	run := body["reward"].(map[string]any)["id"].(string)
	ageRun(t, store, id, chart)
	return run
}
func rankedClear(t *testing.T, app *fiber.App, store *graphStore, token, id string, chart rewardChart, trace string) map[string]any {
	t.Helper()
	run := rankedRun(t, app, store, token, id, chart)
	skip := -1
	if strings.Contains(trace, "M") {
		target := chart.Duration / 2
		if strings.HasSuffix(trace, "M") {
			target = chart.Duration
		}
		distance := chart.Duration
		for i, n := range chart.Notes {
			if n.Kind == "tap" && math.Abs(n.Time-target) < distance {
				skip = i
				distance = math.Abs(n.Time - target)
			}
		}
	}
	replay := fixtureReplay(chart, skip)
	replay.RunID = run
	result := replayResult(t, replay, chart)
	status, body, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", result, token)
	requireStatus(t, status, 200)
	if body["reward"].(map[string]any)["ranked"] != true {
		t.Fatal("ranked clear not published")
	}
	return body
}
func getBoard(t *testing.T, app *fiber.App, token string, chart rewardChart) map[string]any {
	t.Helper()
	status, body, _ := request(t, app, "GET", "/api/v1/leaderboards?song_id="+chart.SongID+"&difficulty="+strings.ReplaceAll(chart.Difficulty, " ", "%20"), nil, token)
	requireStatus(t, status, 200)
	return body["leaderboard"].(map[string]any)
}

func TestCloudScoresLifecycleAndPublicPrivacy(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	one, id := progressAccount(t, app, "rankedone")
	two, id2 := progressAccount(t, app, "rankedtwo")
	three, _ := progressAccount(t, app, "spectator")
	chart := firstChart()
	split := strings.Repeat("P", chart.Units/2) + "M" + strings.Repeat("P", chart.Units-chart.Units/2-1)
	rankedClear(t, app, s, one, id, chart, split)
	rankedClear(t, app, s, two, id2, chart, strings.Repeat("P", chart.Units-1)+"M")
	board := getBoard(t, app, one, chart)
	if board["total"].(float64) != 2 || board["me"].(map[string]any)["position"].(float64) != 2 {
		t.Fatal("score/combo ordering or own rank is wrong")
	}
	if board["top"].([]any)[0].(map[string]any)["username"] != "rankedtwo" {
		t.Fatal("the longer streak must earn a higher momentum score")
	}
	if getBoard(t, app, three, chart)["me"] != nil {
		t.Fatal("spectator received another account's rank")
	}
	rankedClear(t, app, s, one, id, chart, strings.Repeat("P", chart.Units))
	before, err := s.ReadBests(id)
	if err != nil || len(before) != 1 {
		t.Fatalf("read best: %v", err)
	}
	rankedClear(t, app, s, one, id, chart, split)
	after, _ := s.ReadBests(id)
	if after[0].Score != 1000000 || after[0].AchievedAt != before[0].AchievedAt {
		t.Fatal("worse replay replaced a best or changed its tie timestamp")
	}
	board = getBoard(t, app, one, chart)
	if board["me"].(map[string]any)["position"].(float64) != 1 {
		t.Fatal("improvement did not change rank")
	}
	status, body, _ := request(t, app, "GET", "/api/v1/records", nil, one)
	requireStatus(t, status, 200)
	if len(body["records"].([]any)) != 1 {
		t.Fatal("cloud records missing")
	}
	status, body, _ = request(t, app, "GET", "/api/v1/records?user_id="+id, nil, two)
	requireStatus(t, status, 200)
	if body["records"].([]any)[0].(map[string]any)["score"].(float64) == 1000000 {
		t.Fatal("records endpoint accepted a forged account identity")
	}
	status, body, _ = request(t, app, "GET", "/api/v1/players/"+id, nil, two)
	requireStatus(t, status, 200)
	encoded, _ := json.Marshal(body)
	for _, private := range []string{"password", "wallet", "access_token", "starlight", "missions", "receipts"} {
		if strings.Contains(string(encoded), private) {
			t.Fatalf("public profile leaked %s", private)
		}
	}
	if body["profile"].(map[string]any)["username"] != "rankedone" {
		t.Fatal("wrong public player")
	}
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	restored, err := other.ReadBests(id)
	if err != nil || len(restored) != 1 || restored[0].Score != 1000000 {
		t.Fatal("best did not survive a new server connection")
	}
	status, _, _ = request(t, app, "GET", "/api/v1/records", nil, "")
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "GET", "/api/v1/players/missing", nil, one)
	requireStatus(t, status, 404)
	status, _, _ = request(t, app, "GET", "/api/v1/leaderboards?song_id=unknown&difficulty=Easy", nil, one)
	requireStatus(t, status, 400)
}

func TestRankedValidationAndAtomicDuplicate(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "traceplayer")
	chart := firstChart()
	status, _, _ := request(t, app, "POST", "/api/v1/runs", map[string]string{"song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": "forged-chart"}, token)
	requireStatus(t, status, 409)
	run := rankedRun(t, app, s, token, id, chart)
	replay := fixtureReplay(chart, -1)
	replay.RunID = run
	valid := replayResult(t, replay, chart)
	for _, trace := range []string{strings.Repeat("P", chart.Units-1), strings.Repeat("X", chart.Units), strings.Repeat("G", chart.Units)} {
		bad := valid
		bad.Trace = trace
		status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", bad, token)
		requireStatus(t, status, 409)
	}
	if rows, _ := s.ReadBests(id); len(rows) != 0 {
		t.Fatal("rejected result entered rankings")
	}
	var wg sync.WaitGroup
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, _, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", valid, token)
			if code != 200 && code != 503 {
				t.Errorf("duplicate status %d", code)
			}
		}()
	}
	wg.Wait()
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", valid, token)
	requireStatus(t, status, 200)
	if snapshot(t, app, token)["clears"].(float64) != 1 {
		t.Fatal("duplicate clear counted twice")
	}
	if getBoard(t, app, token, chart)["total"].(float64) != 1 {
		t.Fatal("duplicate score rows")
	}
	// Pre-upgrade in-flight tickets can finish unranked; new tickets require inputs.
	legacy := startTestRun(t, app, token, chart)
	ageRun(t, s, id, chart)
	editProgress(t, s, id, func(p *progression) { p.Active.ReplayVersion = 0 })
	status, body, _ := request(t, app, "POST", "/api/v1/runs/"+legacy+"/complete", perfectResult(chart), token)
	requireStatus(t, status, 200)
	if body["reward"].(map[string]any)["ranked"] != false {
		t.Fatal("legacy result entered leaderboard")
	}
	// Counts can be plausible while the reported maximum streak is impossible.
	bad := traceResult(strings.Repeat("P", chart.Units-1) + "M")
	bad.MaxCombo = chart.Units / 2
	judge, _ := verifyInputReplay(valid.Replay, runTicket{ReplayVersion: valid.Replay.Version, ID: run, Revision: chart.Revision}, chart)
	if judge.matches(bad, chart) == nil {
		t.Fatal("wrong ordered maximum combo accepted")
	}
	p, version, err := s.ReadProgress(id)
	if err != nil {
		t.Fatal(err)
	}
	if ok, err := s.WriteProgress(id, version, p); !ok || err != nil {
		t.Fatal("fixture CAS failed")
	}
	other := rewardCharts[chart.SongID+"/Hard"]
	p.rankedBest = &personalBest{SongID: other.SongID, Difficulty: other.Difficulty, Revision: other.Revision, Score: 1000000, MaxCombo: other.Units, AchievedAt: 1}
	if ok, err := s.WriteProgress(id, version, p); ok || err != nil {
		t.Fatal("stale score CAS accepted")
	}
	if rows, err := s.ReadBests(id); err != nil || len(rows) != 1 {
		t.Fatal("a rejected CAS created a phantom ranked record")
	}
}

func TestLeaderboardNearbyAndRevisionIsolation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "nearbyplayer")
	chart := firstChart()
	rankedClear(t, app, s, token, id, chart, strings.Repeat("P", chart.Units-10)+strings.Repeat("M", 10))
	for i := 0; i < 30; i++ {
		uid := fmt.Sprintf("seed-%02d", i)
		_, err := s.Create(user{ID: uid, Username: uid, CreatedAt: time.Now().UTC().Format(time.RFC3339), PasswordHash: "fixture-only"}, uid)
		if err != nil {
			t.Fatal(err)
		}
		p, v, err := s.ReadProgress(uid)
		if err != nil {
			t.Fatal(err)
		}
		p.rankedBest = &personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision, Score: 1000000, MaxCombo: chart.Units, AchievedAt: 1, RunID: uid}
		if ok, err := s.WriteProgress(uid, v, p); !ok || err != nil {
			t.Fatalf("seed score: %v", err)
		}
	}
	board := getBoard(t, app, token, chart)
	if len(board["top"].([]any)) != 25 || board["me"].(map[string]any)["position"].(float64) != 31 {
		t.Fatal("top bound or rank outside top 25 is wrong")
	}
	nearby := board["nearby"].([]any)
	if len(nearby) != 3 || nearby[2].(map[string]any)["user_id"] != id {
		t.Fatal("nearby rows must include the requesting player outside the top list")
	}
	otherChart := rewardCharts[chart.SongID+"/Hard"]
	if getBoard(t, app, token, otherChart)["total"].(float64) != 0 {
		t.Fatal("difficulty leaked into another board")
	}
	_, err := s.query(`MATCH (b:PersonalBest {owner:$id}) SET b.chart_key='old',b.revision='old' RETURN b.key`, map[string]interface{}{"id": id})
	if err != nil {
		t.Fatal(err)
	}
	if rows, _ := s.ReadBests(id); len(rows) != 0 {
		t.Fatal("old chart revision restored as current best")
	}
	if getBoard(t, app, token, chart)["me"] != nil {
		t.Fatal("old revision ranked with the current chart")
	}
}

func TestLeaderboardUsesCurrentAvatarWithoutExposingGallery(t *testing.T) {
	s := testStore(t)
	app := photoTestApp(t, s, t.TempDir())
	token, owner := photoLogin(t, app, "RankPhoto")
	other, otherID := photoLogin(t, app, "RankDefault")
	chart := firstChart()
	rankedClear(t, app, s, token, owner, chart, strings.Repeat("P", chart.Units))
	rankedClear(t, app, s, other, otherID, chart, strings.Repeat("P", chart.Units-1)+"M")
	checkAvatar := func(want any) {
		t.Helper()
		board := getBoard(t, app, token, chart)
		for _, section := range []string{"top", "nearby"} {
			rows := board[section].([]any)
			if len(rows) != 2 || rows[0].(map[string]any)["user_id"] != owner {
				t.Fatalf("%s avatar change altered score ordering", section)
			}
			for _, raw := range rows {
				row := raw.(map[string]any)
				expected := want
				if row["user_id"] != owner {
					expected = nil
				}
				got, _ := json.Marshal(row["avatar"])
				expectedJSON, _ := json.Marshal(expected)
				if string(got) != string(expectedJSON) {
					t.Fatalf("%s avatar: got %s, want %s", section, got, expectedJSON)
				}
				for _, private := range []string{"gallery", "profile_media", "password_hash", "wallet"} {
					if _, leaked := row[private]; leaked {
						t.Fatalf("ranking leaked %s", private)
					}
				}
			}
		}
		got, _ := json.Marshal(board["me"].(map[string]any)["avatar"])
		wantJSON, _ := json.Marshal(want)
		if string(got) != string(wantJSON) {
			t.Fatal("own ranking has a different avatar")
		}
	}
	checkAvatar(nil)
	status, raw := photoCall(t, app, "POST", "/api/v1/profile/media/gallery", token, photoBytes(t))
	requireStatus(t, status, 200)
	checkAvatar(nil) // A gallery picture is not the player's display picture.
	var avatar map[string]any
	for range 2 {
		status, raw = photoCall(t, app, "POST", "/api/v1/profile/media/avatar", token, photoBytes(t))
		requireStatus(t, status, 200)
		next := mediaResult(t, raw)["avatar"].(map[string]any)
		if avatar != nil && next["url"] == avatar["url"] {
			t.Fatal("replacement reused the old photo URL")
		}
		avatar = next
		checkAvatar(avatar)
		status, _ = photoCall(t, app, "GET", avatar["url"].(string), other, nil)
		requireStatus(t, status, 200)
	}
	status, _ = photoCall(t, app, "DELETE", "/api/v1/profile/media/avatar/"+avatar["id"].(string), token, nil)
	requireStatus(t, status, 200)
	checkAvatar(nil)
	if _, err := s.query(`MATCH (u:User {id:$id}) SET u.profile_media='invalid-json' RETURN u.id`, map[string]interface{}{"id": owner}); err != nil {
		t.Fatal(err)
	}
	checkAvatar(nil) // Broken optional media never removes a valid score.
}
