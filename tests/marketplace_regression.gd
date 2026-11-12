extends SceneTree
## Real native mouse/touch shopping flow; storefront preview must never mutate balances.

var menu: ResceneMainMenu
var market: MarketplaceView
var failures: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var before: Dictionary = GameServices.progression().state.duplicate(true)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	menu._open_destination("SHOP")
	market = menu._dialog as MarketplaceView
	await create_timer(0.2).timeout
	check(market != null and market._products.size() == 52, "Shop must open the full marketplace catalog")
	check(is_instance_valid(menu._energy_label), "Marketplace must retain the existing resource HUD")
	for category: String in ["cards", "packs", "upgrades", "energy"]:
		market._category_buttons[category].pressed.emit()
		await process_frame
		check(not market._products.is_empty(), "Every requested category needs actual product previews")
		for item: Dictionary in market._products: check(str(item.category) == category, "Category must filter its products")
	market.set_category("featured")
	market._search.text = "resonance"
	market._search.text_changed.emit("resonance")
	await process_frame
	check(market._products.size() == 1 and str(market._products[0].id) == "resonance_core", "Search must match item titles")
	market._search.text = "no_such_item"
	market._search.text_changed.emit("no_such_item")
	await process_frame
	check(market._empty.visible and market._products.is_empty(), "Empty searches need a readable empty state")
	market._search.text = ""
	market._search.text_changed.emit("")
	market._sort.item_selected.emit(1)
	await process_frame
	for index: int in range(1, market._products.size()):
		check(StrictData.integer(market._products[index - 1].price) <= StrictData.integer(market._products[index].price), "Ascending price sort")
	market._sort.item_selected.emit(0)
	await process_frame
	await mouse_tap(Vector2(80, 245))
	check(is_instance_valid(market._detail) and str(market._selected.id) == "scene_01", "Native mouse tap must open the correct grid cell")
	check(market._checkout.disabled, "Preview checkout must remain disabled")
	market.set_quantity(3)
	check(market._total_label.text == "1350", "Quantity must update the displayed Starlight total")
	market.set_quantity(0)
	check(market._quantity == 1 and market._minus.disabled, "Quantity cannot drop below one")
	market.set_quantity(100)
	check(market._quantity == 99 and market._plus.disabled, "Quantity must have a bounded upper limit")
	market.go_back()
	await process_frame
	check(not is_instance_valid(market._detail) and is_instance_valid(menu._dialog), "Back from item details must retain the store")
	market.set_category("energy")
	await process_frame
	await touch_tap(Vector2(market._scroll.column_step + 80.0, 110))
	check(is_instance_valid(market._detail) and str(market._selected.id) == "energy_trio", "Touch must distinguish the second column")
	market.set_quantity(4)
	menu._rebuild()
	await process_frame
	market = menu._dialog as MarketplaceView
	check(market != null and market.category == "energy" and market._quantity == 4 and is_instance_valid(market._detail), "Rebuilding after resize must preserve store category and item details")
	market.go_back()
	market.set_category("featured")
	await process_frame
	await mouse_tap(Vector2(market._scroll.tile_width + 10.0, 110))
	check(not is_instance_valid(market._detail), "Tapping a grid gutter must not open an item")
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = point(Vector2(100, 120))
	Input.parse_input_event(wheel)
	await create_timer(0.7).timeout
	check(market._scroll._offset > 0.0 and not is_instance_valid(market._detail), "Wheel scrolling must browse products without selecting one")
	market._scroll.focus_index(0, true)
	await process_frame
	await swipe()
	check(not is_instance_valid(market._detail) and market._scroll._offset > 0.0, "Dragging a product must scroll rather than open it")
	check(GameServices.progression().state == before, "Browsing, quantity changes and item previews must not mutate progression or energy")
	market.go_back()
	await process_frame
	check(menu._dialog == null and is_instance_valid(menu._energy_label), "Back must return to the original lobby")
	print("Marketplace navigation, grid input and preview-only state: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func point(local: Vector2) -> Vector2:
	return root.get_final_transform() * market._scroll.get_global_transform_with_canvas() * local

func mouse_tap(local: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point(local)
		Input.parse_input_event(event)
		await process_frame

func touch_tap(local: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = point(local)
		Input.parse_input_event(event)
		await process_frame

func swipe() -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = point(Vector2(100, 250))
	Input.parse_input_event(touch)
	await process_frame
	for step: int in 5:
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 0
		drag.position = point(Vector2(100, 210 - step * 35))
		Input.parse_input_event(drag)
		await process_frame
	touch = touch.duplicate()
	touch.pressed = false
	touch.position = point(Vector2(100, 70))
	Input.parse_input_event(touch)
	await create_timer(0.3).timeout

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
