extends SceneTree
## Headless coverage of chart compatibility, timing windows, holds and curved tracing.

var failures: int = 0
var charts_checked: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var legacy: Dictionary = RhythmChart.normalize({"tempo": 120, "tracks": [{"bars": [
		{"quarters_count": 4, "notes": [{"pos": 280, "len": 70}]},
		{"quarters_count": 4, "notes": [{"pos": 0, "len": 560}]}]}]})
	check(is_equal_approx(StrictData.number(legacy.notes[0].time), 0.5), "Legacy 280 ticks must equal one beat")
	check(is_equal_approx(StrictData.number(legacy.notes[1].time), 2.0), "Bar positions must accumulate")
	check(StrictData.boolean(legacy.notes[1].kind == "hold" and is_equal_approx(StrictData.number(legacy.notes[1].duration), 1.0)), "Legacy long-note lengths must survive conversion")
	for offset: float in [0.0, 0.07, 0.13]:
		var judge: RhythmJudge = RhythmJudge.new()
		judge.setup(fixture("tap"))
		var _bool_1: bool = judge.press(0, 0.0, 1.0 + offset)
		var expected: String = "PERFECT" if offset == 0.0 else ("GREAT" if offset < 0.1 else "GOOD")
		check(StrictData.boolean(judge.counts[expected] == 1), "Timing grade " + expected)
		check(judge.trace.length()==1,"A tap records exactly one ordered scoring judgment")
		var score: int = judge.score()
		var _bool_2: bool = judge.press(1, 0.0, 1.0 + offset)
		check(judge.score() == score, "A tap cannot be judged twice")
	var missed: RhythmJudge = RhythmJudge.new()
	missed.setup(fixture("tap"))
	check(not missed.press(0, 0.0, 0.7), "Early presses must not consume notes")
	missed.step(1.2, 0.2)
	check(StrictData.boolean(missed.counts.MISS == 1 and missed.combo == 0), "Late notes must miss")
	for kind: String in ["hold", "slide"]:
		var judge: RhythmJudge = RhythmJudge.new()
		judge.setup(fixture(kind))
		var _bool_3: bool = judge.press(0, 0.0, 1.0)
		for step: int in range(201):
			var t: float = 1.0 + step * 0.01
			judge.move_pointer(0, RhythmChart.lane_at(judge.notes[0], t))
			judge.step(t, 0.01)
		judge.finish()
		check(StrictData.boolean(judge.score() == 1000000 and judge.counts.MISS == 0), "Correct " + kind + " must award all checkpoints")
		check(judge.resolved_units == judge.total_units, "Sustains cannot duplicate scoring units")
		check(judge.trace=="P".repeat(judge.total_units),"Sustain trace includes every scoring checkpoint")
	var broken: RhythmJudge = RhythmJudge.new()
	broken.setup(fixture("hold"))
	var _bool_4: bool = broken.press(0, 0.0, 1.0)
	broken.release(0)
	for step: int in range(25): broken.step(1.0 + step * 0.01, 0.01)
	check(StrictData.boolean(broken.notes[0].state == 3 and broken.counts.MISS > 0), "Releasing a hold must break it")
	var stationary: RhythmJudge = RhythmJudge.new()
	stationary.setup(fixture("slide"))
	var _bool_5: bool = stationary.press(0, 0.0, 1.0)
	for step: int in range(201): stationary.step(1.0 + step * 0.01, 0.01)
	check(StrictData.boolean(stationary.notes[0].state == 3), "Holding the starting lane cannot complete a curved note")
	var keys: RhythmJudge = RhythmJudge.new()
	keys.setup(fixture("slide"))
	var _bool_6: bool = keys.press(-100, 0.0, 1.0, true)
	for step: int in range(201):
		var t: float = 1.0 + step * 0.01
		var lane: int = roundi(RhythmChart.lane_at(keys.notes[0], t))
		var _bool_7: bool = keys.press(-100 - lane, lane, t, true)
		keys.step(t, 0.01)
	keys.finish()
	check(keys.score() == 1000000, "Keyboard slides must support lane handoff")
	for song: Dictionary in SongCatalog.SONGS:
		var previous_count: int = 0
		for difficulty: String in ["Easy", "Normal", "Hard", "Ultra Hard"]:
			var chart: Dictionary = RhythmChart.load_chart(str(song.id), difficulty)
			check(not chart.is_empty(),str("Load chart: " + song.title + " / " + difficulty))
			if chart.is_empty(): continue
			charts_checked += 1
			check(absf(StrictData.number(chart.duration - song.playable_seconds)) < 0.01,str("Chart must end at half the song: " + song.title))
			var prior: float = -1.0
			var kinds: Dictionary = {"tap": 0, "hold": 0, "slide": 0, "swipe": 0}
			for note: Dictionary in chart.notes:
				check(StrictData.boolean(note.time >= prior and note.time >= 0.0), "Notes must be sorted and nonnegative")
				check(StrictData.boolean(note.time + note.duration <= chart.duration), "No note can extend past the audio cutoff")
				check(StrictData.boolean(note.lane >= 0 and note.lane <= 4), "All notes must fit five lanes")
				kinds[note.kind] += 1
				prior = note.time
			check(StrictData.boolean(kinds.tap > 0 and kinds.hold > 0 and kinds.slide > 0 and kinds.swipe > 0), "Every chart needs all four note mechanics")
			check(StrictData.array(chart.notes).size() >= previous_count,str("Higher difficulties must add density: " + song.title))
			previous_count = StrictData.array(chart.notes).size()
			# Auto-trace representative charts across all difficulty levels.
			if str(song.title).to_upper() in ["LOVE ATTACK", "GLOW UP"]: autoplay(chart)
	verify_collection_lenience()
	verify_records()
	verify_momentum()
	print("Rhythm core: ", charts_checked, " charts checked; ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(failures)

func verify_records() -> void:
	var existed: bool = FileAccess.file_exists(RhythmRecords.PATH)
	var song: Dictionary = {"id": "__test_" + str(Time.get_ticks_usec()), "title": "Regression record"}
	var result: Dictionary = {"score": 750000, "accuracy": 75.0, "rank": "B", "max_combo": 24}
	RhythmRecords.save(song, "Hard", result)
	check(StrictData.boolean(RhythmRecords.best(str(song.id), "Hard").score == 750000), "Personal best must survive disk reload")
	result.score = 500000
	RhythmRecords.save(song, "Hard", result)
	check(StrictData.boolean(RhythmRecords.best(str(song.id), "Hard").score == 750000), "A lower score cannot replace a personal best")
	check(RhythmRecords.best(str(song.id), "Easy").is_empty(), "Difficulty records must remain separate")
	result.score = 900000
	RhythmRecords.save(song, "Hard", result)
	check(StrictData.boolean(RhythmRecords.best(str(song.id), "Hard").score == 900000), "A better score must replace the record")
	check(not RhythmRecords.all_scores().is_empty(), "Records panel must be able to enumerate saved scores")
	var config: ConfigFile = ConfigFile.new()
	var _error_8: Error = config.load(RhythmRecords.PATH)
	config.erase_section_key("scores", RhythmRecords.key(str(song.id), "Hard"))
	if not existed and (not config.has_section("scores") or config.get_section_keys("scores").is_empty()):
		var _error_9: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(RhythmRecords.PATH))
	else:
		var _error_10: Error = config.save(RhythmRecords.PATH)

func autoplay(chart: Dictionary) -> void:
	var judge: RhythmJudge = RhythmJudge.new()
	judge.setup(chart)
	preload("res://tests/replay_fixture.gd").autoplay(judge,chart)
	check(judge.score() == 1000000,str("Auto-traced chart must reach 1,000,000 / " + chart.difficulty))
	check(StrictData.boolean(judge.counts.MISS == 0 and judge.resolved_units == judge.total_units), "All chart notes must be completable")

func fixture(kind: String) -> Dictionary:
	var curve: Array = [{"at": 0.0, "lane": 0.0}, {"at": 0.5, "lane": 3.0}, {"at": 1.0, "lane": 1.0}] if kind == "slide" else []
	return RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400, "duration_seconds": 4,
		"tracks": [{"bars": [{"notes": [{"pos": 800, "len": 1600, "kind": kind, "curve": curve}]}]}]})

func verify_momentum() -> void:
	for combo: int in [19, 20, 39, 40, 59, 60]:
		var expected: int = {19: 1, 20: 2, 39: 2, 40: 3, 59: 3, 60: 5}[combo]
		check(RhythmMomentum.multiplier(combo) == expected, "Momentum threshold at %d" % combo)
	var judge: RhythmJudge = RhythmJudge.new()
	var taps: Array[Dictionary] = []
	for index: int in 100: taps.append({"pos": 800 + index * 200, "kind": "tap"})
	var chart: Dictionary = RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400, "duration_seconds": 27,
		"tracks": [{"bars": [{"notes": taps}]}]})
	judge.setup(chart)
	var last: int = 0
	for index: int in 100:
		var points: int = judge.momentum_points
		var note: Dictionary = judge.notes[index]
		check(judge.press(0, 0.0, StrictData.number(note.time)), "Momentum fixture note must hit")
		judge.release(0)
		check(judge.momentum_points - points == 10 * RhythmMomentum.multiplier(index + 1), "Milestone note must earn the new multiplier")
		check(judge.score() >= last, "Momentum score must increase monotonically")
		last = judge.score()
	check(judge.score() == 1000000 and judge.accuracy() == 100.0, "A perfect full combo must score exactly one million")
	judge.setup(chart)
	for index: int in 21:
		var note: Dictionary = judge.notes[index]
		if index == 19:
			judge.step(StrictData.number(note.time) + 0.2, 0.2)
			check(judge.combo == 0, "A miss must clear momentum immediately")
			continue
		var before: int = judge.momentum_points
		check(judge.press(0, 0.0, StrictData.number(note.time)), "Reset fixture note must hit")
		judge.release(0)
		if index == 20: check(judge.momentum_points - before == 10, "First note after a broken combo must earn 1x")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func verify_collection_lenience() -> void:
	for offset: float in [-0.175, -0.10, -0.055, 0.055, 0.10, 0.175]:
		var judge: RhythmJudge = RhythmJudge.new()
		judge.setup(fixture("tap"))
		check(judge.press(0, 0.70, 1.0 + offset), "Slight timing and finger drift still collect the note")
		var expected: String = "PERFECT" if absf(offset) < 0.06 else "GREAT" if absf(offset) < 0.105 else "GOOD"
		check(judge.counts[expected] == 1, "Lenient timing still awards the correct grade")
	for offset: float in [-0.19, 0.19]:
		var judge: RhythmJudge = RhythmJudge.new()
		judge.setup(fixture("tap"))
		check(not judge.press(0, 0.0, 1.0 + offset), "Presses outside the new window do not collect notes")
	var wrong_lane: RhythmJudge = RhythmJudge.new()
	wrong_lane.setup(fixture("tap"))
	check(not wrong_lane.press(0, 1.0, 1.0), "An adjacent lane does not collect the note")
	var hold: RhythmJudge = RhythmJudge.new()
	hold.setup(fixture("hold"))
	var _head: bool = hold.press(0, 0.70, 1.0)
	hold.move_pointer(0, -10.0, 1.01)
	hold.move_pointer(0, 0.70, 1.15)
	check(StrictData.integer(hold.notes[0].state) == 1, "A brief finger drift no longer breaks a hold")
	hold.move_pointer(0, -10.0, 1.16)
	hold.step(1.35, 0.19)
	check(StrictData.integer(hold.notes[0].state) == 3, "Leaving a hold still breaks it after the grace period")
