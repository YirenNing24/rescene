class_name RhythmStage
extends Control
## A complete short-version rhythm stage over the existing lobby background.

signal return_to_library

const WHITE: Color = Color("f4f1ff")
const MUTED: Color = Color("b7b9d5")
const LILAC: Color = Color("c7bbff")
const KEYS: Array[Key] = [KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K]
const OUTRO_FADE_SECONDS: float = 3.0
const MISS_VIBRATION_MS: int = 35
const MISS_VIBRATION_STRENGTH: float = 0.45
const MISS_VIBRATION_COOLDOWN_MS: int = 120

var host: ResceneMainMenu
var song: Dictionary
var difficulty: String = "Normal"
var test_mode: bool = false
var mobile_rendering: bool = false
var tutorial_mode: bool = false
var _lesson: Label
var _learned: Dictionary[String, bool] = {}
var chart: Dictionary = {}
var judge: RhythmJudge
var highway: RhythmHighway
var audio: AudioStreamPlayer
var song_time: float = -3.0
var visual_age: float = 0.0
var momentum_visual: float = 0.0
var approach_seconds: float = 1.8
var phase: String = "countdown"
var timing_offset_ms: float = 0.0
var _latency: float = 0.0
var _countdown: float = 3.0
var _resume_phase: String
var _resume_count: float = 0.0
var _last_touch_frame: int = -100
var _last_miss_vibration_ms: int = -MISS_VIBRATION_COOLDOWN_MS
var _mouse_down: bool = false
var _score_label: Label
var _accuracy_label: Label
var _rival_label: Label
var _rival: Dictionary = {}
var _combo_label: Label
var _life_label: Label
var _life: ProgressBar
var _momentum_bars: Array[ProgressBar] = []
var _momentum_labels: Array[Label] = []
var _momentum_caption: Label
var _shade: ColorRect
var _progress: ProgressBar
var _time_label: Label
var _feedback: Label
var _feedback_left: float = 0.0
var _count_label: Label
var _overlay: Control
var _failed: bool = false
var _stage_visuals: Array[CanvasItem] = []
var _progression_run: String = ""
var _attempt: int = 0
var _reward_message: String = ""
var _progression_status: Label
var _connection_backgrounded: bool = false
var deck_showcase: DeckShowcase
var _hud_score: int = -1
var _hud_combo: int = -1
var _hud_resolved: int = -1
var _hud_life: float = -1.0
var _hud_second: int = -1
var _hud_momentum: int = -1


func _enter_tree() -> void:
	GameServices.menu_touches().set_gameplay_active(get_instance_id(), true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart = FirstPlay.chart() if tutorial_mode else RhythmChart.load_chart(str(song.id), difficulty)
	if chart.is_empty() or StrictData.array(chart.notes).is_empty():
		_show_error("This chart could not be loaded.")
		return
	approach_seconds = {"Easy": 2.2, "Normal": 1.9, "Hard": 1.65, "Ultra Hard": 1.45}.get(difficulty, 1.9)
	judge = RhythmJudge.new()
	judge.setup(chart)
	var _skill_connection: int = judge.card_battle.skill_activated.connect(_card_skill)
	var _int_1: int = judge.judged.connect(_judged)
	audio = AudioStreamPlayer.new()
	audio.name = "StageAudio"
	var stream: AudioStreamMP3 = load(str(song.audio_path)) as AudioStreamMP3
	if stream == null:
		_show_error("This audio file could not be loaded.")
		return
	audio.stream = stream.duplicate()
	(audio.stream as AudioStreamMP3).loop = false
	audio.volume_linear = host._music_level * 0.65
	add_child(audio)
	chart.duration = 47.0 if tutorial_mode else audio.stream.get_length() * 0.5
	_latency = AudioServer.get_output_latency()
	var config: ConfigFile = ConfigFile.new()
	if config.load(host.PROFILE_PATH) == OK:
		timing_offset_ms = StrictData.number(config.get_value("settings", "timing_offset_ms", 0.0))
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.03, 0.09, 0.6)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._at(self, _shade, Rect2(0, 0, 2400, 1080))
	highway = RhythmHighway.new()
	highway.game = self
	host._at(self, highway, Rect2(0, 0, 2400, 1080))
	_build_hud()
	_warm_hud_glyphs()
	for child: Node in get_children():
		if child is CanvasItem: _stage_visuals.append(child)
	if tutorial_mode:
		deck_showcase.hide()
		_lesson = host._label(self, "", Rect2(430, 235, 1540, 122), 27, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var _skip: Button = host._button(self, "EXIT TUTORIAL", Rect2(58, 770, 310, 60), func() -> void: FirstPlay.mark_seen(); return_to_library.emit())
	_begin_progression_attempt()


func _begin_progression_attempt() -> void:
	_attempt += 1
	_progression_run = ""
	_reward_message = ""
	_connection_backgrounded = false
	_progression_status.text = ""
	if tutorial_mode or test_mode or not GameServices.session().is_authenticated(): return
	var attempt: int = _attempt
	phase = "connecting"
	_count_label.text = "CONNECTING…"
	_request_progression_ticket.call_deferred(attempt)


func _request_progression_ticket(attempt: int) -> void:
	var run_id: String = await GameServices.progression().begin_run(str(song.id), difficulty)
	if not is_inside_tree() or attempt != _attempt: return
	_progression_run = run_id
	if run_id.is_empty():
		_show_error(GameServices.progression().error_message if not GameServices.progression().error_message.is_empty() else "Connect to the server before starting a song.")
		return
	judge.card_loadout = GameServices.progression().run_card.duplicate(true)
	_rival = GameServices.progression().run_rival.duplicate(true)
	_update_rival()
	if is_instance_valid(deck_showcase):
		deck_showcase.configure(GameServices.progression().run_deck_ids)
		if judge.card_battle.rank(1)>0: _card_skill("Overture", "Starting momentum")
	phase = "countdown"
	if _connection_backgrounded: pause_stage()


func _exit_tree() -> void:
	GameServices.menu_touches().set_gameplay_active(get_instance_id(), false)
	if not test_mode and not _progression_run.is_empty() and (phase != "results" or _failed): GameServices.progression().abandon_run.call_deferred(_progression_run)
	if is_instance_valid(audio):
		audio.stop()


func _process(delta: float) -> void:
	if judge == null or audio == null or phase in ["error", "results"]:
		return
	if phase not in ["paused", "results", "error"]:
		visual_age += delta
		if is_instance_valid(deck_showcase): deck_showcase.show_time(visual_age)
		momentum_visual = move_toward(momentum_visual, float(RhythmMomentum.tier(judge.momentum_combo())), delta * 5.0)
		var atmosphere: Color = RhythmMomentum.color(momentum_visual)
		_shade.color = Color(0.025, 0.03, 0.09, 0.6).lerp(Color(atmosphere * 0.24, 0.49), momentum_visual / 3.0)
	if phase == "countdown":
		_countdown -= delta
		song_time = minf(0.0, -_countdown)
		_count_label.text = str(maxi(1, ceili(_countdown)))
		if _countdown <= 0.0:
			_count_label.visible = false
			song_time = 0.0
			audio.play(0.0)
			phase = "playing"
	elif phase == "resume":
		_resume_count -= delta
		_count_label.text = "READY"
		if _resume_count <= 0.0:
			_count_label.visible = false
			audio.stream_paused = false
			phase = "playing"
	elif phase == "playing":
		var now: float = _clock()
		var elapsed: float = maxf(0.0, now - song_time)
		song_time = now
		_update_song_volume()
		judge.step(minf(song_time,StrictData.number(chart.duration)) + timing_offset_ms / 1000.0, elapsed)
		if tutorial_mode:
			judge.life = 1000.0
			_tutorial_caption()
		if judge.life <= 0.0:
			finish_stage(true)
		elif song_time >= chart.duration:
			finish_stage(false)
	_feedback_left = maxf(0.0, _feedback_left - delta)
	_feedback.modulate.a = minf(1.0, _feedback_left * 4.0)
	_update_judgment_hud()
	_update_momentum()
	_progress.value = maxf(0.0,StrictData.number(song_time)) / maxf(0.01,StrictData.number(chart.duration)) * 100.0
	var second: int = maxi(0, floori(song_time))
	if second != _hud_second:
		_hud_second = second
		_time_label.text = "%s  /  %s" % [_format_time(float(second)), _format_time(StrictData.number(chart.duration))]


func _update_judgment_hud() -> void:
	var score: int = judge.score()
	if score != _hud_score: _hud_score = score; _score_label.text = "%07d" % score
	if judge.combo != _hud_combo: _hud_combo = judge.combo; _combo_label.text = str(judge.combo)
	if judge.resolved_units != _hud_resolved:
		_hud_resolved = judge.resolved_units
		_accuracy_label.text = "ACCURACY   %.2f%%" % judge.accuracy()
	if judge.life != _hud_life:
		_hud_life = judge.life
		_life.value = judge.life
		_life_label.text = "LIFE   %04d" % roundi(judge.life)


func _warm_hud_glyphs() -> void:
	var server: TextServer = TextServerManager.get_primary_interface()
	for label: Label in [_score_label, _combo_label, _life_label, _count_label, _accuracy_label, _time_label, _feedback]:
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		for font_rid: RID in font.get_rids():
			server.font_render_range(font_rid, Vector2i(font_size, 0), 48, 57)
			if label == _feedback: server.font_render_range(font_rid, Vector2i(font_size, 0), 65, 90)


func _update_rival() -> void:
	if not is_instance_valid(_rival_label): return
	if _rival.is_empty(): _rival_label.text = ""; return
	var who: String = "YOUR BEST" if str(_rival.get("kind", "")) == "personal" else str(_rival.get("label", "FRIEND")).to_upper()
	_rival_label.text = "TARGET  %s  ·  %07d" % [who,StrictData.integer(_rival.get("score",0))]

func _clock() -> float:
	if not audio.playing or audio.stream_paused:
		return song_time
	return maxf(song_time, audio.get_playback_position() + AudioServer.get_time_since_last_mix() - _latency)


func _update_song_volume() -> void:
	# Follow the audio clock, so pausing/resuming cannot run a fade ahead of music.
	var duration: float = StrictData.number(chart.duration)
	var fade_length: float = minf(OUTRO_FADE_SECONDS, duration)
	var remaining: float = maxf(0.0, duration - song_time)
	var gain: float = smoothstep(0.0, maxf(0.001, fade_length), remaining)
	var volume: float = host._music_level * 0.65 * gain
	if not is_equal_approx(audio.volume_linear, volume): audio.volume_linear = volume


func _input(event: InputEvent) -> void:
	if phase == "results" and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ENTER:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused) and _overlay.is_ancestor_of(focused):
			return
		retry_stage()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		if phase in ["playing", "countdown"]:
			pause_stage()
		elif phase == "paused":
			resume_stage()
		elif phase == "results":
			return_to_library.emit()
		elif phase in ["connecting", "error"]:
			return_to_library.emit()
		get_viewport().set_input_as_handled()
		return
	if phase != "playing":
		return
	var now: float = minf(_clock(),StrictData.number(chart.duration)) + timing_offset_ms / 1000.0
	if event is InputEventKey and not (event as InputEventKey).echo:
		var key: Key = (event as InputEventKey).physical_keycode if (event as InputEventKey).physical_keycode != 0 else (event as InputEventKey).keycode
		var lane: int = KEYS.find(key)
		if lane >= 0:
			if (event as InputEventKey).pressed:
				highway.press(StrictData.number(lane))
				var _bool_2: bool = judge.press(-100 - lane, StrictData.number(lane), now, true)
			else:
				judge.release(-100 - lane, now)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_last_touch_frame = Engine.get_process_frames()
		var point: Vector2 = _local((event as InputEventScreenTouch).position)
		if (event as InputEventScreenTouch).canceled:
			judge.release(StrictData.integer((event as InputEventScreenTouch).index), now)
		elif (event as InputEventScreenTouch).pressed and _in_hit_area(point):
			highway.press(highway.screen_lane(point))
			var _bool_3: bool = judge.press(StrictData.integer((event as InputEventScreenTouch).index), highway.screen_lane(point), now)
			get_viewport().set_input_as_handled()
		elif not (event as InputEventScreenTouch).pressed:
			judge.release(StrictData.integer((event as InputEventScreenTouch).index), now)
	elif event is InputEventScreenDrag:
		_last_touch_frame = Engine.get_process_frames()
		var point: Vector2 = _local((event as InputEventScreenDrag).position)
		if judge.pointers.has((event as InputEventScreenDrag).index):
			judge.move_pointer(StrictData.integer((event as InputEventScreenDrag).index), highway.screen_lane(point) if _in_hit_area(point) else -10.0, now)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = _local((event as InputEventMouseButton).position)
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			# Touch-generated mouse events arrive first. Defer so the real touch wins.
			if _in_hit_area(point) or _mouse_down:
				call_deferred("_emulated_mouse", (event as InputEventMouseButton).pressed, point, now, Engine.get_process_frames())
				get_viewport().set_input_as_handled()
		else:
			_mouse_press(StrictData.boolean((event as InputEventMouseButton).pressed), point, now)
	elif event is InputEventMouseMotion and _mouse_down:
		var point: Vector2 = _local((event as InputEventMouseMotion).position)
		judge.move_pointer(-1, highway.screen_lane(point) if _in_hit_area(point) else -10.0, now)
		get_viewport().set_input_as_handled()


func _emulated_mouse(pressed: bool, point: Vector2, now: float, frame: int) -> void:
	if phase == "playing" and _last_touch_frame < frame:
		_mouse_press(pressed, point, now)


func _mouse_press(pressed: bool, point: Vector2, now: float) -> void:
	if pressed and _in_hit_area(point):
		_mouse_down = true
		highway.press(highway.screen_lane(point))
		var _bool_4: bool = judge.press(-1, highway.screen_lane(point), now)
		get_viewport().set_input_as_handled()
	elif not pressed and _mouse_down:
		_mouse_down = false
		judge.release(-1, now)
		get_viewport().set_input_as_handled()


func _in_hit_area(point: Vector2) -> bool:
	return highway.contains_hit_point(point)


func _local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _card_skill(skill_name: String, description: String) -> void:
	if is_instance_valid(deck_showcase): deck_showcase.show_skill(skill_name,description)

func _judged(label: String, lane: float, value: float, note_id: int) -> void:
	if label == "MISS": _vibrate_miss()
	if tutorial_mode and label != "MISS" and note_id >= 0 and note_id < judge.notes.size():
		var note: Dictionary = judge.notes[note_id]
		if note.kind == "tap": _learned["tap"] = true
		elif song_time >= StrictData.number(note.time) + StrictData.number(note.duration) - 0.1: _learned[str(note.kind)] = true
	highway.hit(label, lane, value, note_id)
	highway.combo_effects.on_judgment(judge.combo, lane, value)
	_feedback.text = label
	_feedback.add_theme_color_override("font_color", Color("abe8ff") if label == "PERFECT" else (LILAC if label != "MISS" else Color("d695b1")))
	_feedback_left = 0.6
	_update_momentum()


func _vibrate_miss() -> void:
	if not OS.has_feature("android") or not host._haptics_on or phase != "playing": return
	var now_ms: int = Time.get_ticks_msec()
	# A missed chord or several notes processed in one frame get one short pulse.
	if now_ms - _last_miss_vibration_ms < MISS_VIBRATION_COOLDOWN_MS: return
	_last_miss_vibration_ms = now_ms
	Input.vibrate_handheld(MISS_VIBRATION_MS, MISS_VIBRATION_STRENGTH)


func _update_momentum() -> void:
	var effective: int = judge.momentum_combo()
	if _hud_momentum == effective: return
	_hud_momentum = effective
	var level: int = RhythmMomentum.tier(effective)
	for index: int in _momentum_bars.size():
		_momentum_bars[index].value = clampf(float(effective - index * 20) / 20.0, 0.0, 1.0)
		_momentum_labels[index].modulate = Color.WHITE if level > index else Color(0.65, 0.65, 0.78)
	if _momentum_caption == null: return
	var needed: int = RhythmMomentum.THRESHOLDS[mini(level, 2)] - effective
	_momentum_caption.text = "MOMENTUM  %d×  /  MAX" % RhythmMomentum.multiplier(effective) if level == 3 else "MOMENTUM  %d×  /  %d COMBO TO %d×" % [RhythmMomentum.multiplier(effective), needed, RhythmMomentum.MULTIPLIERS[level + 1]]
	_momentum_caption.add_theme_color_override("font_color", RhythmMomentum.COLORS[level])


func _build_hud() -> void:
	deck_showcase = DeckShowcase.new(); deck_showcase.host = host; deck_showcase.set_id = SongSets.for_song(str(song.id))
	deck_showcase.name = "EquippedSongSetCards"
	deck_showcase.deck_ids = GameServices.commerce().deck_ids(deck_showcase.set_id)
	host._at(self, deck_showcase, Rect2(Vector2(42, 282), DeckShowcase.PANEL_SIZE))
	var _panel_5: Panel = host._panel(self, Rect2(58, 38, 510, 115), Color(0.055, 0.065, 0.15, 0.84), Color(0.74, 0.7, 1, 0.4), 23)
	var _label_6: Label = host._label(self, "S C O R E", Rect2(85, 53, 310, 24), 14, LILAC, host.BOLD)
	_score_label = host._label(self, "0000000", Rect2(82, 82, 432, 61), 45, WHITE, host.BOLD)
	_accuracy_label = host._label(self, "ACCURACY   100.00%", Rect2(64, 173, 440, 30), 17, MUTED, host.FONT)
	_rival_label = host._label(self, "", Rect2(64, 194, 460, 25), 14, LILAC, host.BOLD)
	_progression_status = host._label(self, "", Rect2(64,217,650,30),16,MUTED,host.FONT)
	var cover: TextureRect = TextureRect.new()
	cover.texture = load(str(song.cover_path))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	host._at(self, cover, Rect2(1145, 31, 110, 110))
	var title: Label = host._label(self,str(song.title), Rect2(630, 49, 470, 41), 27, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var _label_7: Label = host._label(self,str(song.artist), Rect2(635, 100, 465, 28), 16, MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	var _label_8: Label = host._label(self, difficulty.to_upper(), Rect2(1300, 47, 390, 40), 24, LILAC, host.BOLD)
	var _label_9: Label = host._label(self, "GUIDED FIRST PLAY" if tutorial_mode else "SHORT VERSION", Rect2(1302, 98, 390, 28), 13, MUTED, host.FONT)
	_life_label = host._label(self, "LIFE   1000", Rect2(1790, 48, 400, 32), 24, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_life = ProgressBar.new()
	_life.max_value = 1000.0
	_life.value = 1000.0
	_life.show_percentage = false
	_life.add_theme_stylebox_override("background", host._style(Color(0.15, 0.15, 0.25), Color.TRANSPARENT, 7))
	_life.add_theme_stylebox_override("fill", host._style(Color("b9e5d9"), Color.TRANSPARENT, 7))
	host._at(self, _life, Rect2(1790, 103, 400, 12))
	_momentum_caption = host._label(self, "", Rect2(1790, 130, 400, 24), 14, LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	for index: int in 3:
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", host._style(Color(0.11, 0.11, 0.2, 0.9), Color(RhythmMomentum.COLORS[index + 1], 0.22), 5))
		bar.add_theme_stylebox_override("fill", host._style(RhythmMomentum.COLORS[index + 1], Color.TRANSPARENT, 5))
		host._at(self, bar, Rect2(1790 + index * 137, 160, 126, 14))
		_momentum_bars.append(bar)
		var tier_label: Label = host._label(self, "%d×" % RhythmMomentum.MULTIPLIERS[index + 1], Rect2(1790 + index * 137, 180, 126, 25), 16, RhythmMomentum.COLORS[index + 1], host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		_momentum_labels.append(tier_label)
	_update_momentum()
	var _button_10: Button = host._icon_button(self, "pause", Rect2(2260, 39, 82, 82), pause_stage)
	var _label_11: Label = host._label(self, "C O M B O", Rect2(2015, 354, 300, 34), 21, LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_combo_label = host._label(self, "0", Rect2(2010, 403, 310, 124), 94, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_feedback = host._label(self, "", Rect2(850, 558, 700, 82), 54, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_feedback.modulate.a = 0.0
	_count_label = host._label(self, "3", Rect2(780, 396, 840, 160), 112, WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_time_label = host._label(self, "0:00", Rect2(2060, 1019, 280, 27), 17, MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", host._style(Color(0.3, 0.28, 0.5, 0.3), Color.TRANSPARENT, 2))
	_progress.add_theme_stylebox_override("fill", host._style(LILAC, Color.TRANSPARENT, 2))
	host._at(self, _progress, Rect2(60, 1050, 2280, 4))


func pause_stage() -> void:
	if phase not in ["playing", "countdown"]:
		return
	_resume_phase = phase
	phase = "paused"
	audio.stream_paused = true
	if _resume_phase == "playing":
		judge.suspend(minf(song_time,StrictData.number(chart.duration)) + timing_offset_ms / 1000.0)
		_progression_status.text = "Paused run · progression only"
	_mouse_down = false
	_show_pause_controls.call_deferred()


func _show_pause_controls() -> void:
	# Focus notifications can arrive while the scene tree is adding children.
	if phase != "paused" or not is_inside_tree(): return
	var window: Panel = _modal("Take a breath", "STAGE PAUSED")
	var _button_14: Button = host._button(window, "RESUME", Rect2(42, 178, 636, 66), resume_stage, true)
	var _button_15: Button = host._button(window, "RETRY", Rect2(42, 263, 636, 66), retry_stage)
	var _button_16: Button = host._button(window, "SONG SELECTION", Rect2(42, 348, 636, 66), func() -> void: return_to_library.emit())
	var _label_17: Label = host._label(window, "TIMING OFFSET", Rect2(43, 445, 370, 26), 14, MUTED, host.BOLD)
	var value: Label = host._label(window, "%+d ms" % roundi(timing_offset_ms), Rect2(480, 440, 195, 32), 18, LILAC, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	var slider: HSlider = HSlider.new()
	slider.min_value = -150.0
	slider.max_value = 150.0
	slider.step = 5.0
	slider.value = timing_offset_ms
	host._at(window, slider, Rect2(43, 487, 635, 42))
	var _int_18: int = slider.value_changed.connect(func(ms: float) -> void:
		timing_offset_ms = ms
		value.text = "%+d ms" % roundi(ms)
		var config: ConfigFile = ConfigFile.new()
		var _error_19: Error = config.load(host.PROFILE_PATH)
		config.set_value("settings", "timing_offset_ms", ms)
		var _error_20: Error = config.save(host.PROFILE_PATH)
	)


func resume_stage() -> void:
	if phase != "paused": return
	_close_overlay()
	if _resume_phase == "countdown":
		phase = "countdown"
	else:
		phase = "resume"
		_resume_count = 1.0
		_count_label.visible = true


func retry_stage() -> void:
	_close_overlay()
	for visual: CanvasItem in _stage_visuals: visual.show()
	audio.stop()
	audio.stream_paused = false
	audio.volume_linear = host._music_level * 0.65
	judge.setup(chart)
	highway.effects.clear()
	highway.combo_effects.reset()
	highway.sustain_effects.reset()
	highway.reset_presses()
	highway.reset_note_colors()
	visual_age = 0.0
	momentum_visual = 0.0
	_shade.color = Color(0.025, 0.03, 0.09, 0.6)
	_update_momentum()
	_mouse_down = false
	_feedback_left = 0.0
	_feedback.modulate.a = 0.0
	_countdown = 3.0
	song_time = -3.0
	_count_label.visible = true
	_failed = false
	phase = "countdown"
	_begin_progression_attempt()


func finish_stage(failed: bool) -> void:
	if phase == "results": return
	if tutorial_mode: _finish_tutorial(); return
	audio.stop()
	if failed:
		# Future notes were never attempted; don't count them as missed judgments.
		judge.pointers.clear()
	else:
		judge.finish(StrictData.number(chart.duration + timing_offset_ms / 1000.0))
	phase = "results"
	_failed = failed
	if failed and not test_mode and not _progression_run.is_empty(): GameServices.progression().abandon_run.call_deferred(_progression_run)
	_count_label.visible = false
	var result: Dictionary = {"score": judge.score(), "accuracy": judge.accuracy(), "rank": judge.rank(), "max_combo": judge.max_combo}
	var previous: Dictionary = RhythmRecords.best(str(song.id), difficulty)
	var data: Dictionary = result.duplicate(true)
	data.failed = failed
	data.previous = previous
	data.last_attempt = RhythmRecords.last_attempt(str(song.id),difficulty)
	data.rival = _rival.duplicate(true)
	data.new_best = not failed and (previous.is_empty() or result.score > previous.score)
	data.counts = judge.counts.duplicate()
	data.total_units = judge.total_units
	data.played = clampf(song_time, 0.0,StrictData.number(chart.duration))
	data.duration = chart.duration
	data.completion = data.played / maxf(0.01,StrictData.number(chart.duration))
	if not test_mode:
		if not failed: RhythmRecords.save(song, difficulty, result)
		else: RhythmRecords.save_last_attempt(str(song.id),difficulty,result)
	_close_overlay()
	for visual: CanvasItem in _stage_visuals: visual.hide()
	_overlay = ResultsScreen.new()
	(_overlay as ResultsScreen).stage = self
	(_overlay as ResultsScreen).data = data
	add_child(_overlay)
	if not test_mode and not failed and not _progression_run.is_empty():
		if judge.replay_overflow:
			(_overlay as ResultsScreen).set_progression_message("Replay size limit reached. This record is saved on this device.")
			return
		(_overlay as ResultsScreen).set_progression_message("Verifying your run…")
		GameServices.progression().finish_run.call_deferred(_progression_run, {"score":result.score,"max_combo":result.max_combo,"counts":data.counts,"trace":judge.trace,"replay":judge.replay_payload(_progression_run, str(chart.get("revision", "")))})


func _show_error(message: String) -> void:
	phase = "error"
	var window: Panel = _modal("Song unavailable", "LET’S GET YOU BACK ON STAGE")
	var detail: Label = Label.new()
	detail.name = "StageErrorMessage"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text = message
	detail.add_theme_font_override("font", host.FONT)
	detail.add_theme_font_size_override("font_size", 23)
	detail.add_theme_color_override("font_color", MUTED)
	host._at(window, detail, Rect2(44, 172, 632, 154))
	var _retry_button: Button = host._button(window, "TRY AGAIN", Rect2(42, 350, 636, 72), retry_stage, true)
	var _button_21: Button = host._button(window, "BACK TO SONGS", Rect2(42, 446, 636, 72), func() -> void: return_to_library.emit())


func _modal(title: String, subtitle: String) -> Panel:
	_close_overlay()
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	host._at(self, _overlay, Rect2(0, 0, 2400, 1080))
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.025, 0.075, 0.82)
	host._at(_overlay, shade, Rect2(0, 0, 2400, 1080))
	var window: Panel = host._panel(_overlay, Rect2(840, 246, 720, 588), Color("16182d"), Color(0.76, 0.71, 1, 0.6), 28)
	var _label_22: Label = host._label(window, title, Rect2(42, 32, 636, 62), 39, WHITE, host.SERIF)
	var sub: Label = host._label(window, subtitle, Rect2(44, 108, 634, 31), 14, LILAC, host.BOLD)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return window


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.hide()
		_overlay.queue_free()
	_overlay = null


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_connection_backgrounded = false
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and phase == "connecting":
		_connection_backgrounded = true
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and not test_mode and phase in ["playing", "countdown", "resume"]:
		if phase == "resume": phase = "playing"
		pause_stage()


static func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), StrictData.integer(seconds) % 60]

func _tutorial_caption() -> void:
	if song_time < 11.0: _lesson.text = "1 / TAP  ·  Tap the matching circle as the note reaches it."
	elif song_time < 20.0: _lesson.text = "2 / HOLD  ·  Keep pressing until the ribbon ends."
	elif song_time < 31.0: _lesson.text = "3 / CURVE  ·  Keep your finger down and follow the ribbon."
	elif song_time < 44.0: _lesson.text = "4 / MOMENTUM  ·  Build a streak for 2×, 3× and 5×.\nA miss resets momentum. Perfect hits activate your card bonuses."
	else: _lesson.text = "Your album deck combines five members’ bonuses.\nCards gain XP from refinement items; your player earns XP from songs."

func _finish_tutorial() -> void:
	phase = "results"; audio.stop(); _count_label.hide()
	var mastered: bool = _learned.has("tap") and _learned.has("hold") and _learned.has("slide")
	FirstPlay.mark_seen()
	var window: Panel = _modal("Your stage awaits" if mastered else "Keep finding your rhythm", "TUTORIAL COMPLETE" if mastered else "TRY THE NOTES AGAIN")
	var caption: String = "Tap %s   ·   Hold %s   ·   Curve %s" % ["✓" if _learned.has("tap") else "—", "✓" if _learned.has("hold") else "—", "✓" if _learned.has("slide") else "—"]
	var _detail: Label = host._label(window, caption + "\n\nTutorial uses no energy and awards no records or rewards.", Rect2(42, 160, 636, 130), 24, LILAC)
	var _retry: Button = host._button(window, "REPEAT TUTORIAL", Rect2(42, 320, 636, 66), func() -> void: _learned.clear(); retry_stage())
	var _done: Button = host._button(window, "LET’S PLAY", Rect2(42, 410, 636, 66), func() -> void: return_to_library.emit(), true)
