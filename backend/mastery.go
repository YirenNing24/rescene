package main

import (
	"github.com/gofiber/fiber/v3"
	"math"
	"time"
)

type songMastery struct {
	Clears       map[string]bool `json:"clears"`
	BestAccuracy int             `json:"best_accuracy"` // hundredths of a percent
	FullCombo    bool            `json:"full_combo"`
	Claimed      map[string]bool `json:"claimed"`
}
type masteryMilestone struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Complete    bool   `json:"complete"`
	Claimed     bool   `json:"claimed"`
	XP          int    `json:"xp"`
	Starlight   int    `json:"starlight"`
	Shards      int    `json:"shards"`
}

func masteryState(p *progression, song string) *songMastery {
	if p.Mastery == nil {
		p.Mastery = map[string]*songMastery{}
	}
	m := p.Mastery[song]
	if m == nil {
		m = &songMastery{}
		p.Mastery[song] = m
	}
	if m.Clears == nil {
		m.Clears = map[string]bool{}
	}
	if m.Claimed == nil {
		m.Claimed = map[string]bool{}
	}
	return m
}
func advanceMastery(p *progression, run runTicket, counts map[string]int, accuracy int) {
	m := masteryState(p, run.SongID)
	m.Clears[run.Difficulty] = true
	m.BestAccuracy = max(m.BestAccuracy, accuracy/100)
	if counts["MISS"] == 0 {
		m.FullCombo = true
	}
}
func masteryMilestones(m *songMastery) []masteryMilestone {
	if m == nil {
		m = &songMastery{}
	}
	result := []masteryMilestone{
		{ID: "easy", Name: "Opening note", Description: "Clear Easy.", Complete: m.Clears["Easy"], XP: 40, Starlight: 20},
		{ID: "normal", Name: "Finding the rhythm", Description: "Clear Normal.", Complete: m.Clears["Normal"], XP: 60, Starlight: 30},
		{ID: "hard", Name: "In the spotlight", Description: "Clear Hard.", Complete: m.Clears["Hard"], XP: 80, Starlight: 40},
		{ID: "ultra_hard", Name: "A brighter stage", Description: "Clear Ultra Hard.", Complete: m.Clears["Ultra Hard"], XP: 120, Starlight: 60},
		{ID: "accuracy", Name: "Every beat", Description: "Clear with at least 90% accuracy on any difficulty.", Complete: m.BestAccuracy >= 9000, XP: 80, Starlight: 40},
		{ID: "full_combo", Name: "Perfect harmony", Description: "Full combo any difficulty.", Complete: m.FullCombo, XP: 100, Starlight: 50, Shards: 1},
	}
	for i := range result {
		result[i].Claimed = m.Claimed[result[i].ID]
	}
	return result
}
func masteredSongs(p progression) int {
	count := 0
	for _, state := range p.Mastery {
		all := true
		for _, m := range masteryMilestones(state) {
			if !m.Complete {
				all = false
				break
			}
		}
		if all {
			count++
		}
	}
	return count
}
func masteryView(p progression, song string) fiber.Map {
	state := p.Mastery[song]
	if state == nil {
		state = &songMastery{}
	}
	milestones := masteryMilestones(state)
	complete, claimed := 0, 0
	for _, m := range milestones {
		if m.Complete {
			complete++
		}
		if m.Claimed {
			claimed++
		}
	}
	return fiber.Map{"song_id": song, "milestones": milestones, "completed": complete, "claimed": claimed, "total": len(milestones), "best_accuracy": state.BestAccuracy, "full_combo": state.FullCombo}
}

// Only the current verified personal-best records can be recovered for older
// players. Claims and outcomes absent from those records are never invented.
func seedMastery(p *progression, records []personalBest) {
	for _, b := range records {
		chart, ok := rewardCharts[b.SongID+"/"+b.Difficulty]
		if !ok || b.Revision != chart.Revision || b.Verification != 2 {
			continue
		}
		m := masteryState(p, b.SongID)
		m.Clears[b.Difficulty] = true
		m.BestAccuracy = max(m.BestAccuracy, int(math.Round(b.Accuracy*100)))
		if chart.Units > 0 && b.MaxCombo == chart.Units {
			m.FullCombo = true
		}
	}
	p.MasterySeeded = true
}
func validMasterySong(song string) bool {
	for _, chart := range rewardCharts {
		if chart.SongID == song {
			return true
		}
	}
	return false
}
func (a *api) getMastery(c fiber.Ctx) error {
	song := c.Params("song")
	if !validMasterySong(song) {
		return fiber.ErrNotFound
	}
	store, ok := a.store.(progressStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	p, _, err := store.ReadProgress(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	if !p.MasterySeeded {
		if scores, available := a.store.(scoreStore); available {
			bests, e := scores.ReadBests(c.Locals("user").(user).ID)
			if e != nil {
				return e
			}
			seedMastery(&p, bests)
		}
	}
	return c.JSON(fiber.Map{"mastery": masteryView(p, song)})
}
func (a *api) claimMastery(c fiber.Ctx) error {
	var body struct{}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	song, mission := c.Params("song"), c.Params("mission")
	if !validMasterySong(song) {
		return fiber.ErrNotFound
	}
	return a.mutateProgress(c, func(p *progression, _ time.Time) (any, error) {
		if !p.MasterySeeded {
			if scores, available := a.store.(scoreStore); available {
				bests, e := scores.ReadBests(c.Locals("user").(user).ID)
				if e != nil {
					return nil, e
				}
				seedMastery(p, bests)
			}
		}
		state := masteryState(p, song)
		for _, m := range masteryMilestones(state) {
			if m.ID != mission {
				continue
			}
			if m.Claimed {
				return fiber.Map{"song_id": song, "mission_id": mission, "already_claimed": true}, nil
			}
			if !m.Complete {
				return nil, badProgress("Complete this mastery milestone first.")
			}
			if m.Shards > 0 && a.eventRewards == nil {
				return nil, progressError{503, "Item delivery is reconnecting. Please try again shortly."}
			}
			state.Claimed[m.ID] = true
			p.XP += int64(m.XP)
			p.Starlight += int64(m.Starlight)
			if m.Shards > 0 {
				p.eventItems = int64(m.Shards)
				p.eventItemTarget = a.eventRewards.target
			}
			return fiber.Map{"song_id": song, "mission_id": mission, "xp": m.XP, "starlight": m.Starlight, "shards": m.Shards}, nil
		}
		return nil, progressError{404, "Mastery milestone not found."}
	})
}
