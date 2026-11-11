package main

import (
	"encoding/json"
	"math"
	"os"
	"sort"
	"strings"
	"testing"
)

func fixtureReplay(chart rewardChart, skip int) *inputReplay {
	r := &inputReplay{Version: replayVersion, RunID: "fixture-run", Revision: chart.Revision, EndUS: int64(math.Round(chart.Duration * 1000000))}
	free := make([]int64, 10)
	for i, n := range chart.Notes {
		if i == skip {
			continue
		}
		at := int64(math.Round(n.Time * 1000000))
		end := at
		if n.Kind != "tap" {
			end = int64(math.Round((n.Time + n.Duration + 0.01) * 1000000))
		}
		id := -1
		for k := range free {
			if free[k] <= at {
				id = k
				break
			}
		}
		if id < 0 {
			panic("fixture exceeds ten simultaneous contacts")
		}
		free[id] = end + 1
		r.Events = append(r.Events, []int64{at, 0, int64(id), int64(math.Round(n.Lane * 10000))})
		if n.Kind == "slide" {
			for t := n.Time + 0.01; t < n.Time+n.Duration; t += 0.01 {
				r.Events = append(r.Events, []int64{int64(math.Round(t * 1000000)), 1, int64(id), int64(math.Round(n.laneAt(t) * 10000))})
			}
		}
		r.Events = append(r.Events, []int64{end, 2, int64(id), 0})
	}
	sort.SliceStable(r.Events, func(i, j int) bool { return r.Events[i][0] < r.Events[j][0] })
	return r
}
func replayResult(t *testing.T, r *inputReplay, chart rewardChart) runResult {
	t.Helper()
	j, err := verifyInputReplay(r, runTicket{ID: r.RunID, Revision: r.Revision}, chart)
	if err != nil {
		t.Fatal(err)
	}
	return runResult{Score: momentumScore(j.trace.String(), chart.Units), MaxCombo: j.maxCombo, Counts: j.counts, Trace: j.trace.String(), Replay: r}
}
func TestReplayAllCharts(t *testing.T) {
	for _, chart := range rewardCharts {
		r := fixtureReplay(chart, -1)
		result := replayResult(t, r, chart)
		if result.Score != 1000000 || result.Counts["MISS"] != 0 || result.MaxCombo != chart.Units {
			t.Fatalf("valid autoplay rejected: %s/%s score=%d counts=%v", chart.SongID, chart.Difficulty, result.Score, result.Counts)
		}
	}
}
func TestReplayRejectsFabrication(t *testing.T) {
	chart := firstChart()
	r := fixtureReplay(chart, -1)
	run := runTicket{ID: r.RunID, Revision: r.Revision}
	for _, edit := range []func(*inputReplay){
		func(r *inputReplay) { r.RunID = "another-run" }, func(r *inputReplay) { r.Revision = "another-chart" }, func(r *inputReplay) { r.Version = 1 }, func(r *inputReplay) { r.EndUS = 1 },
		func(r *inputReplay) { r.Events[0][0] = -150001 }, func(r *inputReplay) { r.Events[0][1] = 99 }, func(r *inputReplay) { r.Events[0][2] = 999 }, func(r *inputReplay) { r.Events[0][3] = 1000000 },
		func(r *inputReplay) { r.Events[1][0] = r.Events[0][0] - 1 }, func(r *inputReplay) {
			r.Events = append(r.Events[:1], append([][]int64{r.Events[0]}, r.Events[1:]...)...)
		},
		func(r *inputReplay) { r.Events[0] = []int64{0, 0} }, func(r *inputReplay) { r.Events = make([][]int64, maxReplayEvents+1) },
	} {
		copy := fixtureReplay(chart, -1)
		edit(copy)
		if _, err := verifyInputReplay(copy, run, chart); err == nil {
			t.Fatal("malformed replay was accepted")
		}
	}
	// A perfect judgment string with no matching inputs must not award a clear.
	empty := &inputReplay{Version: replayVersion, RunID: run.ID, Revision: run.Revision, EndUS: r.EndUS}
	if j, err := verifyInputReplay(empty, run, chart); err == nil && j.matches(traceResult(strings.Repeat("P", chart.Units)), chart) == nil {
		t.Fatal("fabricated perfect results accepted without inputs")
	}
	// Holding a slide's starting lane cannot reproduce a traced slide's result.
	stationary := fixtureReplay(chart, -1)
	filtered := [][]int64{}
	for _, e := range stationary.Events {
		if e[1] != 1 {
			filtered = append(filtered, e)
		}
	}
	stationary.Events = filtered
	if j, err := verifyInputReplay(stationary, run, chart); err == nil && j.matches(traceResult(strings.Repeat("P", chart.Units)), chart) == nil {
		t.Fatal("stationary pointers completed curved notes")
	}
	early := fixtureReplay(chart, -1)
	pressed := map[int64]int64{}
	events := [][]int64{}
	for _, e := range early.Events {
		if e[1] == 1 {
			continue
		}
		if e[1] == 0 {
			pressed[e[2]] = e[0]
		} else if e[1] == 2 {
			e[0] = min(e[0], pressed[e[2]]+1000)
		}
		events = append(events, e)
	}
	sort.SliceStable(events, func(i, j int) bool { return events[i][0] < events[j][0] })
	early.Events = events
	if j, err := verifyInputReplay(early, run, chart); err == nil && j.matches(traceResult(strings.Repeat("P", chart.Units)), chart) == nil {
		t.Fatal("early releases completed long notes")
	}
}

func TestReplayUpgradeAndPausedProgression(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "verifiedplayer")
	chart := firstChart()
	status, _, _ := request(t, app, "POST", "/api/v1/runs", map[string]string{"song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision}, token)
	requireStatus(t, status, 400)
	run := rankedRun(t, app, s, token, id, chart)
	// Metadata alone cannot complete newly issued tickets, even with perfect totals.
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart), token)
	requireStatus(t, status, 409)
	r := fixtureReplay(chart, -1)
	r.RunID = run
	r.Events = append([][]int64{{0, 3, 0, 0}}, r.Events...)
	result := replayResult(t, r, chart)
	status, body, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", result, token)
	requireStatus(t, status, 200)
	reward := body["reward"].(map[string]any)
	if reward["ranked"] != false || reward["unranked_reason"] != "paused" || reward["verification"].(float64) != replayVersion || snapshot(t, app, token)["clears"].(float64) != 1 {
		t.Fatal("paused inputs should award verified progression without a ranked score")
	}
	if board := getBoard(t, app, token, chart); board["total"].(float64) != 0 {
		t.Fatal("paused replay entered rankings")
	}
	rankedClear(t, app, s, token, id, chart, strings.Repeat("P", chart.Units))
	// Existing v1 entries stay in the database but cannot appear as verified scores.
	_, err := s.query(`MATCH (b:PersonalBest {owner:$id}) SET b.verification=1 RETURN b.key`, map[string]interface{}{"id": id})
	if err != nil {
		t.Fatal(err)
	}
	if board := getBoard(t, app, token, chart); board["total"].(float64) != 0 {
		t.Fatal("old judgment-only record still ranked")
	}
	if rows, _ := s.ReadBests(id); len(rows) != 0 {
		t.Fatal("old unverified record returned as a cloud best")
	}
	rankedClear(t, app, s, token, id, chart, strings.Repeat("P", chart.Units-1)+"M")
	if rows, _ := s.ReadBests(id); len(rows) != 1 || rows[0].Verification != 2 || rows[0].Score == 1000000 {
		t.Fatal("first verified replay did not replace a higher unverified legacy entry")
	}
}

func TestReplayParity(t *testing.T) {
	path := os.Getenv("RESCENE_REPLAY_GOLDENS")
	if path == "" {
		t.Skip("use tools/test_replay.py for Godot/Go parity")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		SongID     string       `json:"song_id"`
		Difficulty string       `json:"difficulty"`
		Result     runResult    `json:"result"`
		Dead       bool         `json:"dead"`
		Paused     bool         `json:"paused"`
		Card       *cardLoadout `json:"card"`
		CardPoints int64        `json:"card_points"`
		LifeMilli  int          `json:"life_milli"`
	}
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) < 128 {
		t.Fatal("parity must cover every chart and adversarial input styles")
	}
	for _, f := range fixtures {
		chart := rewardCharts[f.SongID+"/"+f.Difficulty]
		r := f.Result.Replay
		j, err := verifyInputReplay(r, runTicket{ID: r.RunID, Revision: r.Revision, Card: f.Card}, chart)
		if f.Dead {
			if err == nil {
				t.Fatal("Go accepted a Godot game-over replay")
			}
			continue
		}
		if err != nil {
			t.Fatalf("%s/%s rejected: %v", f.SongID, f.Difficulty, err)
		}
		if err = j.matches(f.Result, chart); err != nil || j.paused != f.Paused || j.cardPoints != f.CardPoints || j.life != f.LifeMilli {
			t.Fatalf("Godot/Go diverged %s/%s: %v; go=%v/%d, Godot=%v/%d", f.SongID, f.Difficulty, err, j.counts, j.maxCombo, f.Result.Counts, f.Result.MaxCombo)
		}
	}
}
