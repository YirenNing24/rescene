package main

import (
	"strings"
	"testing"
)

func TestRetiredSoundtracksCannotStartNewRuns(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "soundtrackretired")
	before := snapshot(t, app, token)["energy"].(map[string]any)["current"]
	for _, song := range []string{"6704cd078ba6", "51623539bf1f", "144504cd9688"} {
		chart, ok := rewardCharts[song+"/Easy"]
		if !ok || songSets[song] != "" {
			t.Fatal("Retired charts must remain archived outside the active catalog")
		}
		status, _, _ := request(t, app, "POST", "/api/v1/runs", map[string]any{"song_id": song, "difficulty": "Easy", "revision": chart.Revision, "replay_version": replayVersion}, token)
		requireStatus(t, status, 409)
	}
	if snapshot(t, app, token)["energy"].(map[string]any)["current"] != before {
		t.Fatal("Unavailable songs spent energy")
	}
	p, _, err := s.ReadProgress(id)
	if err != nil || p.Active != nil {
		t.Fatal("Unavailable song created a run ticket")
	}
	if len(songSets) != 29 {
		t.Fatalf("Expected 29 active songs, got %d", len(songSets))
	}
}

func TestSoundtrackRunIssuedBeforeRetirementStillCompletes(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "soundtrackexisting")
	run := startTestRun(t, app, token, firstChart())
	archived := rewardCharts["6704cd078ba6/Easy"]
	editProgress(t, s, id, func(p *progression) {
		p.Active.SongID = archived.SongID
		p.Active.Revision = archived.Revision
		p.Active.SetID = "the_first_night_with_the_duke_(original_television_soundtrack)_pt._1"
	})
	ageRun(t, s, id, archived)
	replay := fixtureReplay(archived, -1)
	replay.RunID = run
	result := replayResult(t, replay, archived)
	status, _, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", result, token)
	requireStatus(t, status, 200)
	rows, err := s.ReadBests(id)
	if err != nil || len(rows) != 1 || rows[0].SongID != archived.SongID || !strings.Contains(rows[0].Title, "BamBamBam") {
		t.Fatal("Retirement erased or broke archived score history", err)
	}
}
