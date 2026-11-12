extends SceneTree
## Actual input dispatch: transparent GUI feedback, touch deduplication and
## suppression across the desktop and Android gameplay viewports.

var failures: int = 0
var presses: int = 0
var feedback: MenuTouchFeedback


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	feedback = GameServices.menu_touches()
	feedback.set_enabled(true)
	var previous_emulation: bool = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = false
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	var button: Button = Button.new()
	button.position = Vector2(1800, 500)
	button.size = Vector2(300, 80)
	var _pressed: int = button.pressed.connect(func() -> void: presses += 1)
	menu.add_child(button)
	await process_frame
	for pressed: bool in [true, false]:
		mouse(Vector2(1900, 540), pressed)
		await process_frame
	check(presses == 1, "Touch overlay must let buttons receive each click once")
	check(feedback._pulses.size() == 1, "Only pressing creates feedback, never releasing")
	check(feedback._pulses[0].point.distance_to(Vector2(1900, 540)) < 1.0, "Feedback must use viewport coordinates after input scaling")
	button.queue_free()
	feedback._clear()
	# Emulation may arrive before ScreenTouch on Android. Render one burst.
	mouse(Vector2(1500, 540), true, InputEvent.DEVICE_ID_EMULATION)
	touch(Vector2(1500, 540), true)
	await process_frame
	check(feedback._pulses.size() == 1, "Emulated mouse and native touch must share one effect")
	touch(Vector2(1500, 540), false)
	await process_frame
	check(feedback._pulses.size() == 1, "Touch release must not create another effect")
	touch(Vector2(1600, 540), true, 1)
	await process_frame
	check(feedback._pulses.size() == 2, "Distinct fingers receive independent feedback")
	feedback.set_enabled(false)
	touch(Vector2(1600, 540), true)
	await process_frame
	check(feedback._pulses.is_empty() and not feedback.is_processing(), "Particle Effects off must clear feedback and stop its processing")
	feedback.set_enabled(true)
	for index: int in 20: touch(Vector2(1500 + index * 5, 540), true, index)
	await process_frame
	check(feedback._pulses.size() == MenuTouchFeedback.MAX_PULSES, "Rapid multitouch must have a fixed effect budget")
	await create_timer(0.5).timeout
	check(feedback._pulses.is_empty() and not feedback.is_processing(), "Feedback must expire and do no idle animation work")
	menu._open_songs()
	for mobile: bool in [false, true]:
		menu.force_mobile_gameplay_rendering = mobile
		touch(Vector2(2200, 1020), true)
		await process_frame
		check(not feedback._pulses.is_empty(), "Song selection receives menu feedback")
		menu._request_song_start(SongCatalog.SONGS[0], "Easy")
		var stage: RhythmStage = menu._stage
		stage.test_mode = true
		stage.set_process(false)
		check(feedback._pulses.is_empty(), "Entering gameplay immediately clears existing menu effects")
		for phase: String in ["countdown", "playing", "paused", "results"]:
			stage.phase = phase
			touch(Vector2(1500, 540), true)
			await process_frame
			check(feedback._pulses.is_empty(), "Stage input must never spawn menu effects: " + phase)
		menu._return_from_stage()
		await process_frame
		touch(Vector2(2200, 1020), true)
		await process_frame
		check(feedback._pulses.size() == 1, "Leaving gameplay restores menu feedback on both render paths")
		feedback._clear()
	if DisplayServer.get_name() != "headless":
		menu._back_from_songs()
		await create_timer(0.6).timeout
		touch(Vector2(1350, 965), true)
		await process_frame
		feedback.set_process(false)
		feedback._pulses[0].age = 0.09
		feedback._canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var _saved: Error = root.get_texture().get_image().save_png("res://previews/menu-touch-feedback.png")
	feedback._clear()
	Input.emulate_mouse_from_touch = previous_emulation
	menu.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Menu touch feedback, GUI input and gameplay exclusion: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)


func mouse(point: Vector2, pressed: bool, device: int = 0) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.device = device
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = root.get_final_transform() * point
	Input.parse_input_event(click)


func touch(point: Vector2, pressed: bool, index: int = 0) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)


func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
