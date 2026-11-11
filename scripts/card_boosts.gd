class_name CardBoosts
extends RefCounted
signal skill_activated(skill_name: String, description: String)

## Shared integer scoring rules with backend/card_skills.go. Never changes timing.
var card: Dictionary = {}
var offset: int = 0
var streak: int = 0
var used_wind: bool = false
var encore_announced: bool = false
var overdrive_active: bool = false

func setup(value: Dictionary) -> void:
	card = value.duplicate(true)
	offset = rank(1) * 4
	streak = 0
	used_wind = false
	encore_announced = false
	overdrive_active = false

func rank(skill: int) -> int:
	var skills: Array = StrictData.array(card.get("skills", []))
	if StrictData.integer(card.get("version", 0)) != 2 or skills.size() <= skill: return 0
	return clampi(StrictData.integer(skills[skill]), 0, 5)

func miss() -> void:
	overdrive_active = false
	offset = 0
	streak = 0

func hit(weight: int, combo: int, is_head: bool, completed_units: int, perfect_sustain: bool, time: float, duration: float, life_milli: int) -> Vector2i:
	var multiplier: int = RhythmMomentum.multiplier(combo + offset)
	var bonus: int = 0
	var heal: int = 0
	if is_head: streak = streak + 1 if weight == 10 else 0
	if StrictData.integer(card.get("version", 0)) == 2 and weight == 10:
		bonus = StrictData.integer(card.get("perfect_score_bp", 0))
		if is_head:
			heal = StrictData.integer(card.get("recovery_ppm", 0))
			var spotlight: int = rank(2)
			if spotlight > 0 and streak > 0 and streak % 30 == 0:
				bonus += [300, 350, 400, 450, 500][spotlight - 1]
				skill_activated.emit("Spotlight", "30 PERFECT hits · score boosted")
			var wind: int = rank(3)
			if wind > 0 and not used_wind and life_milli <= 300000 and streak >= [15, 14, 13, 12, 10][wind - 1]:
				heal += [30000, 35000, 40000, 45000, 50000][wind - 1]
				used_wind = true
				skill_activated.emit("Second Wind", "PERFECT streak · life restored")
		var encore: int = rank(4)
		if encore > 0 and duration > 0.0 and time >= duration * 0.8:
			bonus += [100, 150, 200, 250, 300][encore - 1]
			if not encore_announced:
				encore_announced = true
				skill_activated.emit("Encore", "Final stretch · PERFECT score boosted")
		var overdrive: int = rank(6)
		if overdrive > 0 and multiplier == 5:
			bonus += [50, 75, 100, 125, 150][overdrive - 1]
			if not overdrive_active:
				overdrive_active = true
				skill_activated.emit("Overdrive", "5× momentum · PERFECT score boosted")
		elif multiplier < 5: overdrive_active = false
	var points: int = weight * multiplier * (10000 + bonus)
	var resonance: int = rank(5)
	if resonance > 0 and completed_units > 1 and perfect_sustain and weight == 10:
		points += 10 * multiplier * completed_units * [200, 250, 300, 350, 400][resonance - 1]
		skill_activated.emit("Resonance", "Perfect hold · extra score")
	return Vector2i(points, heal)

static func final_score(_base: int, points: int, units: int) -> int:
	return clampi(roundi(1000000.0 * points / float(maxi(1, RhythmMomentum.budget(units)) * 10 * 10000)), 0, 1000000)

static func score_trace(trace: String, units: int, value: Dictionary) -> int:
	var battle: CardBoosts = CardBoosts.new()
	battle.setup(value)
	var combo: int = 0
	var points: int = 0
	for index: int in trace.length():
		var unit: String = trace[index]
		if unit == "M": combo = 0; battle.miss(); continue
		combo += 1
		var weight: int = StrictData.integer({"P":10, "R":8, "G":5}.get(unit, 0))
		points += battle.hit(weight, combo, true, 0, false, float(index), float(units), 1000000).x
	return final_score(0, points, units)

static func combined(cards: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {"id":"pulse_team", "version":2, "perfect_score_bp":0, "recovery_ppm":0, "skills":[0, 0, 0, 0, 0, 0, 0]}
	for value: Dictionary in cards:
		result.perfect_score_bp = StrictData.integer(result.perfect_score_bp) + StrictData.integer(value.get("perfect_score_bp", 0))
		result.recovery_ppm = StrictData.integer(result.recovery_ppm) + StrictData.integer(value.get("recovery_ppm", 0))
		var skills: Array = StrictData.array(value.get("skills", []))
		for index: int in mini(7, skills.size()): result.skills[index] = maxi(StrictData.integer(result.skills[index]), StrictData.integer(skills[index]))
	result.perfect_score_bp = mini(6000, StrictData.integer(result.perfect_score_bp))
	result.recovery_ppm = mini(6000, StrictData.integer(result.recovery_ppm))
	return result
