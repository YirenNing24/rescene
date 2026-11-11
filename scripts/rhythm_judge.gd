class_name RhythmJudge
extends RefCounted
## Deterministic timing and sustain judge, independent of rendering/frame rate.

signal judged(label: String, lane: float, value: float, note_id: int)

const PERFECT_WINDOW: float = 0.045
const GREAT_WINDOW: float = 0.09
const HIT_WINDOW: float = 0.15
const TRACE_TOLERANCE: float = 0.62
const RELEASE_GRACE: float = 0.12
const REPLAY_VERSION: int = 3
const TICK_HZ: int = 120
const MAX_EVENTS: int = 24000

var notes: Array[Dictionary] = []
var pointers: Dictionary[int, Dictionary] = {}
var combo: int = 0
var max_combo: int = 0
var life: float = 1000.0
var earned: float = 0.0
var momentum_points: int = 0
var card_points: int = 0
var card_battle: CardBoosts = CardBoosts.new()
var card_loadout: Dictionary = {}:
	set(value):
		card_loadout = value
		card_battle.setup(value)
var total_units: int = 0
var resolved_units: int = 0
var counts: Dictionary[String, int] = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}
var trace: String = ""
var events: Array[Array] = []
var replay_overflow: bool = false
var paused: bool = false
var dead: bool = false
var _time_us: int = -150000
var _tick: int = -18
var _duration: float = 0.0
var _last_move_us: Dictionary[int, int] = {}


func setup(chart: Dictionary) -> void:
	notes.assign(StrictData.array(StrictData.array(chart.notes).duplicate(true)))
	pointers.clear()
	combo = 0
	max_combo = 0
	life = 1000.0
	earned = 0.0
	momentum_points = 0
	card_points = 0
	card_loadout = {}
	resolved_units = 0
	total_units = 0
	counts = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}
	trace = ""
	events.clear()
	replay_overflow = false
	paused = false
	dead = false
	_time_us = -150000
	_tick = -18
	_duration = StrictData.number(chart.duration)
	_last_move_us.clear()
	for note: Dictionary in notes:
		total_units += 1 + StrictData.array(note.checkpoints).size()


func press(pointer_id: int, lane: float, time: float, keyboard: bool = false) -> bool:
	_advance(time)
	if dead or pointers.has(pointer_id) or pointers.size() >= 10: return false
	keyboard = pointer_id <= -100
	lane = StrictData.number(roundi(lane * 10000.0)) / 10000.0
	_event(0, pointer_id, roundi(lane * 10000.0))
	time = StrictData.number(_time_us) / 1000000.0
	pointers[pointer_id] = {"lane": lane, "keyboard": keyboard}
	var best: Dictionary = {}
	var nearest: float = HIT_WINDOW + 0.001
	for note: Dictionary in notes:
		if note.state != 0 or absf(StrictData.number(note.lane - lane)) > TRACE_TOLERANCE:
			continue
		var difference: float = absf(StrictData.number(note.time - time))
		if difference <= HIT_WINDOW and difference < nearest:
			nearest = difference
			best = note
	if best.is_empty():
		# After a pause, a fresh OS touch index may take over the suspended ribbon.
		for note: Dictionary in notes:
			if note.state == 1 and note.get("regrab", false) and absf(RhythmChart.lane_at(note, time) - lane) <= TRACE_TOLERANCE:
				note.owner = pointer_id
				note.regrab = false
				note.gap = 0.0
				return true
		return false
	var label: String = "PERFECT" if nearest <= PERFECT_WINDOW else ("GREAT" if nearest <= GREAT_WINDOW else "GOOD")
	var value: float = 1.0 if label == "PERFECT" else (0.8 if label == "GREAT" else 0.5)
	_record(label,StrictData.number(best.lane), value,StrictData.integer(best.id))
	best.head_perfect = label == "PERFECT"
	if best.kind == "tap":
		best.state = 2
	else:
		best.state = 1
		best.owner = pointer_id
		best.gap = 0.0
	return true


func move_pointer(pointer_id: int, lane: float, time: float = -1.0) -> void:
	if time != -1.0: _advance(time)
	if pointers.has(pointer_id):
		lane = StrictData.number(roundi(lane * 10000.0)) / 10000.0
		if is_equal_approx(StrictData.number(pointers[pointer_id].lane), lane): return
		# Judge and capture the same bounded input stream, including gaming mice.
		if _last_move_us.has(pointer_id) and _time_us - StrictData.integer(_last_move_us[pointer_id]) < 8000: return
		_last_move_us[pointer_id] = _time_us
		_event(1, pointer_id, roundi(lane * 10000.0))
		pointers[pointer_id].lane = lane


func release(pointer_id: int, time: float = -1.0) -> void:
	if time != -1.0: _advance(time)
	if not pointers.has(pointer_id): return
	_event(2, pointer_id, 0)
	var _bool_1: bool = pointers.erase(pointer_id)
	var _bool_2: bool = _last_move_us.erase(pointer_id)


func step(time: float, _delta: float) -> void:
	_advance(time)


func _advance(time: float) -> void:
	var target: int = maxi(_time_us, roundi(time * 1000000.0))
	while (_tick + 1) * 1000000 <= target * TICK_HZ:
		_tick += 1
		_step_tick(StrictData.number(_tick) / TICK_HZ)
	_time_us = target


func _step_tick(time: float) -> void:
	if dead: return
	for note: Dictionary in notes:
		if note.time > time: break
		if note.state == 0 and time > note.time + HIT_WINDOW:
			_miss(note, 1 + StrictData.array(note.checkpoints).size())
		elif note.state == 1:
			var lane: float = RhythmChart.lane_at(note, time)
			var valid: bool = false
			if pointers.has(note.owner):
				valid = absf(StrictData.number(pointers[note.owner].lane) - lane) <= TRACE_TOLERANCE
			# Keyboard slides can hand off between adjacent held keys.
			if note.owner <= -100 and not valid:
				var ids: Array = pointers.keys()
				ids.sort()
				for id: int in ids:
					if pointers[id].keyboard and absf(StrictData.number(pointers[id].lane) - lane) <= TRACE_TOLERANCE:
						note.owner = id
						valid = true
						break
			if valid:
				note.gap = 0.0
			else:
				note.gap += 1.0 / TICK_HZ
			if note.gap > RELEASE_GRACE:
				_miss(note,StrictData.integer(StrictData.array(note.checkpoints).size() - note.next_tick))
				continue
			while note.next_tick < StrictData.array(note.checkpoints).size() and time >= note.checkpoints[note.next_tick]:
				var completed: int = 1 + StrictData.array(note.checkpoints).size() if note.next_tick == StrictData.array(note.checkpoints).size() - 1 else 0
				_record("PERFECT", lane, 1.0, StrictData.integer(note.id), false, completed, StrictData.boolean(note.get("head_perfect", false)), time)
				note.next_tick += 1
			if note.next_tick >= StrictData.array(note.checkpoints).size():
				note.state = 2
		if dead: break


func finish(time: float = -1.0) -> void:
	_advance(_duration if time == -1.0 else time)
	for note: Dictionary in notes:
		if note.state == 0:
			_miss(note, 1 + StrictData.array(note.checkpoints).size())
		elif note.state == 1:
			_miss(note,StrictData.integer(StrictData.array(note.checkpoints).size() - note.next_tick))
	pointers.clear()


func suspend(time: float) -> void:
	_advance(time)
	_event(3, 0, 0)
	paused = true
	pointers.clear()
	_last_move_us.clear()
	for note: Dictionary in notes:
		if note.state == 1:
			note.gap = -0.2
			note.regrab = true


func _event(kind: int, pointer_id: int, lane: int) -> void:
	if events.size() >= MAX_EVENTS:
		replay_overflow = true
		return
	events.append([_time_us, kind, pointer_id, lane])


func replay_payload(run_id: String, revision: String) -> Dictionary:
	return {"version":REPLAY_VERSION,"run_id":run_id,"revision":revision,"end_us":_time_us,"events":events.duplicate(true)} if not replay_overflow else {}


func base_score() -> int:
	return roundi(1000000.0 * momentum_points / (maxi(1, RhythmMomentum.budget(total_units)) * 10))

func score() -> int:
	return CardBoosts.final_score(base_score(), card_points, total_units)

func momentum_combo() -> int:
	return combo + card_battle.offset



func accuracy() -> float:
	if resolved_units == 0:
		return 100.0
	return earned / maxi(1, resolved_units) * 100.0


func rank() -> String:
	var percent: float = earned / maxi(1, total_units)
	if percent >= 0.98: return "S+"
	if percent >= 0.93: return "S"
	if percent >= 0.85: return "A"
	if percent >= 0.70: return "B"
	return "C"


func _miss(note: Dictionary, units: int) -> void:
	note.state = 3
	counts.MISS += maxi(0, units)
	trace += "M".repeat(maxi(0, units))
	resolved_units += maxi(0, units)
	combo = 0
	card_battle.miss()
	life = maxf(0.0, life - 45.0)
	if life <= 0.0: dead = true
	judged.emit("MISS", note.lane, 0.0, note.id)


func _record(label: String, lane: float, value: float, note_id: int, is_head: bool = true, completed_units: int = 0, perfect_sustain: bool = false, tick_time: float = -1.0) -> void:
	if dead: return
	counts[label] += 1
	trace += {"PERFECT":"P", "GREAT":"R", "GOOD":"G"}[label]
	resolved_units += 1
	earned += value
	combo += 1
	var weight: int = {"PERFECT": 10, "GREAT": 8, "GOOD": 5}[label]
	momentum_points += weight * RhythmMomentum.multiplier(combo)
	var earned_points: Vector2i = card_battle.hit(weight, combo, is_head, completed_units, perfect_sustain, float(_time_us) / 1000000.0 if tick_time < 0.0 else tick_time, _duration, roundi(life * 1000.0))
	card_points += earned_points.x
	max_combo = maxi(combo, max_combo)
	life = clampf(float(roundi((life + (5.0 if value >= 0.8 else -12.0) + float(earned_points.y) / 1000.0) * 1000.0)) / 1000.0, 0.0, 1000.0)
	if life <= 0.0: dead = true
	judged.emit(label, lane, value, note_id)
