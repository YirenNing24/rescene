package main

import (
	"fmt"
	"os"
	"sync"
	"testing"
	"time"
)

func TestEnergyRecoveryClockAndCap(t *testing.T) {
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	var p progression
	p.normalize(now)
	if p.Energy.Current != 15 || p.Energy.NextAt != 0 {
		t.Fatal("new accounts must start full")
	}
	p.normalize(now.Add(100 * time.Hour))
	now = now.Add(100 * time.Hour)
	if err := p.spendEnergy(now); err != nil {
		t.Fatal(err)
	}
	first := p.Energy.NextAt
	if p.Energy.Current != 14 || first != now.Add(30*time.Minute).UnixMilli() {
		t.Fatal("full time was banked")
	}
	if err := p.spendEnergy(now.Add(15 * time.Minute)); err != nil {
		t.Fatal(err)
	}
	if p.Energy.Current != 13 || p.Energy.NextAt != first {
		t.Fatal("spending discarded partial recovery")
	}
	p.normalize(now.Add(30*time.Minute - time.Millisecond))
	if p.Energy.Current != 13 {
		t.Fatal("energy recovered early")
	}
	p.normalize(now.Add(30 * time.Minute))
	if p.Energy.Current != 14 || p.Energy.NextAt != now.Add(time.Hour).UnixMilli() {
		t.Fatal("wrong exact boundary")
	}
	p.normalize(now.Add(30 * time.Minute))
	if p.Energy.Current != 14 {
		t.Fatal("the same boundary granted twice")
	}
	p.normalize(now.Add(30*time.Minute - time.Second))
	if p.Energy.Current != 14 {
		t.Fatal("backward clock granted energy")
	}
	p.normalize(now.Add(300 * time.Hour))
	if p.Energy.Current != 15 || p.Energy.NextAt != 0 {
		t.Fatal("offline recovery exceeded cap")
	}
	p.Energy = &energyProgress{Current: 0, NextAt: now.Add(30 * time.Minute).UnixMilli()}
	p.normalize(now.Add(7*time.Hour + 45*time.Minute))
	if p.Energy.Current != 15 || p.Energy.NextAt != 0 {
		t.Fatal("offline full recovery failed")
	}
	p.Energy = &energyProgress{Current: 0, NextAt: now.Add(30 * time.Minute).UnixMilli()}
	p.normalize(now.Add(90*time.Minute + 10*time.Second))
	if p.Energy.Current != 3 || p.Energy.NextAt != now.Add(2*time.Hour).UnixMilli() {
		t.Fatal("offline partial recovery lost remainder")
	}
}

func energyRunBody(chart rewardChart, request int) map[string]any {
	return map[string]any{"request_id": fmt.Sprintf("%032x", request), "song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}
}

func TestEnergySpendingPersistenceAndIsolation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "energyplayer")
	other, _ := progressAccount(t, app, "energyother")
	view := snapshot(t, app, token)["energy"].(map[string]any)
	if view["current"].(float64) != 15 || view["max"].(float64) != 15 || view["next_recovery_at"] != nil {
		t.Fatal("wrong initial energy view")
	}
	chart := firstChart()
	var last string
	for i := 1; i <= 15; i++ {
		status, body, _ := request(t, app, "POST", "/api/v1/runs", energyRunBody(chart, i), token)
		requireStatus(t, status, 200)
		last = body["reward"].(map[string]any)["id"].(string)
	}
	status, body, _ := request(t, app, "POST", "/api/v1/runs", energyRunBody(chart, 15), token)
	requireStatus(t, status, 200)
	if body["reward"].(map[string]any)["id"] != last {
		t.Fatal("duplicate request did not recover the same ticket")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/runs", energyRunBody(chart, 16), token)
	requireStatus(t, status, 409)
	if snapshot(t, app, token)["energy"].(map[string]any)["current"].(float64) != 0 {
		t.Fatal("empty energy changed")
	}
	if snapshot(t, app, other)["energy"].(map[string]any)["current"].(float64) != 15 {
		t.Fatal("another account was charged")
	}
	forged := energyRunBody(chart, 17)
	forged["energy"] = 15
	status, _, _ = request(t, app, "POST", "/api/v1/runs", forged, token)
	requireStatus(t, status, 400)
	editProgress(t, s, id, func(p *progression) { p.Energy.NextAt = time.Now().Add(-5 * time.Second).UnixMilli() })
	if snapshot(t, app, token)["energy"].(map[string]any)["current"].(float64) != 1 {
		t.Fatal("server did not recover elapsed energy")
	}
	reopened, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	restored, _, err := reopened.ReadProgress(id)
	if err != nil || restored.Energy.Current != 1 || len(restored.Starts) != 15 {
		t.Fatal("energy or dedupe receipts did not persist", err)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/runs", energyRunBody(chart, 16), token)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/runs", energyRunBody(chart, 15), token)
	requireStatus(t, status, 409) // Old retries cannot replace a newer active attempt.
}

func TestEnergyConcurrentStartsAndIdempotency(t *testing.T) {
	for _, duplicate := range []bool{false, true} {
		s := testStore(t)
		app := testApp(t, s)
		token, id := progressAccount(t, app, "concurrentenergy")
		var wg sync.WaitGroup
		var lock sync.Mutex
		runs := map[string]bool{}
		for i := 1; i <= 8; i++ {
			wg.Add(1)
			go func(index int) {
				defer wg.Done()
				if duplicate {
					index = 1
				}
				status, body, _ := request(t, app, "POST", "/api/v1/runs", energyRunBody(firstChart(), index), token)
				if status != 200 {
					t.Errorf("concurrent start: %d %v", status, body)
					return
				}
				lock.Lock()
				runs[body["reward"].(map[string]any)["id"].(string)] = true
				lock.Unlock()
			}(i)
		}
		wg.Wait()
		want := 7
		if duplicate {
			want = 14
		}
		p, _, err := s.ReadProgress(id)
		if err != nil || p.Energy.Current != want || len(runs) != 15-want {
			t.Fatal("concurrent requests charged incorrectly", p.Energy, runs, err)
		}
		if duplicate {
			other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
			if err != nil {
				t.Fatal(err)
			}
			otherApp := testApp(t, other)
			status, body, _ := request(t, otherApp, "POST", "/api/v1/runs", energyRunBody(firstChart(), 1), token)
			requireStatus(t, status, 200)
			if !runs[body["reward"].(map[string]any)["id"].(string)] {
				t.Fatal("restart did not recover the existing attempt")
			}
			p, _, err = other.ReadProgress(id)
			if err != nil || p.Energy.Current != 14 {
				t.Fatal("restart retry charged twice")
			}
			_ = other.Close()
		}
	}
}
