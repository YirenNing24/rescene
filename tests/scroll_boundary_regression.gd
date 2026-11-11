extends SceneTree

var menu: ResceneMainMenu
var scroll: KineticSongScroll
var failures: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await create_timer(0.4).timeout
	scroll = menu._song_view._scroll
	# Reproduce a missing release after dragging beyond the window edge.
	scroll.focus_index(0, true)
	await touch(true, Vector2(150, 240))
	await drag(Vector2(150, 700))
	# A new press with the same touch index starts a new OS gesture.
	await touch(true, Vector2(150, 350))
	await drag(Vector2(150, 200))
	check(scroll._offset > 100, "New swipe must recover after release was lost outside window")
	await touch(false, Vector2(150, 200))
	# Pull against the first edge then reverse within the same gesture.
	scroll.reset_motion()
	scroll.focus_index(0, true)
	await touch(true, Vector2(150, 100))
	for position: int in [180, 260, 340]:
		await drag(Vector2(150, position))
	check(is_zero_approx(scroll.velocity), "Outward pull must not store momentum at top edge")
	await drag(Vector2(150, 300))
	check(scroll._offset > 30 and scroll.velocity > 0, "Reversing away from top must respond immediately")
	await touch(false, Vector2(150, 300))
	# The last edge must also permit an immediate reversal.
	scroll.reset_motion()
	scroll.focus_index(scroll.row_count - 1, true)
	var maximum: float = scroll._maximum()
	await touch(true, Vector2(150, 350))
	for position: int in [260, 170, 80]:
		await drag(Vector2(150, position))
	check(is_zero_approx(scroll.velocity), "Outward pull must not store momentum at bottom edge")
	await drag(Vector2(150, 125))
	check(scroll._offset < maximum - 30 and scroll.velocity < 0, "Reversing away from bottom must respond immediately")
	await touch(false, Vector2(150, 125))
	print("Scroll boundary checks: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func point(local: Vector2) -> Vector2:
	return root.get_final_transform() * scroll.get_global_transform_with_canvas() * local

func touch(pressed: bool, local: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = point(local)
	Input.parse_input_event(event)
	await process_frame

func drag(local: Vector2) -> void:
	await create_timer(0.016).timeout
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 0
	event.position = point(local)
	Input.parse_input_event(event)
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
