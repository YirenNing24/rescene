package main

import (
	"encoding/json"
	"math/rand"
	"os"
	"strings"
	"testing"
)

func TestCardBalanceCapsAndNativeVectors(t *testing.T) {
	type vector struct {
		Trace string       `json:"trace"`
		Units int          `json:"units"`
		Card  *cardLoadout `json:"card"`
		Score int          `json:"score"`
	}
	vectors := []vector{}
	traces := []string{strings.Repeat("P", 100), strings.Repeat("R", 100), strings.Repeat("P", 19) + "M" + strings.Repeat("P", 80), strings.Repeat("P", 58) + "M" + strings.Repeat("P", 41), "PRGMPPRG" + strings.Repeat("P", 120)}
	random := rand.New(rand.NewSource(17))
	for range 50 {
		var trace strings.Builder
		for range 300 {
			trace.WriteByte("PPPPPRRGGM"[random.Intn(10)])
		}
		traces = append(traces, trace.String())
	}
	for skill := 0; skill <= 6; skill++ {
		for _, stars := range []int{1, 3, 5} {
			card := &cardLoadout{ID: "test", Version: 2, PerfectScoreBP: 1200, RecoveryPPM: 1200}
			card.Skills[skill] = stars
			for i, trace := range traces {
				score := cardScore(trace, len(trace), card)
				base := momentumScore(trace, len(trace))
				if score < base || score > 1000000 {
					t.Fatal("invalid card score cap")
				}
				if i < 5 {
					vectors = append(vectors, vector{trace, len(trace), card, score})
				}
			}
		}
	}
	basic := &cardLoadout{Version: 2, PerfectScoreBP: 1200, RecoveryPPM: 1200}
	if cardScore(strings.Repeat("R", 100), 100, basic) != momentumScore(strings.Repeat("R", 100), 100) {
		t.Fatal("Perfect Score boosted GREAT hits")
	}
	if os.Getenv("UPDATE_CARD_VECTORS") == "1" {
		body, _ := json.MarshalIndent(vectors, "", "  ")
		if err := os.WriteFile("../tests/fixtures/card_score_vectors.json", append(body, '\n'), 0644); err != nil {
			t.Fatal(err)
		}
	}
}
func TestFiveCardStatsAddAndDuplicateSkillsUseStrongest(t *testing.T) {
	var cards []*cardLoadout
	for i := 0; i < 5; i++ {
		card := &cardLoadout{Version: 2, PerfectScoreBP: 1200, RecoveryPPM: 1200}
		card.Skills[1] = i + 1
		cards = append(cards, card)
	}
	team := combinedPulseCards(cards)
	if team.PerfectScoreBP != 6000 || team.RecoveryPPM != 6000 || team.Skills[1] != 5 {
		t.Fatal("incorrect team combination")
	}
	battle := newCardBattle(team)
	if battle.offset != 20 {
		t.Fatal("duplicate Overture stacked starting bars")
	}
	battle.miss()
	if battle.offset != 0 {
		t.Fatal("momentum survived a miss")
	}
	points, heal := battle.hit(8, 1, true, 0, false, 0, 100, 500000)
	if points != 80000 || heal != 0 {
		t.Fatal("non-perfect hit received bonus/healing")
	}
	points, heal = battle.hit(10, 1, false, 0, false, 0, 100, 500000)
	if points != 160000 || heal != 0 {
		t.Fatal("sustain tick farmed recovery")
	}
	_, heal = battle.hit(10, 1, true, 0, false, 0, 100, 500000)
	if heal != 6000 {
		t.Fatal("combined perfect recovery incorrect")
	}
}
func TestCardSkillsBoundedAndStarStrengthMonotonic(t *testing.T) {
	for skill := 1; skill <= 6; skill++ {
		prior := int64(-1)
		for stars := 1; stars <= 5; stars++ {
			card := &cardLoadout{Version: 2}
			card.Skills[skill] = stars
			battle := newCardBattle(card)
			points := int64(0)
			for combo := 1; combo <= 90; combo++ {
				earned, heal := battle.hit(10, combo, true, 2, true, 95, 100, 200000)
				points += earned
				if heal > 50000 {
					t.Fatal("unbounded skill healing")
				}
			}
			if points < prior {
				t.Fatal("higher stars weakened a skill", skill, stars)
			}
			prior = points
		}
	}
	card := &cardLoadout{Version: 2}
	card.Skills[3] = 5
	battle := newCardBattle(card)
	bursts := 0
	for combo := 1; combo <= 100; combo++ {
		_, heal := battle.hit(10, combo, true, 0, false, 0, 100, 100000)
		if heal > 0 {
			bursts++
		}
	}
	if bursts != 1 {
		t.Fatal("Second Wind repeated within a song")
	}
}

func TestSharedSkillContextVectors(t *testing.T) {
	type step struct {
		Weight   int     `json:"weight"`
		Combo    int     `json:"combo"`
		Head     bool    `json:"head"`
		Complete int     `json:"complete"`
		Perfect  bool    `json:"perfect"`
		Time     float64 `json:"time"`
		Duration float64 `json:"duration"`
		Life     int     `json:"life"`
		Miss     bool    `json:"miss"`
		Points   int64   `json:"points"`
		Heal     int     `json:"heal"`
		Offset   int     `json:"offset"`
		Streak   int     `json:"streak"`
		Used     bool    `json:"used"`
	}
	type sample struct {
		Card  *cardLoadout `json:"card"`
		Steps []step       `json:"steps"`
	}
	samples := []sample{}
	for skill := 1; skill <= 6; skill++ {
		for _, stars := range []int{1, 5} {
			card := &cardLoadout{ID: "contexts", Version: 2, PerfectScoreBP: 1000, RecoveryPPM: 1000}
			card.Skills[skill] = stars
			battle := newCardBattle(card)
			frames := []step{}
			for i := 1; i <= 35; i++ {
				frames = append(frames, step{Weight: 10, Combo: i, Head: true, Time: float64(i), Duration: 100, Life: 100000})
			}
			for i := 1; i <= 20; i++ {
				frames = append(frames, step{Weight: 10, Combo: 35 + i, Head: false, Complete: 21 * map[bool]int{true: 1}[i == 20], Perfect: true, Time: float64(70 + i), Duration: 100, Life: 100000})
			}
			frames = append(frames, step{Miss: true}, step{Weight: 8, Combo: 1, Head: true, Time: 90, Duration: 100, Life: 100000}, step{Weight: 5, Combo: 2, Head: true, Time: 91, Duration: 100, Life: 100000})
			for i := 1; i <= 35; i++ {
				frames = append(frames, step{Weight: 10, Combo: 60 + i, Head: true, Time: 95, Duration: 100, Life: 100000})
			}
			for i := range frames {
				entry := &frames[i]
				if entry.Miss {
					battle.miss()
				} else {
					entry.Points, entry.Heal = battle.hit(entry.Weight, entry.Combo, entry.Head, entry.Complete, entry.Perfect, entry.Time, entry.Duration, entry.Life)
				}
				entry.Offset = battle.offset
				entry.Streak = battle.streak
				entry.Used = battle.usedWind
			}
			samples = append(samples, sample{card, frames})
		}
	}
	if os.Getenv("UPDATE_CARD_VECTORS") == "1" {
		body, _ := json.MarshalIndent(samples, "", "  ")
		if err := os.WriteFile("../tests/fixtures/card_skill_vectors.json", append(body, '\n'), 0644); err != nil {
			t.Fatal(err)
		}
	}
}
