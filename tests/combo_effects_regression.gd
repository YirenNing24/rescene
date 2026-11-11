extends SceneTree
## Real judgment wiring, combo breaks and the milestone pool's pause/retry lifecycle.

var failures: int = 0
var stage: RhythmStage

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await create_timer(0.2).timeout
	menu._request_song_start(SongCatalog.SONGS[0], "Normal")
	stage = menu._stage
	stage.test_mode = true
	stage.set_process(false)
	stage.audio.stop()
	stage.phase = "playing"
	var effects: RhythmComboEffects = stage.highway.combo_effects
	effects.set_process(false)
	var taps: Array[Dictionary] = []
	for index: int in 32:
		taps.append({"pos": 800 + index * 200, "kind": "tap"})
	stage.judge.setup(RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400,
		"duration_seconds": 10.0, "tracks": [{"bars": [{"notes": taps}]}]}))
	for index: int in 9: hit(index)
	check(visible_pillars() == 0, "Combos below ten must not create a pillar")
	hit(9)
	check(visible_pillars() == 1 and effects._cursor == 1, "The tenth actual judgment must create one pillar")
	var base: Vector2 = effects._sprites[0].position + Vector2(effects.PILLAR_SIZE.x * 0.5, effects.PILLAR_SIZE.y * effects.BASE_UV)
	check(base.is_equal_approx(stage.highway.project(0.0, 0.0)), "The pillar must originate on the judged catcher")
	effects.on_judgment(10, 0.0, 1.0)
	check(effects._cursor == 1, "A repeated judgment must not duplicate a milestone")
	stage.visual_age += 0.08
	effects._process(0.08)
	var age: float = StrictData.number(effects._materials[0].get_shader_parameter("age"))
	stage.pause_stage()
	stage._process(1.0)
	effects._process(1.0)
	check(is_equal_approx(StrictData.number(effects._materials[0].get_shader_parameter("age")), age), "Pause must freeze the pillar animation")
	stage.resume_stage()
	stage._process(1.1)
	await create_timer(0.15).timeout
	stage.audio.stop()
	stage.phase = "playing"
	for index: int in range(10, 20): hit(index)
	check(effects._cursor == 2 and visible_pillars() == 1, "Twenty combo must emit again while older pillars expire")
	stage.song_time = 6.2
	stage.visual_age = 6.2
	stage.judge.step(6.2, 0.2)
	check(stage.judge.combo == 0, "The missed twenty-first note must break the combo")
	for index: int in range(21, 31): hit(index)
	check(stage.judge.combo == 10 and effects._cursor == 0, "A rebuilt ten combo must trigger after a miss")
	check(effects.get_child_count() == effects.MAX_PILLARS, "Milestones must reuse the fixed pool")
	stage.visual_age += effects.LIFETIME + 0.01
	effects._process(0.0)
	check(visible_pillars() == 0, "Finished pillars must become invisible")
	stage.retry_stage()
	check(visible_pillars() == 0 and effects._last_combo == 0 and effects._cursor == 0, "Retry must clear milestone state")
	print("Combo pillar integration: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func hit(index: int) -> void:
	var note: Dictionary = stage.judge.notes[index]
	stage.song_time = StrictData.number(note.time)
	stage.visual_age = stage.song_time
	stage.highway.combo_effects._process(0.0)
	check(stage.judge.press(0, StrictData.number(note.lane), stage.song_time), "Fixture note must be caught")
	stage.judge.release(0, stage.song_time)

func visible_pillars() -> int:
	var count: int = 0
	for pillar: Sprite2D in stage.highway.combo_effects._sprites:
		if pillar.visible: count += 1
	return count

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
