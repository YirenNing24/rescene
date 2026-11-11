package main

import (
	"os"
	"sync"
	"testing"
	"time"
)

func TestDailyLoginCalendar(t *testing.T) {
	now := time.Date(2026, 11, 9, 23, 59, 59, 0, time.UTC)
	var p progression
	p.normalize(now)
	var xp, stars int64
	for day := 1; day <= 7; day++ {
		date := now.Format("2006-01-02")
		view := loginView(p.Login, now)
		if view["next_day"] != day || view["claimed_today"] != false {
			t.Fatalf("wrong eligibility for day %d: %v", day, view)
		}
		gift, err := applyLoginClaim(&p, now, date, day)
		if err != nil || gift.Day != day || gift.AlreadyClaimed {
			t.Fatalf("claim day %d: %v", day, err)
		}
		xp += int64(loginRewards[day-1].XP)
		stars += int64(loginRewards[day-1].Starlight)
		duplicate, err := applyLoginClaim(&p, now, date, day)
		if err != nil || !duplicate.AlreadyClaimed || duplicate.XP != gift.XP || p.XP != xp || p.Starlight != stars {
			t.Fatal("retry changed balances or receipt")
		}
		if _, err := applyLoginClaim(&p, now, date, day%7+1); err == nil {
			t.Fatal("more than one gift claimed in a UTC day")
		}
		// Even a long missed interval preserves calendar progress.
		now = now.AddDate(0, 0, 3)
		if _, err := applyLoginClaim(&p, now, date, day); err == nil {
			t.Fatal("delayed request crossed the daily boundary")
		}
	}
	if xp != 700 || stars != 555 || p.Clears != 0 || len(p.Charts) != 0 || p.Daily.Clears != 0 {
		t.Fatal("wrong weekly totals or login incorrectly counted as gameplay")
	}
	if view := loginView(p.Login, now); view["completed"] != 0 || view["next_day"] != 1 {
		t.Fatal("calendar did not begin a new seven-day cycle")
	}
	if _, err := applyLoginClaim(&p, now, now.Format("2006-01-02"), 7); err == nil {
		t.Fatal("old day-seven request accepted in a new cycle")
	}
	if _, err := applyLoginClaim(&p, now, now.Format("2006-01-02"), 1); err != nil || p.XP != 750 {
		t.Fatal("new cycle could not start")
	}
}

func TestDailyLoginUTCAndUnlocks(t *testing.T) {
	now := time.Date(2026, 11, 9, 7, 59, 59, 0, time.FixedZone("Manila", 8*3600))
	p := progression{XP: 150}
	p.normalize(now)
	if _, err := applyLoginClaim(&p, now, "2026-11-09", 1); err == nil {
		t.Fatal("client local date overrode server UTC date")
	}
	gift, err := applyLoginClaim(&p, now, "2026-11-08", 1)
	if err != nil || gift.LevelBefore != 1 || gift.LevelAfter != 2 || len(gift.Unlocks) != 1 || gift.Unlocks[0] != "Rising Star" {
		t.Fatal("login XP did not unlock level cosmetics")
	}
	if _, err := applyLoginClaim(&p, now.Add(time.Second), "2026-11-09", 2); err != nil {
		t.Fatal("claim did not become available at UTC midnight")
	}
	if _, err := applyLoginClaim(&p, now, "2026-11-08", 1); err == nil {
		t.Fatal("server clock rollback allowed an extra reward")
	}
}

func TestDailyLoginConcurrentPersistenceAndIsolation(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "dailyplayer")
	other, _ := progressAccount(t, app, "otherdaily")
	date := snapshot(t, app, token)["daily_login"].(map[string]any)["date"].(string)
	body := map[string]any{"date": date, "day": 1}
	status, _, _ := request(t, app, "POST", "/api/v1/daily-login/claim", body, "")
	requireStatus(t, status, 401)
	for _, bad := range []any{map[string]any{"date": date, "day": 7}, map[string]any{"date": "1999-01-01", "day": 1}, `{"day":1,"xp":100000}`} {
		status, _, _ = request(t, app, "POST", "/api/v1/daily-login/claim", bad, token)
		if status != 400 && status != 409 {
			t.Fatalf("invalid claim status %d", status)
		}
	}
	var wg sync.WaitGroup
	awards := make(chan bool, 8)
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			status, response, _ := request(t, app, "POST", "/api/v1/daily-login/claim", body, token)
			requireStatus(t, status, 200)
			awards <- !response["reward"].(map[string]any)["already_claimed"].(bool)
		})
	}
	wg.Wait()
	close(awards)
	count := 0
	for awarded := range awards {
		if awarded {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("concurrent claim awarded %d times", count)
	}
	view := snapshot(t, app, token)
	if view["xp"].(float64) != 50 || view["starlight"].(float64) != 30 || view["daily_login"].(map[string]any)["claimed_today"] != true {
		t.Fatal("balances or calendar incorrect after concurrent claim")
	}
	if snapshot(t, app, other)["xp"].(float64) != 0 {
		t.Fatal("claim affected another account")
	}
	connection, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	p, _, err := connection.ReadProgress(id)
	if err != nil || p.Login.Last.Date != date || p.Login.Completed != 1 || p.XP != 50 {
		t.Fatal("claim did not survive a new database connection")
	}
	// An old user's payload without the new field also starts at Day 1.
	if snapshot(t, app, other)["daily_login"].(map[string]any)["next_day"].(float64) != 1 {
		t.Fatal("existing account migration did not default to Day 1")
	}
}
