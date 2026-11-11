extends SceneTree

func _initialize() -> void:
	var file: FileAccess = FileAccess.open("res://tests/fixtures/card_score_vectors.json", FileAccess.READ)
	if file == null: push_error("Missing shared server score vectors"); quit(1); return
	var values: Array = StrictData.array(JSON.parse_string(file.get_as_text()))
	var failures: int = 0
	for value: Variant in values:
		var sample: Dictionary = StrictData.dictionary(value)
		var trace: String = str(sample.trace)
		var card: Dictionary = StrictData.dictionary(sample.card)
		var units: int = StrictData.integer(sample.units)
		var expected: int = StrictData.integer(sample.score)
		var judge: RhythmJudge = RhythmJudge.new()
		judge.total_units = units; judge.card_loadout = card; judge._duration = float(units)
		for index: int in trace.length():
			var unit: String = trace[index]
			judge._time_us = index * 1000000
			if unit == "M": judge._miss({"state":0, "lane":0.0, "id":0}, 1)
			else:
				var kind: String = str({"P":"PERFECT", "R":"GREAT", "G":"GOOD"}.get(unit, "PERFECT"))
				var quality: float = StrictData.number({"P":1.0, "R":0.8, "G":0.5}.get(unit, 1.0))
				judge._record(kind, 0.0, quality, 0)
		if judge.score() != expected or CardBoosts.score_trace(trace, units, card) != expected:
			failures += 1; push_error("Client/server card score mismatch for " + str(card.id))
	var contexts_file: FileAccess = FileAccess.open("res://tests/fixtures/card_skill_vectors.json", FileAccess.READ)
	if contexts_file == null: push_error("Missing skill context vectors"); quit(1); return
	var contexts: Array = StrictData.array(JSON.parse_string(contexts_file.get_as_text()))
	var context_steps: int = 0
	for value: Variant in contexts:
		var sample: Dictionary = StrictData.dictionary(value)
		var battle: CardBoosts = CardBoosts.new(); battle.setup(StrictData.dictionary(sample.card))
		for raw: Variant in StrictData.array(sample.steps):
			var step: Dictionary = StrictData.dictionary(raw)
			var result: Vector2i = Vector2i.ZERO
			if StrictData.boolean(step.get("miss", false)): battle.miss()
			else: result = battle.hit(StrictData.integer(step.weight), StrictData.integer(step.combo), StrictData.boolean(step.head), StrictData.integer(step.complete), StrictData.boolean(step.perfect), StrictData.number(step.time), StrictData.number(step.duration), StrictData.integer(step.life))
			context_steps += 1
			if result.x != StrictData.integer(step.points) or result.y != StrictData.integer(step.heal) or battle.offset != StrictData.integer(step.offset) or battle.streak != StrictData.integer(step.streak) or battle.used_wind != StrictData.boolean(step.used):
				failures += 1; push_error("Server/client skill context mismatch")
	print("Skill context vectors: ", context_steps, " steps: ", "PASS" if failures == 0 else "FAIL")
	print("Shared server/client card score vectors: ", values.size(), " cases: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
