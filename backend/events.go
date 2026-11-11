package main

import (
	"time"

	"github.com/gofiber/fiber/v3"
)

// Event rules are versioned with the server, never supplied by a client. A new
// edition needs a new ID; extending/reopening an old edition cannot reset claims.
const pulseEventID = "pulse_first_scene_2026"

var pulseSongs = []string{"ca722c0b0e8b", "38c9a4926480", "a950208419f4", "96dce23d7f60", "f2b3fdebb1b3"}
var pulseTitles = []string{"Finest Thing", "With", "Inside Out", "MEME", "Dragon"}
var pulseEventStart = time.Date(2026, 11, 10, 16, 0, 0, 0, time.UTC)
var pulseEventEnd = pulseEventStart.Add(14 * 24 * time.Hour)
var pulseClaimEnd = pulseEventEnd.Add(48 * time.Hour)

type eventTicket struct {
	ID       string `json:"id"`
	Featured bool   `json:"featured"`
}
type eventProgress struct {
	Clears     int64           `json:"clears"`
	Featured   int64           `json:"featured"`
	Perfect    int64           `json:"perfect"`
	FullCombos int64           `json:"full_combos"`
	Songs      map[string]bool `json:"songs"`
	Claimed    map[string]bool `json:"claimed"`
}
type eventMission struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Target      int64  `json:"target"`
	Progress    int64  `json:"progress"`
	XP          int    `json:"xp"`
	Starlight   int    `json:"starlight"`
	Shards      int    `json:"shards"`
	Claimed     bool   `json:"claimed"`
	Claimable   bool   `json:"claimable"`
}

func pulseSong(song string) bool {
	for _, id := range pulseSongs {
		if song == id {
			return true
		}
	}
	return false
}
func featuredPulse(now time.Time) int {
	day := int(now.Sub(pulseEventStart) / (24 * time.Hour))
	if day < 0 {
		day = 0
	}
	return day % len(pulseSongs)
}

type eventTheme struct {
	Name   string
	Songs  []string
	Titles []string
}

var weeklyThemes = []eventTheme{
	{"PULSE", pulseSongs, pulseTitles},
	{"GLOW UP", []string{"d668154fdb09", "cbee07ca71b1", "bae48c05e24a", "c9c8615ddffc", "b3d56a546b73"}, []string{"Cotton Candy", "CRASH", "Glow Up", "Going on", "In my lotion"}},
	{"lip bomb", []string{"63e0fd3215f1", "6ba02500273b", "a844b0766b06", "ef9458174e5a"}, []string{"Bloom", "Hello XO", "Love Echo", "MVP"}},
	{"SCENEDROME", []string{"d156b3488eee", "b7f81b591f14", "6026c854cdd9", "57e8df8f93bf"}, []string{"LOVE ATTACK", "Lucky you", "New World", "Pinball"}},
}

func weeklyTheme(start time.Time) eventTheme {
	epoch := time.Date(2026, 11, 9, 0, 0, 0, 0, time.UTC)
	weeks := int(start.Sub(epoch) / (7 * 24 * time.Hour))
	index := ((weeks % len(weeklyThemes)) + len(weeklyThemes)) % len(weeklyThemes)
	return weeklyThemes[index]
}
func weeklyEventID(start time.Time) string { return "weekly_" + start.Format("2006-01-02") }
func weeklyFeatured(start, now time.Time) int {
	day := int(now.Sub(start) / (24 * time.Hour))
	if day < 0 {
		day = 0
	}
	theme := weeklyTheme(start)
	return day % len(theme.Songs)
}
func themeContains(theme eventTheme, song string) bool {
	for _, v := range theme.Songs {
		if v == song {
			return true
		}
	}
	return false
}
func eventTickets(song string, now time.Time) []eventTicket {
	tickets := []eventTicket{}
	if pulseSong(song) && !now.Before(pulseEventStart) && now.Before(pulseEventEnd) {
		tickets = append(tickets, eventTicket{ID: pulseEventID, Featured: song == pulseSongs[featuredPulse(now)]})
	}
	start := weekStart(now)
	theme := weeklyTheme(start)
	if themeContains(theme, song) {
		tickets = append(tickets, eventTicket{ID: weeklyEventID(start), Featured: song == theme.Songs[weeklyFeatured(start, now)]})
	}
	return tickets
}
func eventState(p *progression) *eventProgress { return eventStateID(p, pulseEventID) }
func eventStateID(p *progression, id string) *eventProgress {
	if p.Events == nil {
		p.Events = map[string]*eventProgress{}
	}
	e := p.Events[id]
	if e == nil {
		e = &eventProgress{}
		p.Events[id] = e
	}
	if e.Songs == nil {
		e.Songs = map[string]bool{}
	}
	if e.Claimed == nil {
		e.Claimed = map[string]bool{}
	}
	return e
}

// Called only after replay verification and the clear threshold, in the same CAS
// as the run receipt. Tickets lock the featured song at start, across rotation.
func advanceEvents(p *progression, run runTicket, result runResult, now time.Time) {
	started := time.UnixMilli(run.StartedAt)
	for _, ticket := range run.Events {
		eligible := false
		if ticket.ID == pulseEventID {
			eligible = pulseSong(run.SongID) && !started.Before(pulseEventStart) && started.Before(pulseEventEnd) && now.Before(pulseClaimEnd)
		}
		if ticket.ID == weeklyEventID(weekStart(started)) {
			week := weekStart(started)
			eligible = themeContains(weeklyTheme(week), run.SongID) && now.Before(week.Add(9*24*time.Hour))
		}
		if !eligible {
			continue
		}
		e := eventStateID(p, ticket.ID)
		e.Clears = min(5, e.Clears+1)
		if ticket.Featured {
			e.Featured = min(3, e.Featured+1)
		}
		e.Perfect = min(1000, e.Perfect+int64(result.Counts["PERFECT"]))
		if result.Counts["MISS"] == 0 {
			e.FullCombos = 1
		}
		e.Songs[run.SongID] = true
	}
}
func weeklyMissions(p progression, id string, start, now time.Time) []eventMission {
	e := eventStateID(&p, id)
	m := []eventMission{
		{ID: "weekly_clears", Name: "Scene by scene", Description: "Clear 3 songs from this week's featured album. Repeats count.", Target: 3, Progress: e.Clears, XP: 150, Starlight: 75},
		{ID: "weekly_perfect", Name: "Perfect moments", Description: "Earn 300 PERFECT judgments in cleared featured-album songs.", Target: 300, Progress: e.Perfect, XP: 150, Starlight: 75},
	}
	for i := range m {
		m[i].Progress = min(m[i].Progress, m[i].Target)
		m[i].Claimed = e.Claimed[m[i].ID]
		m[i].Claimable = !m[i].Claimed && m[i].Progress >= m[i].Target && !now.Before(start) && now.Before(start.Add(9*24*time.Hour))
	}
	return m
}
func weeklyView(p progression, start, now time.Time) fiber.Map {
	theme := weeklyTheme(start)
	index := weeklyFeatured(start, now)
	status := "active"
	if !now.Before(start.Add(9 * 24 * time.Hour)) {
		status = "ended"
	} else if !now.Before(start.Add(7 * 24 * time.Hour)) {
		status = "claiming"
	}
	rotate := start.Add(time.Duration(int(now.Sub(start)/(24*time.Hour))+1) * 24 * time.Hour)
	rotate = minTime(rotate, start.Add(7*24*time.Hour))
	id := weeklyEventID(start)
	return fiber.Map{"id": id, "name": theme.Name + " / Weekly Spotlight", "subtitle": "A new scene every week.", "set_id": songSets[theme.Songs[0]], "status": status, "starts_at": start.Format(time.RFC3339), "ends_at": start.Add(7 * 24 * time.Hour).Format(time.RFC3339), "claim_ends_at": start.Add(9 * 24 * time.Hour).Format(time.RFC3339), "featured_song_id": theme.Songs[index], "featured_title": theme.Titles[index], "rotation_at": rotate.Format(time.RFC3339), "missions": weeklyMissions(p, id, start, now), "rules": "Clear songs from this week's featured album with at least 50% accuracy. Verified, unpaused attempts count. Start before the weekly reset; finish and sync within two hours. Rewards can be claimed for 48 hours after the event ends."}
}
func eventMissions(p progression, now time.Time) []eventMission {
	e := eventState(&p)
	m := []eventMission{
		{ID: "opening", Name: "Your PULSE begins", Description: "Clear a PULSE song.", Target: 1, Progress: e.Clears, XP: 100, Starlight: 50},
		{ID: "encore", Name: "Five little encores", Description: "Clear 5 PULSE songs. Repeats count.", Target: 5, Progress: e.Clears, XP: 250, Starlight: 100, Shards: 1},
		{ID: "featured", Name: "In the spotlight", Description: "Clear the featured song 3 times. The spotlight rotates daily.", Target: 3, Progress: e.Featured, XP: 200, Starlight: 100, Shards: 1},
		{ID: "perfect", Name: "A thousand perfect moments", Description: "Collect 1,000 PERFECT judgments in cleared PULSE songs.", Target: 1000, Progress: e.Perfect, XP: 300, Starlight: 150, Shards: 2},
		{ID: "harmony", Name: "Perfect harmony", Description: "Full combo any PULSE song. Any difficulty counts.", Target: 1, Progress: e.FullCombos, XP: 250, Starlight: 100, Shards: 1},
		{ID: "album", Name: "Every side of PULSE", Description: "Clear all 5 different PULSE songs.", Target: 5, Progress: int64(len(e.Songs)), XP: 400, Starlight: 200, Shards: 2},
	}
	complete := int64(0)
	for _, mission := range m {
		if mission.Progress >= mission.Target {
			complete++
		}
	}
	m = append(m, eventMission{ID: "finale", Name: "The first scene, complete", Description: "Complete all 6 event missions.", Target: 6, Progress: complete, XP: 500, Starlight: 250, Shards: 3})
	for i := range m {
		m[i].Progress = min(m[i].Progress, m[i].Target)
		m[i].Claimed = e.Claimed[m[i].ID]
		m[i].Claimable = !m[i].Claimed && m[i].Progress >= m[i].Target && !now.Before(pulseEventStart) && now.Before(pulseClaimEnd)
	}
	return m
}
func eventsView(p progression, now time.Time) []fiber.Map {
	status := "active"
	if now.Before(pulseEventStart) {
		status = "upcoming"
	} else if !now.Before(pulseClaimEnd) {
		status = "ended"
	} else if !now.Before(pulseEventEnd) {
		status = "claiming"
	}
	index := featuredPulse(now)
	rotation := pulseEventStart.Add(time.Duration(int64(now.Sub(pulseEventStart)/(24*time.Hour))+1) * 24 * time.Hour)
	if now.Before(pulseEventStart) {
		rotation = pulseEventStart.Add(24 * time.Hour)
	}
	rotation = minTime(rotation, pulseEventEnd)
	pulse := fiber.Map{"id": pulseEventID, "name": "PULSE / The First Scene", "subtitle": "With you, in every beat.", "set_id": "pulse", "status": status, "starts_at": pulseEventStart.Format(time.RFC3339), "ends_at": pulseEventEnd.Format(time.RFC3339), "claim_ends_at": pulseClaimEnd.Format(time.RFC3339), "featured_song_id": pulseSongs[index], "featured_title": pulseTitles[index], "rotation_at": rotation.Format(time.RFC3339), "missions": eventMissions(p, now), "rules": "Clear PULSE songs with at least 50% accuracy. Verified, unpaused attempts count on any difficulty. Start before the event ends; finish and sync within 2 hours. Featured credit uses the spotlight at song start. Claim rewards before the claim deadline.", "refinement_item_id": "prism_shards", "refinement_item_name": "Prism Shards ×10"}
	views := []fiber.Map{}
	if status != "ended" {
		views = append(views, pulse)
	}
	start := weekStart(now)
	views = append(views, weeklyView(p, start, now))
	previous := start.Add(-7 * 24 * time.Hour)
	if now.Before(start.Add(48*time.Hour)) && p.Events[weeklyEventID(previous)] != nil {
		views = append(views, weeklyView(p, previous, now))
	}
	if status == "ended" {
		views = append(views, pulse)
	}
	return views
}
func minTime(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}
func (a *api) getEvents(c fiber.Ctx) error {
	store, ok := a.store.(progressStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	p, _, err := store.ReadProgress(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	return c.JSON(fiber.Map{"server_time": now.Format(time.RFC3339Nano), "events": eventsView(p, now)})
}
func (a *api) claimEvent(c fiber.Ctx) error {
	var body struct{}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	id := c.Params("event")
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		var milestones []eventMission
		if id == pulseEventID {
			milestones = eventMissions(*p, now)
		} else if len(id) == 17 && id[:7] == "weekly_" {
			start, err := time.Parse("2006-01-02", id[7:])
			if err != nil || !start.Equal(weekStart(start)) || now.Before(start) || !now.Before(start.Add(9*24*time.Hour)) {
				return nil, progressError{404, "Event not found or expired."}
			}
			milestones = weeklyMissions(*p, id, start, now)
		} else {
			return nil, progressError{404, "Event not found."}
		}
		for _, m := range milestones {
			if m.ID != c.Params("mission") {
				continue
			}
			if m.Claimed {
				return fiber.Map{"event_id": id, "mission_id": m.ID, "already_claimed": true}, nil
			}
			if !m.Claimable {
				return nil, badProgress("Complete this mission and claim during the event reward window.")
			}
			if m.Shards > 0 && a.eventRewards == nil {
				return nil, progressError{503, "Item rewards are reconnecting. Your reward is safe; please retry shortly."}
			}
			eventStateID(p, id).Claimed[m.ID] = true
			p.XP += int64(m.XP)
			p.Starlight += int64(m.Starlight)
			if m.Shards > 0 {
				p.eventItems = int64(m.Shards)
				p.eventItemTarget = a.eventRewards.target
			}
			return fiber.Map{"event_id": id, "mission_id": m.ID, "xp": m.XP, "starlight": m.Starlight, "shards": m.Shards, "item_delivery": map[bool]string{true: "pending", false: "none"}[m.Shards > 0]}, nil
		}
		return nil, progressError{404, "Event mission not found."}
	})
}
