extends SceneTree

var menu: ResceneMainMenu
var scroll: KineticSongScroll
var failures: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await create_timer(0.4).timeout
	scroll = menu._song_view._scroll
	scroll.focus_index(0, true)
	print("Touchscreen emulation: ", DisplayServer.is_touchscreen_available())
	# Begin in the gap between the first and second row, outside either button.
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = point(Vector2(250, 119))
	Input.parse_input_event(touch)
	await process_frame
	check(not scroll.is_processing_internal(), "Native ScrollContainer must not also start a drag")
	for y: int in [169, 219, 269, 319]:
		await drag(Vector2(250, y))
	for y: int in [269, 219, 169, 119]:
		await drag(Vector2(250, y))
	touch = touch.duplicate()
	touch.pressed = false
	touch.position = point(Vector2(250, 119))
	Input.parse_input_event(touch)
	await create_timer(0.7).timeout
	check(scroll._offset > 125, "Swipe back from a row gap must move through the songs")
	check(not scroll.is_processing_internal(), "No native drag/deceleration left running")
	# Editor/forwarded mouse input may have an emulated device ID without a touch counterpart.
	Input.emulate_touch_from_mouse = false
	scroll.focus_index(0, true)
	await process_frame
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.device = InputEvent.DEVICE_ID_EMULATION
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = point(Vector2(250, 45))
	Input.parse_input_event(wheel)
	await create_timer(0.7).timeout
	check(scroll._offset > 100, "Forwarded wheel input must not snap back to the first song")
	print("Input ownership checks: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func point(local: Vector2) -> Vector2:
	return root.get_final_transform() * scroll.get_global_transform_with_canvas() * local

func drag(local: Vector2) -> void:
	await create_timer(0.016).timeout
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 0
	event.position = point(local)
	event.relative = Vector2(0, 45)
	Input.parse_input_event(event)
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
