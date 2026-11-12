package main

import (
	"strings"
	"testing"
	"time"
)

func TestMomentumBoundariesAndReset(t *testing.T) {
	for _, sample := range []struct{ combo, multiplier, budget int }{
		{0, 1, 0}, {19, 1, 19}, {20, 2, 21}, {39, 2, 59},
		{40, 3, 62}, {59, 3, 119}, {60, 5, 124}, {100, 5, 324},
	} {
		if momentumMultiplier(sample.combo) != sample.multiplier || momentumBudget(sample.combo) != sample.budget {
			t.Fatalf("wrong momentum boundary at %d", sample.combo)
		}
	}
	if momentumScore(strings.Repeat("P", 100), 100) != 1000000 {
		t.Fatal("all-perfect full combo must retain the million-point maximum")
	}
	if momentumScore(strings.Repeat("R", 100), 100) != 800000 || momentumScore(strings.Repeat("G", 100), 100) != 500000 {
		t.Fatal("judgment weights must apply before the multiplier")
	}
	// Equal hit totals, different miss placement: the shorter streak earns less.
	one := strings.Repeat("P", 99) + "M"
	two := strings.Repeat("P", 49) + "M" + strings.Repeat("P", 50)
	if momentumScore(one, 100) <= momentumScore(two, 100) {
		t.Fatal("a combo break did not reset the multiplier")
	}
	if momentumScore(strings.Repeat("P", 19)+"M"+"P", 21) != 869565 {
		t.Fatal("the first hit after a miss must earn only 1x")
	}
}

func TestLowMomentumScoreStillCommitsAndKeepsAccuracy(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	_, id := progressAccount(t, app, "momentumstore")
	chart := firstChart()
	p, version, err := s.ReadProgress(id)
	if err != nil {
		t.Fatal(err)
	}
	p.XP = 100
	p.publicationTarget = publicationTarget(publicationConfig())
	p.rankedBest = &personalBest{SongID: chart.SongID, Difficulty: chart.Difficulty, Revision: chart.Revision,
		Score: 400000, Accuracy: 80, MaxCombo: 30, AchievedAt: time.Now().UnixMilli(), RunID: strings.Repeat("3", 32)}
	if ok, err := s.WriteProgress(id, version, p); err != nil || !ok {
		t.Fatal("low-score progression failed", err)
	}
	rows, err := s.ReadBests(id)
	if err != nil || len(rows) != 1 || rows[0].Score != 400000 || rows[0].Accuracy != 80 || rows[0].Grade != "B" {
		t.Fatal("momentum score was confused with accuracy", rows, err)
	}
	if err := s.backfillPublications(p.publicationTarget); err != nil {
		t.Fatal(err)
	}
	r, err := s.query("MATCH(j:LeaderboardPublication) RETURN count(j)", nil)
	if err != nil || !r.Next() || r.Record().Values()[0].(int64) != 0 {
		t.Fatal("a score below the deployed contract minimum created a transaction", err)
	}
}

func TestReplayRejectsFabricatedMomentum(t *testing.T) {
	chart := firstChart()
	r := fixtureReplay(chart, 20)
	j, err := verifyInputReplay(r, runTicket{ReplayVersion: r.Version, ID: r.RunID, Revision: r.Revision}, chart)
	if err != nil {
		t.Fatal(err)
	}
	result := replayResult(t, r, chart)
	if err := j.matches(result, chart); err != nil {
		t.Fatal(err)
	}
	result.Score = 1000000
	if j.matches(result, chart) == nil {
		t.Fatal("inflated momentum score accepted")
	}
	result.Score = canonicalScore(j.counts, chart.Units)
	if j.matches(result, chart) == nil {
		t.Fatal("legacy counts-only score bypassed momentum verification")
	}
	result.Score = 1000000
	if validateResult(result, chart, false) == nil {
		t.Fatal("client replay metadata bypassed legacy ticket score validation")
	}
}
