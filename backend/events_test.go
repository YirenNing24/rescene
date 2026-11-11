package main

import (
	"sync"
	"testing"
	"time"
)

func TestPulseEventScheduleAndScoring(t *testing.T) {
	start := pulseEventStart
	pulseTicket := func(song string, at time.Time) *eventTicket {
		for _, v := range eventTickets(song, at) {
			if v.ID == pulseEventID {
				copy := v
				return &copy
			}
		}
		return nil
	}
	if pulseTicket(pulseSongs[0], start.Add(-time.Millisecond)) != nil || pulseTicket(pulseSongs[0], pulseEventEnd) != nil || pulseTicket("other", start) != nil {
		t.Fatal("event admitted an ineligible attempt")
	}
	for i, id := range pulseSongs {
		ticket := pulseTicket(id, start.Add(time.Duration(i)*24*time.Hour+time.Minute))
		if ticket == nil || !ticket.Featured {
			t.Fatalf("day %d rotation incorrect", i)
		}
	}
	if pulseTicket(pulseSongs[0], start.Add(24*time.Hour)).Featured {
		t.Fatal("featured credit did not rotate")
	}
	var p progression
	run := runTicket{SongID: pulseSongs[0], StartedAt: start.Add(time.Hour).UnixMilli(), Events: eventTickets(pulseSongs[0], start.Add(time.Hour))}
	result := runResult{Counts: map[string]int{"PERFECT": 250, "MISS": 0}}
	advanceEvents(&p, run, result, start.Add(time.Hour+time.Minute))
	e := eventState(&p)
	if e.Clears != 1 || e.Featured != 1 || e.Perfect != 250 || e.FullCombos != 1 || len(e.Songs) != 1 {
		t.Fatalf("incorrect event progress: %+v", e)
	}
	// A run remembers the featured song from its start when the day changes.
	run.StartedAt = start.Add(24*time.Hour - time.Minute).UnixMilli()
	advanceEvents(&p, run, result, start.Add(24*time.Hour+time.Minute))
	if e.Featured != 2 {
		t.Fatal("rotation changed the in-flight ticket")
	}
	advanceEvents(&p, runTicket{SongID: pulseSongs[0], StartedAt: start.Add(-time.Second).UnixMilli(), Events: run.Events}, result, start)
	advanceEvents(&p, runTicket{SongID: pulseSongs[0], StartedAt: pulseEventEnd.UnixMilli(), Events: run.Events}, result, pulseEventEnd)
	advanceEvents(&p, run, result, pulseClaimEnd)
	if e.Clears != 2 {
		t.Fatal("out-of-window run was counted")
	}
	m := eventMissions(p, start.Add(time.Hour))
	if !m[0].Claimable || m[1].Claimable || m[6].Progress != 2 {
		t.Fatalf("invalid milestone eligibility: %+v", m)
	}
	if eventMissions(p, pulseClaimEnd)[0].Claimable {
		t.Fatal("claim deadline was not enforced")
	}
}

func TestEventVerifiedRunsClaimsAndItemOutbox(t *testing.T) {
	if time.Now().Before(pulseEventStart) || !time.Now().Before(pulseEventEnd) {
		t.Skip("integration fixture requires the scheduled event window")
	}
	s := testStore(t)
	app := testApp(t, s)
	token, id := progressAccount(t, app, "eventtester")
	other, _ := progressAccount(t, app, "eventother")
	chart := rewardCharts[pulseSongs[0]+"/Easy"]
	if chart.Units == 0 {
		t.Fatal("missing PULSE chart")
	}
	run := startTestRun(t, app, token, chart)
	ageRun(t, s, id, chart)
	bad := perfectResult(chart, run)
	bad.Score = 1
	status, _, _ := request(t, app, "POST", "/api/v1/runs/"+run+"/complete", bad, token)
	requireStatus(t, status, 409)
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart, run), token)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart, run), token)
	requireStatus(t, status, 200)
	p, _, err := s.ReadProgress(id)
	if err != nil || eventState(&p).Clears != 1 {
		t.Fatal("verified result duplicated or lost")
	}
	if snapshot(t, app, other)["xp"].(float64) != 0 {
		t.Fatal("different player was changed")
	}
	path := "/api/v1/events/" + pulseEventID + "/missions/opening/claim"
	status, _, _ = request(t, app, "POST", path, map[string]any{"xp": 999999}, token)
	requireStatus(t, status, 400)
	status, _, _ = request(t, app, "POST", path, map[string]any{}, other)
	requireStatus(t, status, 409)
	before := p.XP
	var wg sync.WaitGroup
	awards := make(chan bool, 8)
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			status, response, _ := request(t, app, "POST", path, map[string]any{}, token)
			requireStatus(t, status, 200)
			reward := response["reward"].(map[string]any)
			awards <- reward["already_claimed"] != true
		})
	}
	wg.Wait()
	close(awards)
	n := 0
	for award := range awards {
		if award {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("awarded %d times", n)
	}
	p, version, err := s.ReadProgress(id)
	if err != nil || p.XP != before+100 || !eventState(&p).Claimed["opening"] {
		t.Fatal("event claim was not persisted exactly once")
	}
	// The item outbox is committed with the progression CAS and isolated from STARL.
	p.eventItems = 2
	p.eventItemTarget = "test-event-target"
	p.starlightAward = 50
	p.starlightTarget = "test-star-target"
	ok, err := s.WriteProgress(id, version, p)
	if err != nil || !ok {
		t.Fatalf("item outbox: %v", err)
	}
	job, ok, err := s.claimReward("EventItemReward", "test-event-target", time.Now())
	if err != nil || !ok || job.Amount != 2 || job.Owner != id {
		t.Fatalf("item outbox job: %+v %v", job, err)
	}
	if _, ok, err = s.claimStarlight("test-event-target", time.Now()); err != nil || ok {
		t.Fatal("item job leaked into STARL queue")
	}
	star, ok, err := s.claimStarlight("test-star-target", time.Now())
	if err != nil || !ok || star.Amount != 50 || star.Owner != id {
		t.Fatal("STARL and item outboxes were not committed together")
	}
	if err = s.saveReward("EventItemReward", job, time.Now()); err != nil {
		t.Fatal(err)
	}
}
