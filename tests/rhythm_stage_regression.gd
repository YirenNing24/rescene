extends SceneTree
## Exercises the real Start -> stage -> results -> song library flow and native input.

var menu: ResceneMainMenu
var stage: RhythmStage
var failures: int = 0
var previous_fps: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	previous_fps = Engine.max_fps
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	menu.force_mobile_gameplay_rendering = OS.get_cmdline_user_args().has("--mobile-rendering")
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await create_timer(0.4).timeout
	var view: SongSelection = menu._song_view
	var selected_id: String = view.selected.id
	view._start_button.pressed.emit()
	stage = menu._stage
	check(is_instance_valid(stage), "START must open gameplay")
	if not is_instance_valid(stage):
		quit(1)
		return
	stage.test_mode = true
	stage.set_process(false)
	if menu.force_mobile_gameplay_rendering:
		check(stage.mobile_rendering and stage.get_viewport() is SubViewport, "Android gameplay must use its own render target")
		check((stage.get_viewport() as SubViewport).size == Vector2i(1600, 720), "Android target must be 1600 × 720")
		check((stage.get_viewport() as SubViewport).size_2d_override == Vector2i(2400, 1080), "Gameplay layout and input coordinates must remain 2400 × 1080")
		check(Engine.max_fps == 60, "Mobile gameplay must target 60 FPS")
	check(stage.phase == "countdown" and not StrictData.array(stage.chart.notes).is_empty(), "Stage must load the selected chart")
	check(not menu._canvas.visible and not menu._preview.playing and menu._music.stream_paused, "Gameplay must own screen and audio")
	check(absf(StrictData.number(stage.chart.duration - stage.audio.stream.get_length() * 0.5)) < 0.01, "Gameplay must use exactly half the track")
	if menu.force_mobile_gameplay_rendering:
		await process_frame
		for pressed: bool in [true, false]:
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = physical_at(Vector2(2300, 80))
			Input.parse_input_event(click)
			await process_frame
		check(stage.phase == "paused", "The scaled pause button must receive native GUI clicks")
		stage.resume_stage()
	stage._process(3.1)
	check(stage.audio.playing and stage.phase == "playing", "Countdown must start the selected audio")
	await create_timer(0.15).timeout
	stage._process(0.15)
	check(stage.song_time >= 0.0, "Audio clock must advance")
	stage.pause_stage()
	var paused_at: float = stage.song_time
	stage._process(0.2)
	check(stage.phase == "paused" and stage.audio.stream_paused and stage.song_time == paused_at, "Pause must freeze music and gameplay")
	stage.resume_stage()
	check(stage.phase == "resume", "Resume must offer a ready countdown")
	stage._process(1.1)
	check(stage.phase == "playing" and not stage.audio.stream_paused, "Resume must continue the same audio")
	stage.test_mode = false
	stage._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	stage.test_mode = true
	check(stage.phase == "paused" and stage.audio.stream_paused, "Backgrounding the mobile app must pause the stage")
	verify_outro_fade()
	stage.retry_stage()
	check(stage.phase == "countdown" and stage.judge.score() == 0 and stage.judge.life == 1000, "Retry must reset the stage")
	stage.audio.stop()
	stage.phase = "playing"
	# Two simultaneous touch notes, then a curved trace with native drag events.
	var fixture: Dictionary = RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400, "duration_seconds": 5,
		"tracks": [
			{"bars": [{"notes": [{"pos": 800, "kind": "tap"}]}]},
			{"bars": [{"notes": [{"pos": 1600, "kind": "slide", "len": 1600, "curve": [{"at": 0.0, "lane": 1.0}, {"at": 0.5, "lane": 3.0}, {"at": 1.0, "lane": 2.0}]}]}]},
			{"bars": []}, {"bars": []},
			{"bars": [{"notes": [{"pos": 800, "kind": "tap"}]}]}]})
	stage.judge.setup(fixture)
	stage.song_time = 1.0
	await touch(0, true, 0.0)
	await touch(1, true, 4.0)
	check(StrictData.boolean(stage.judge.counts.PERFECT == 2), "Multitouch must hit simultaneous notes independently")
	check(not stage.judge.pointers.has(-1), "Touch emulation must not leave an extra mouse pointer")
	await touch(0, false, 0.0)
	await touch(1, false, 4.0)
	stage.song_time = 2.0
	await touch(0, true, 1.0)
	var tracing_finger: int = 0
	for step: int in range(1, 101):
		var t: float = 2.0 + step * 0.02
		stage.song_time = t
		var note: Dictionary = stage.judge.notes[2]
		var event: InputEventScreenDrag = InputEventScreenDrag.new()
		event.index = tracing_finger
		event.position = physical_point(RhythmChart.lane_at(note, t))
		Input.parse_input_event(event)
		await process_frame
		stage.judge.step(t, 0.02)
		if step == 20:
			stage.pause_stage()
			stage.resume_stage()
			stage._process(1.1)
			tracing_finger = 3
			await touch(tracing_finger, true, RhythmChart.lane_at(note, t))
	await touch(tracing_finger, false, 2.0)
	check(stage.judge.score() == 1000000, "Native curved touch tracing must complete the chart")
	verify_sustain_effects()
	verify_momentum_hud()
	# Keyboard presses use the same timing judge.
	stage.judge.setup(fixture)
	stage.song_time = 1.0
	await key(KEY_D, true)
	await key(KEY_K, true)
	await key(KEY_D, false)
	await key(KEY_K, false)
	check(StrictData.boolean(stage.judge.counts.PERFECT == 2), "D / F / Space / J / K keyboard controls")
	stage.audio.play(StrictData.number(stage.chart.duration - 0.1))
	stage.song_time = stage.chart.duration
	stage._process(0.0)
	check(stage.phase == "results" and is_instance_valid(stage._overlay), "Finishing must open results")
	check(not stage.audio.playing, "Audio must stop at the half-length cutoff")
	check((stage._overlay as ResultsScreen).name == "ResultsScreen" and not stage.highway.visible and not stage._score_label.visible, "Results must replace the gameplay screen")
	(stage._overlay as ResultsScreen)._retry.pressed.emit()
	check(stage.phase == "countdown" and stage.highway.visible and stage._overlay == null, "Results retry must restore gameplay")
	stage.judge.setup(fixture)
	var _bool_1: bool = stage.judge.press(0, 0.0, 1.0)
	stage.judge.release(0)
	stage.judge.life = 0.0
	stage.song_time = 1.2
	stage.phase = "playing"
	stage._process(0.0)
	check(StrictData.boolean((stage._overlay as ResultsScreen).data.failed and (stage._overlay as ResultsScreen).data.counts.MISS == 1), "Game over must not count future notes as missed")
	check(StrictData.boolean((stage._overlay as ResultsScreen).data.max_combo == 1 and (stage._overlay as ResultsScreen).data.accuracy == 50.0), "Game over must retain attempted-note stats")
	await key(KEY_ENTER, true)
	await key(KEY_ENTER, false)
	check(stage.phase == "countdown" and stage._overlay == null, "Enter must retry from game over")
	stage.finish_stage(true)
	(stage._overlay as ResultsScreen)._songs.pressed.emit()
	await process_frame
	check(not is_instance_valid(menu._stage) and menu._canvas.visible, "Songs must return to the same library")
	check(Engine.max_fps == previous_fps, "Leaving the mobile stage must restore the prior frame-rate setting")
	check(StrictData.boolean(menu._song_view.selected.id == selected_id and menu._preview.playing), "Return must retain selection and resume its preview")
	print("Rhythm stage integration: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await process_frame
	# Let the audio server release stopped MP3 playback objects before shutdown.
	await create_timer(0.15).timeout
	quit(failures)

func physical_point(lane: float) -> Vector2:
	var local: Vector2 = Vector2(1200.0 + (lane - 2.0) * 316.0, 895.0)
	return physical_at(local)

func verify_outro_fade() -> void:
	var previous_music: float = menu._music_level
	menu._music_level = 0.8
	var full_volume: float = menu._music_level * 0.65
	stage.audio.stop()
	stage.phase = "playing"
	stage.judge.life = 1000000.0
	stage.song_time = StrictData.number(stage.chart.duration) - 3.0
	stage._process(0.0)
	check(is_equal_approx(stage.audio.volume_linear, full_volume), "Outro must keep full music volume before the final three seconds")
	stage.song_time = StrictData.number(stage.chart.duration) - 1.5
	stage._process(0.0)
	check(is_equal_approx(stage.audio.volume_linear, full_volume * 0.5), "Music must fade smoothly during the final playable seconds")
	stage.pause_stage()
	stage._process(2.0)
	check(is_equal_approx(stage.audio.volume_linear, full_volume * 0.5), "Pausing must freeze the outro fade with the song")
	stage.resume_stage()
	stage._process(1.1)
	stage.song_time = StrictData.number(stage.chart.duration) - 0.05
	stage._process(0.0)
	check(stage.audio.volume_linear < full_volume * 0.01, "Music must be nearly silent at the existing half-song cutoff")
	stage.retry_stage()
	check(is_equal_approx(stage.audio.volume_linear, full_volume), "Retry must restore the normal music volume")
	menu._music_level = previous_music

func physical_at(local: Vector2) -> Vector2:
	if is_instance_valid(menu._stage_surface):
		return root.get_final_transform() * menu._stage_surface.container.get_global_transform_with_canvas() * stage.get_viewport().get_final_transform() * stage.get_global_transform_with_canvas() * local
	return root.get_final_transform() * stage.get_global_transform_with_canvas() * local

func verify_momentum_hud() -> void:
	var taps: Array[Dictionary] = []
	for index: int in 61: taps.append({"pos": 800 + index * 200, "kind": "tap"})
	stage.judge.setup(RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400, "duration_seconds": 18,
		"tracks": [{"bars": [{"notes": taps}]}]}))
	for index: int in 60:
		stage.song_time = StrictData.number(stage.judge.notes[index].time)
		check(stage.judge.press(0, 0.0, stage.song_time), "Momentum HUD fixture must hit")
		stage.judge.release(0)
		if stage.judge.combo in [20, 40, 60]:
			var tier: int = RhythmMomentum.tier(stage.judge.combo)
			check(stage._momentum_caption.text.contains("%d×" % RhythmMomentum.MULTIPLIERS[tier]), "The HUD must show the earned multiplier")
	stage.phase = "countdown"
	stage._countdown = 100.0
	stage._process(0.7)
	check(stage.momentum_visual == 3.0 and stage._momentum_bars[2].value == 1.0, "Max momentum must fill all bars and drive the environment")
	var shade: Color = stage._shade.color
	stage.phase = "paused"
	stage._process(1.0)
	check(stage._shade.color == shade and stage.momentum_visual == 3.0, "Pause must freeze momentum atmosphere")
	stage.song_time = StrictData.number(stage.judge.notes[60].time) + 0.2
	stage.judge.step(stage.song_time, 0.2)
	check(stage._momentum_bars[0].value == 0.0 and stage._momentum_caption.text.contains("1×"), "A miss must empty the HUD immediately")
	stage.retry_stage()
	check(stage.momentum_visual == 0.0 and stage._momentum_bars[2].value == 0.0 and stage.judge.score() == 0, "Retry must reset score, momentum and atmosphere")
	stage.phase = "playing"

func verify_sustain_effects() -> void:
	var effects: RhythmSustainEffects = stage.highway.sustain_effects
	effects.reset()
	stage.judge.setup(RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400, "duration_seconds": 5,
		"tracks": [
			{"bars": [{"notes": [{"pos": 800, "len": 1600, "kind": "hold"}]}]},
			{"bars": [{"notes": [{"pos": 800, "len": 1600, "kind": "slide", "curve": [{"at": 0.0, "lane": 1.0}, {"at": 1.0, "lane": 3.0}]}]}]}]}))
	stage.song_time = 1.0
	check(stage.judge.press(0, 0.0, 1.0) and stage.judge.press(1, 1.0, 1.0), "Both fixture ribbons must start")
	effects._process(0.0)
	check(effects._ids.has(0) and effects._ids.has(1), "Simultaneous collected ribbons must each own a vortex")
	stage.song_time = 1.5
	stage.visual_age += 0.5
	stage.judge.move_pointer(1, RhythmChart.lane_at(stage.judge.notes[1], 1.5), 1.5)
	stage.judge.step(1.5, 0.5)
	effects._process(0.0)
	var slot: int = effects._ids.find(1)
	if slot >= 0:
		var origin: Vector2 = effects._sprites[slot].position + effects.VORTEX_SIZE * effects.ORIGIN_UV
		check(origin.is_equal_approx(stage.highway.project(RhythmChart.lane_at(stage.judge.notes[1], 1.5), 0.0)), "The vortex must follow the curved head along the hit line")
		var age: float = StrictData.number(effects._materials[slot].get_shader_parameter("age"))
		stage.phase = "paused"
		effects._process(0.5)
		check(is_equal_approx(StrictData.number(effects._materials[slot].get_shader_parameter("age")), age), "Pause must freeze vortex motion")
		stage.phase = "playing"
	else:
		check(false, "The curved ribbon vortex must remain active while tracing")
	stage.judge.release(0, 1.5)
	stage.judge.release(1, 1.5)
	effects._process(0.0)
	stage.visual_age += effects.RELEASE + 0.01
	effects._process(0.0)
	check(not effects._ids.has(0) and not effects._ids.has(1), "Released holds must fade their vortices")
	check(effects.get_child_count() == effects.MAX_VORTICES, "Sustains must reuse a bounded effect pool")
	stage.retry_stage()
	check(effects._ids.count(-1) == effects.MAX_VORTICES, "Retry must clear all vortex ownership")
	stage.phase = "playing"

func touch(index: int, pressed: bool, lane: float) -> void:
	if index == 0:
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		mouse.position = physical_point(lane)
		Input.parse_input_event(mouse)
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = physical_point(lane)
	Input.parse_input_event(event)
	await process_frame

func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
