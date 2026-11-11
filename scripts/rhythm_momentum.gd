class_name RhythmMomentum
extends RefCounted
## Shared combo thresholds; score weights remain integers until final rounding.

const SCORING_ID: String = "momentum-v1"
const THRESHOLDS: Array[int] = [20, 40, 60]
const MULTIPLIERS: Array[int] = [1, 2, 3, 5]
const COLORS: Array[Color] = [Color("c7bbff"), Color("99d8ee"), Color("b09bff"), Color("eea3d3")]

static func tier(combo: int) -> int:
	if combo >= THRESHOLDS[2]: return 3
	if combo >= THRESHOLDS[1]: return 2
	if combo >= THRESHOLDS[0]: return 1
	return 0

static func multiplier(combo: int) -> int:
	return MULTIPLIERS[tier(combo)]

static func budget(units: int) -> int:
	# 1..19 at 1x, 20..39 at 2x, 40..59 at 3x, then 5x.
	return mini(units, 19) + mini(maxi(0, units - 19), 20) * 2 + mini(maxi(0, units - 39), 20) * 3 + maxi(0, units - 59) * 5

static func color(level: float) -> Color:
	var stage: float = clampf(level, 0.0, 3.0)
	var index: int = mini(floori(stage), 2)
	return COLORS[index].lerp(COLORS[index + 1], stage - float(index))
