extends SceneTree

var failures: int = 0
var menu: ResceneMainMenu
var scroll: ActionListScroll
var taps: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var commerce: CommerceService = GameServices.commerce()
	commerce.inventory = [{"id":"qa_liv", "member":"Liv", "member_index":1, "quantity":1, "stars":1, "level":1}, {"id":"qa_zena", "member":"Zena", "member_index":4, "quantity":1, "stars":2, "level":1}, {"id":"gone", "quantity":0}]
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu); current_scene = menu
	await create_timer(0.3).timeout
	var showcase: DeckShowcase = DeckShowcase.new()
	showcase.host = menu; showcase.deck_ids = ["", "", "", "", ""]
	menu.add_child(showcase)
	check(not showcase.visible, "No deck means no gameplay card panel")
	showcase.configure(["", "qa_liv", "gone", "", ""])
	showcase.show_time(0.0)
	check(showcase.visible and showcase._slots == [1], "Only populated, owned slots are shown")
	var original: Control = showcase._portrait
	showcase.show_time(12.5)
	check(showcase._portrait == original and original.position == Vector2(27,65) and original.modulate.a == 1.0, "One card remains static and fully visible")
	showcase.configure(["", "qa_liv", "", "", "qa_zena"])
	showcase.show_time(0.8)
	check(showcase._member_label.text.begins_with("Liv"), "Sparse deck starts at its first populated member")
	showcase.show_time(5.3)
	check(showcase._member_label.text.begins_with("Zena"), "Sparse deck rotates directly to its next populated member")
	showcase.hide(); showcase.show_time(10.0)
	check(not showcase.visible, "Tutorial hide remains respected")
	showcase.queue_free()
	var missions: Array[Dictionary] = []
	var unlocks: Array[Dictionary] = []
	for index: int in 9:
		missions.append({"id":str(index), "name":"Mission %d" % index, "scope":"daily", "description":"Clear a song", "target":3, "progress":1, "xp":100, "starlight":10, "claimed":false})
		unlocks.append({"id":str(index), "name":"Title %d" % index, "kind":"title", "requirement":"Reach level 5", "unlocked":false, "equipped":false})
	GameServices.progression().state = {"level":3, "missions":missions, "unlocks":unlocks}
	menu._open_destination("MISSIONS")
	var journey: ProgressionView = menu._dialog as ProgressionView
	check(journey != null, "Journey opens")
	for tab_name: String in ["missions", "unlocks"]:
		journey.tab = tab_name; journey._render()
		await create_timer(0.15).timeout
		scroll = journey._scroll as ActionListScroll
		check(scroll != null and scroll._maximum() > 500, tab_name + " has scrollable content")
		var button: Button = scroll.actions[0]
		for callback: Dictionary in button.pressed.get_connections():
			if callback.callable is Callable:
				var action: Callable = callback.callable
				button.pressed.disconnect(action)
		button.disabled = false
		var _connected: int = button.pressed.connect(func() -> void: taps += 1)
		var local: Vector2 = scroll.get_global_transform_with_canvas().affine_inverse() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
		var before: int = taps
		await touch(local, true)
		await drag(local - Vector2(0, 180))
		await touch(local - Vector2(0, 180), false)
		await create_timer(0.4).timeout
		check(scroll._offset > 100, tab_name + " scrolls via touch starting over an action button")
		check(taps == before, "Dragging must never activate an action")
		scroll.reset_motion(); scroll._set_offset(scroll._maximum())
		await touch(Vector2(300,200), true)
		await drag(Vector2(300,400))
		await touch(Vector2(300,400), false)
		check(scroll._offset < scroll._maximum(), tab_name + " can reverse at the bottom")
		scroll.reset_motion(); scroll._set_offset(0.0)
		await touch(local, true); await touch(local, false)
		check(taps == before + 1, tab_name + " button taps still work")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var _saved: Error = root.get_texture().get_image().save_png("res://builds/" + tab_name + "-scroll-fixed.png")
	menu.queue_free()
	await process_frame
	commerce.inventory.clear(); GameServices.progression().state.clear()
	print("Journey scrolling and populated card showcase: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func touch(local: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 0; event.pressed = pressed
	event.position = root.get_final_transform() * scroll.get_global_transform_with_canvas() * local
	Input.parse_input_event(event)
	await process_frame

func drag(local: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 0
	event.position = root.get_final_transform() * scroll.get_global_transform_with_canvas() * local
	Input.parse_input_event(event)
	await process_frame

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
