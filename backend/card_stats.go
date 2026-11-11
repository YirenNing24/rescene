package main

import "math"

const cardMaxLevel = 100
const cardMaxXP = 1000000 // Banked XP; levels are advanced only by resolved attempts.

type cardLoadout struct {
	ID             string `json:"id"`
	Level          int    `json:"level"`
	Version        int    `json:"version"`
	PerfectScoreBP int    `json:"perfect_score_bp,omitempty"`
	RecoveryPPM    int    `json:"recovery_ppm,omitempty"`
	Skills         [7]int `json:"skills,omitempty"`
	Member         int    `json:"member_index,omitempty"`
}
type cardMaterial struct {
	ID, Name  string
	TokenID   int64
	Price, XP int
}

var cardMaterials = []cardMaterial{
	{"prism_shards", "Prism Shards ×10", 11, 150, 100},
	{"resonance_core", "Resonance Cores ×3", 12, 300, 225},
	{"aurora_catalyst", "Aurora Catalyst", 13, 550, 450},
}

func materialByID(id string) (cardMaterial, bool) {
	for _, item := range cardMaterials {
		if item.ID == id {
			return item, true
		}
	}
	return cardMaterial{}, false
}
func effectiveCombo(combo int, card *cardLoadout) int {
	return combo + newCardBattle(card).offset
}
func cardPointsScore(points int64, units int) int {
	return min(1000000, max(0, int(math.Round(1000000*float64(points)/float64(max(1, momentumBudget(units))*10*10000)))))
}
func cardScore(trace string, units int, card *cardLoadout) int {
	battle := newCardBattle(card)
	combo := 0
	points := int64(0)
	for index, unit := range trace {
		if unit == 'M' {
			combo = 0
			battle.miss()
			continue
		}
		combo++
		weight := map[rune]int{'P': 10, 'R': 8, 'G': 5}[unit]
		earned, _ := battle.hit(weight, combo, true, 0, false, float64(index), float64(units), 1000000)
		points += earned
	}
	return cardPointsScore(points, units)
}
