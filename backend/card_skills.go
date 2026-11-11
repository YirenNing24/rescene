package main

import "fmt"

func pulseSkillDescription(skill, stars int) string {
	stars = max(1, min(5, stars))
	i := stars - 1
	switch skill {
	case 1:
		return fmt.Sprintf("Start with %d%% of the first momentum bar. Lost on the first miss.", []int{20, 40, 60, 80, 100}[i])
	case 2:
		return fmt.Sprintf("Every 30 consecutive PERFECT note heads: +%.1f%% score on that hit. Other judgments reset the streak.", float64([]int{300, 350, 400, 450, 500}[i])/100)
	case 3:
		return fmt.Sprintf("Once per song, at 30%% HP or below, %d consecutive PERFECT note heads restore %.1f%% max HP.", []int{15, 14, 13, 12, 10}[i], float64([]int{300, 350, 400, 450, 500}[i])/100)
	case 4:
		return fmt.Sprintf("PERFECT hits in the final 20%% of the song gain +%.1f%% score.", float64([]int{100, 150, 200, 250, 300}[i])/100)
	case 5:
		return fmt.Sprintf("Finish an unbroken hold/curve with a PERFECT head: +%.1f%% of that note's score.", float64([]int{200, 250, 300, 350, 400}[i])/100)
	case 6:
		return fmt.Sprintf("While at 5× momentum, PERFECT hits gain +%.2f%% score.", float64([]int{50, 75, 100, 125, 150}[i])/100)
	}
	return "No skill. Stars do not grant or reroll skills."
}

type cardBattle struct {
	card           *cardLoadout
	offset, streak int
	usedWind       bool
}

func newCardBattle(card *cardLoadout) *cardBattle {
	b := &cardBattle{card: card}
	if rank := b.rank(1); rank > 0 {
		b.offset = rank * 4
	}
	return b
}
func (b *cardBattle) rank(skill int) int {
	if b.card == nil || b.card.Version != 2 || len(b.card.Skills) <= skill {
		return 0
	}
	return max(0, min(5, b.card.Skills[skill]))
}
func (b *cardBattle) miss() { b.offset = 0; b.streak = 0 }

// Returns weighted score in basis-point units and extra healing in milli-HP.
// Only note heads heal/charge streaks; sustain ticks cannot farm either.
func (b *cardBattle) hit(weight, combo int, head bool, completedUnits int, perfectSustain bool, time, duration float64, lifeMilli int) (int64, int) {
	multiplier := momentumMultiplier(combo + b.offset)
	bonus, heal := 0, 0
	if head {
		if weight == 10 {
			b.streak++
		} else {
			b.streak = 0
		}
	}
	if b.card != nil && b.card.Version == 2 && weight == 10 {
		bonus = b.card.PerfectScoreBP
		if head {
			heal = b.card.RecoveryPPM
			if rank := b.rank(2); rank > 0 && b.streak > 0 && b.streak%30 == 0 {
				bonus += []int{300, 350, 400, 450, 500}[rank-1]
			}
			if rank := b.rank(3); rank > 0 && !b.usedWind && lifeMilli <= 300000 && b.streak >= []int{15, 14, 13, 12, 10}[rank-1] {
				heal += []int{30000, 35000, 40000, 45000, 50000}[rank-1]
				b.usedWind = true
			}
		}
		if rank := b.rank(4); rank > 0 && duration > 0 && time >= duration*0.8 {
			bonus += []int{100, 150, 200, 250, 300}[rank-1]
		}
		if rank := b.rank(6); rank > 0 && multiplier == 5 {
			bonus += []int{50, 75, 100, 125, 150}[rank-1]
		}
	}
	points := int64(weight * multiplier * (10000 + bonus))
	if rank := b.rank(5); rank > 0 && completedUnits > 1 && perfectSustain && weight == 10 {
		points += int64(10 * multiplier * completedUnits * []int{200, 250, 300, 350, 400}[rank-1])
	}
	return points, heal
}
