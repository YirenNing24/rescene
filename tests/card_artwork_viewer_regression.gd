extends SceneTree
## Real input coverage for artwork versus item actions and scrolling.

var failures: int = 0
var menu: ResceneMainMenu


func _initialize() -> void:
	verify.call_deferred()


func verify() -> void:
	var commerce: CommerceService = GameServices.commerce()
	for index: int in 12:
		commerce.inventory.append({"id":"pulse_%d" % (100 + index), "token_id":str(100 + index), "template_id":"le_scenedrome_02", "category":"cards", "set_id":"scenedrome", "series":"SCENEDROME", "member":"Liv", "member_name":"Liv", "member_index":1, "quantity":1, "level":12, "stars":2, "stats":{}})
	commerce.decks = {"scenedrome":["", "pulse_100", "", "", ""]}
	commerce.equipped_card = "pulse_100"
	var before: Array[Dictionary] = commerce.inventory.duplicate(true)
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.35).timeout
	menu._open_marketplace()
	var market: MarketplaceView = menu._dialog as MarketplaceView
	market.open_item(MarketCatalog.find_item("scene_02"))
	market.set_quantity(3)
	await process_frame
	var art_button: Button = market._detail.find_child("EnlargeCardArtwork", true, false) as Button
	check(art_button != null, "Shop detail artwork must offer enlargement")
	await click(art_button.get_global_transform_with_canvas() * (art_button.size * 0.5))
	check(menu.card_viewer_open() and menu._card_viewer.item_id == "scene_02", "Tapping the pictured card opens that artwork")
	if not menu.card_viewer_open(): quit(1); return
	check(menu._card_viewer._artwork.size.y > 900.0, "Viewer must use nearly the full screen height")
	var close_button: Button = menu._card_viewer._close_button
	var close_icon: TextureRect = close_button.get_child(0) as TextureRect
	check(close_icon.get_rect().get_center().distance_to(close_button.size * 0.5) < 0.1, "Close icon must stay centered inside its actual button size")
	await snap("card-artwork-viewer-pulse.png")
	await cancel()
	check(not menu.card_viewer_open() and is_instance_valid(market._detail) and market._quantity == 3, "Back closes only the artwork and preserves checkout state")
	market._close_detail()
	market.set_category("cards")
	await process_frame
	var grid_point: Vector2 = market._scroll.get_global_transform_with_canvas() * Vector2(100, 100)
	await touch_tap(grid_point)
	check(menu.card_viewer_open() and not is_instance_valid(market._detail), "Shop grid image taps enlarge without entering checkout")
	var offset: float = market._scroll._offset
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = root.get_final_transform() * grid_point
	Input.parse_input_event(wheel)
	await create_timer(0.15).timeout
	check(is_equal_approx(offset, market._scroll._offset), "Enlargement blocks background grid scrolling")
	await click(Vector2(200, 500))
	check(not menu.card_viewer_open() and is_instance_valid(menu._dialog), "Tapping outside dismisses artwork without leaving the store")
	menu._open_collection()
	var collection: CollectionView = menu._dialog as CollectionView
	collection.selected_set = "scenedrome"
	collection._render()
	await process_frame
	art_button = collection.body.find_child("EnlargeCardArtwork", true, false) as Button
	await click(art_button.get_global_transform_with_canvas() * (art_button.size * 0.5))
	check(menu.card_viewer_open() and menu._card_viewer.item_id == "pulse_100" and not collection.inventory_mode, "Equipped artwork enlarges without changing the deck")
	await cancel()
	collection.inventory_mode = true
	collection._render()
	await process_frame
	var inventory: MarketGridScroll = collection.body.get_node("IndividualCardInventory") as MarketGridScroll
	await touch_tap(inventory.get_global_transform_with_canvas() * Vector2(100, 100))
	check(menu.card_viewer_open() and menu._card_viewer.item_id == "pulse_100" and collection.selected_id.is_empty(), "Inventory artwork preserves the unique card identity and selection")
	await snap("card-artwork-viewer-scenedrome.png")
	await cancel()
	await touch_tap(inventory.get_global_transform_with_canvas() * Vector2(100, 470))
	check(collection.selected_id == "pulse_100" and not menu.card_viewer_open(), "Inventory details remain accessible outside the image")
	await process_frame
	art_button = collection.body.find_child("EnlargeCardArtwork", true, false) as Button
	await click(art_button.get_global_transform_with_canvas() * (art_button.size * 0.5))
	check(menu.card_viewer_open(), "Owned card details support the same viewer")
	menu._close_dialog()
	await process_frame
	check(not menu.card_viewer_open(), "Leaving the source screen removes its viewer")
	menu._open_profile()
	await process_frame
	var favorite: MemberCardArt = menu._profile_view.body.find_child("FavoriteCollectible", true, false) as MemberCardArt
	check(favorite != null, "Profile fixture shows its favorite card")
	art_button = favorite.get_node("EnlargeCardArtwork") as Button
	await click(art_button.get_global_transform_with_canvas() * (art_button.size * 0.5))
	check(menu.card_viewer_open() and menu._card_viewer.item_id == "pulse_100", "Profile artwork opens the matching owned card")
	check(not quit_on_go_back, "Android Back must not exit the app while artwork is open")
	menu._card_viewer.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(not menu.card_viewer_open() and quit_on_go_back, "Android Back closes the viewer and restores the prior window behavior")
	check(commerce.inventory == before, "Artwork browsing never changes cards, stats or quantities")
	menu.queue_free()
	await create_timer(0.2).timeout
	print("Card artwork viewer, unique identities and safe menu input: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)


func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = root.get_final_transform() * point
		Input.parse_input_event(event)
		await process_frame


func touch_tap(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.position = root.get_final_transform() * point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func cancel() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func snap(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/" + filename)


func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
