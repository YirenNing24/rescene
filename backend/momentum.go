package main

import "math"

func momentumMultiplier(combo int) int {
	switch {
	case combo >= 60:
		return 5
	case combo >= 40:
		return 3
	case combo >= 20:
		return 2
	default:
		return 1
	}
}

func momentumBudget(units int) int {
	return min(units, 19) + min(max(0, units-19), 20)*2 + min(max(0, units-39), 20)*3 + max(0, units-59)*5
}

// Recompute the bonus from ordered judgments. Totals alone cannot prove a streak.
func momentumScore(trace string, units int) int {
	combo, points := 0, 0
	for _, unit := range trace {
		if unit == 'M' {
			combo = 0
			continue
		}
		combo++
		weight := map[rune]int{'P': 10, 'R': 8, 'G': 5}[unit]
		points += weight * momentumMultiplier(combo)
	}
	return int(math.Round(1000000 * float64(points) / float64(max(1, momentumBudget(units))*10)))
}
