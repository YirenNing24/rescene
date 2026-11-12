package main

import (
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
)

func progressAccount(t *testing.T, app *fiber.App, name string) (string, string) {
	t.Helper()
	status, body, _ := request(t, app, "POST", "/api/v1/auth/register", creds(name, "password123"), "")
	requireStatus(t, status, 201)
	return body["access_token"].(string), body["user"].(map[string]any)["id"].(string)
}
func snapshot(t *testing.T, app *fiber.App, token string) map[string]any {
	t.Helper()
	status, body, _ := request(t, app, "GET", "/api/v1/progression", nil, token)
	requireStatus(t, status, 200)
	return body["progression"].(map[string]any)
}
func startTestRun(t *testing.T, app *fiber.App, token string, chart rewardChart) string {
	t.Helper()
	status, body, _ := request(t, app, "POST", "/api/v1/runs", map[string]any{"song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}, token)
	requireStatus(t, status, 200)
	return body["reward"].(map[string]any)["id"].(string)
}
func editProgress(t *testing.T, s *graphStore, id string, edit func(*progression)) {
	t.Helper()
	p, v, err := s.ReadProgress(id)
	if err != nil {
		t.Fatal(err)
	}
	p.normalize(time.Now())
	edit(&p)
	ok, err := s.WriteProgress(id, v, p)
	if err != nil || !ok {
		t.Fatalf("seed progression: %v", err)
	}
}
func ageRun(t *testing.T, s *graphStore, id string, chart rewardChart) {
	editProgress(t, s, id, func(p *progression) {
		p.Active.StartedAt = time.Now().Add(-time.Duration(chart.Duration+4) * time.Second).UnixMilli()
	})
}
func firstChart() rewardChart { return rewardCharts["63e0fd3215f1/Easy"] }
func perfectResult(chart rewardChart, runIDs ...string) runResult {
	r := runResult{Score: 1000000, MaxCombo: chart.Units, Counts: map[string]int{"PERFECT": chart.Units, "GREAT": 0, "GOOD": 0, "MISS": 0}}
	if len(runIDs) > 0 {
		r.Replay = fixtureReplay(chart, -1)
		r.Replay.RunID = runIDs[0]
	}
	return r
}

func TestProgressionLifecycle(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "progressplayer")
	view := snapshot(t, app, token)
	if view["xp"].(float64) != 0 || view["level"].(float64) != 1 {
		t.Fatal("new player must start at level one")
	}
	if view["best_accuracy"].(float64) != 0 || view["full_combos"].(float64) != 0 || view["charts_cleared"].(float64) != 0 {
		t.Fatal("new player profile must start without clear statistics")
	}
	chart := firstChart()
	if chart.Units == 0 || chart.Duration == 0 {
		t.Fatal("missing embedded chart")
	}
	runID := startTestRun(t, app, token, chart)
	status, _, _ := request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", perfectResult(chart, runID), token)
	requireStatus(t, status, 409)
	ageRun(t, s, id, chart)
	status, body, _ := request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", perfectResult(chart, runID), token)
	requireStatus(t, status, 200)
	reward := body["reward"].(map[string]any)
	if reward["xp"].(float64) != 140 || reward["starlight"].(float64) != 60 || reward["first_clear"] != true {
		t.Fatal("wrong clear rewards")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", perfectResult(chart, runID), token)
	requireStatus(t, status, 200)
	view = snapshot(t, app, token)
	if view["xp"].(float64) != 140 || view["clears"].(float64) != 1 {
		t.Fatal("replayed run awarded twice")
	}
	if view["best_accuracy"].(float64) != 10000 || view["full_combos"].(float64) != 1 || view["charts_cleared"].(float64) != 1 || view["max_combo"].(float64) != float64(chart.Units) {
		t.Fatal("profile must expose persisted clear statistics without counting a duplicate receipt")
	}
	status, body, _ = request(t, app, "POST", "/api/v1/missions/first_clear/claim", map[string]string{"day": ""}, token)
	requireStatus(t, status, 200)
	if body["progression"].(map[string]any)["level"].(float64) != 2 {
		t.Fatal("first career claim should reach level two")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/missions/first_clear/claim", map[string]string{"day": ""}, token)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/progression/equip", map[string]string{"id": "rising_star"}, token)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/progression/equip", map[string]string{"id": "frost"}, token)
	requireStatus(t, status, 409)
	runID = startTestRun(t, app, token, chart)
	ageRun(t, s, id, chart)
	status, body, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", perfectResult(chart, runID), token)
	requireStatus(t, status, 200)
	reward = body["reward"].(map[string]any)
	if reward["xp"].(float64) != 100 || reward["first_clear"] != false {
		t.Fatal("first-chart bonus repeated")
	}
	// Re-open from a different connection to verify persisted claims and equipment.
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	p, _, err := other.ReadProgress(id)
	if err != nil || p.Title != "rising_star" || !p.Claimed["first_clear"] || p.Clears != 2 {
		t.Fatal("progress did not survive reopening store")
	}
}

func TestProgressionIsolationAndValidation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	one, id := progressAccount(t, app, "oneplayer")
	two, _ := progressAccount(t, app, "twoplayer")
	chart := firstChart()
	runID := startTestRun(t, app, one, chart)
	ageRun(t, s, id, chart)
	status, _, _ := request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", perfectResult(chart, runID), two)
	requireStatus(t, status, 409)
	bad := perfectResult(chart, runID)
	bad.Score = 123
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", bad, one)
	requireStatus(t, status, 409)
	bad = perfectResult(chart, runID)
	bad.Counts["MISS"] = -1
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", bad, one)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", `{"score":1000000,"xp":999999}`, one)
	requireStatus(t, status, 400)
	status, _, _ = request(t, app, "POST", "/api/v1/runs", map[string]string{"song_id": "fake", "difficulty": "Easy"}, one)
	requireStatus(t, status, 400)
	status, _, _ = request(t, app, "POST", "/api/v1/missions/five_clears/claim", map[string]string{"day": ""}, one)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "GET", "/api/v1/progression", nil, "")
	requireStatus(t, status, 401)
	if snapshot(t, app, two)["xp"].(float64) != 0 {
		t.Fatal("different account gained XP")
	}
}

func TestProgressionConcurrencyAndReset(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "concurrentplayer")
	editProgress(t, s, id, func(p *progression) { p.Clears = 1; p.Daily.Clears = 1 })
	var wg sync.WaitGroup
	statuses := make(chan int, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			status, _, _ := request(t, app, "POST", "/api/v1/missions/first_clear/claim", map[string]string{"day": ""}, token)
			statuses <- status
		}()
	}
	wg.Wait()
	close(statuses)
	success := 0
	for status := range statuses {
		if status == 200 {
			success++
		} else if status != 409 {
			t.Errorf("unexpected status %d", status)
		}
	}
	if success != 1 {
		t.Fatal("claim was not atomic")
	}
	if snapshot(t, app, token)["xp"].(float64) != 100 {
		t.Fatal("claim awarded more than once")
	}
	day := time.Now().UTC().Format("2006-01-02")
	status, _, _ := request(t, app, "POST", "/api/v1/missions/daily_one/claim", map[string]string{"day": day}, token)
	requireStatus(t, status, 200)
	editProgress(t, s, id, func(p *progression) { p.Daily.Day = time.Now().UTC().Add(-24 * time.Hour).Format("2006-01-02") })
	view := snapshot(t, app, token)
	for _, raw := range view["missions"].([]any) {
		m := raw.(map[string]any)
		if m["id"] == "daily_one" && (m["progress"].(float64) != 0 || m["claimed"] != false) {
			t.Fatal("daily reset failed")
		}
	}
	status, _, _ = request(t, app, "POST", "/api/v1/missions/daily_one/claim", map[string]string{"day": "1999-01-01"}, token)
	requireStatus(t, status, 409)
	p, _, err := s.ReadProgress(id)
	if err != nil || !p.Claimed["first_clear"] {
		t.Fatal("daily reset erased career claim")
	}
	// Two independent read/modify/write callers cannot overwrite each other.
	a, v, _ := s.ReadProgress(id)
	b, _, _ := s.ReadProgress(id)
	a.XP++
	b.XP++
	ok, err := s.WriteProgress(id, v, a)
	if err != nil || !ok {
		t.Fatal(err)
	}
	ok, err = s.WriteProgress(id, v, b)
	if err != nil || ok {
		t.Fatal("stale version accepted")
	}
}

func TestProgressionRules(t *testing.T) {
	for _, test := range []struct {
		xp    int64
		level int
	}{{0, 1}, {199, 1}, {200, 2}, {499, 2}, {500, 3}, {900, 4}} {
		level, _, _ := levelFor(test.xp)
		if level != test.level {
			t.Error(fmt.Sprint(test))
		}
	}
	if len(rewardCharts) != 128 {
		t.Fatalf("expected 128 charts, got %d", len(rewardCharts))
	}
	for _, chart := range rewardCharts {
		if chart.Units <= 0 || chart.Duration < 30 || len(chart.Revision) != 64 || chart.Title == "" {
			t.Fatal("invalid chart metadata")
		}
		if err := validateResult(perfectResult(chart), chart, false); err != nil {
			t.Fatal(err)
		}
	}
}
