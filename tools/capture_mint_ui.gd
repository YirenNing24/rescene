extends SceneTree
## Local-only visual review; fixture data never reaches an account or checkout.


func _initialize() -> void:
	OS.set_environment("RESCENE_AUTH_FILE", "user://__palette_preview.txt")
	capture.call_deferred()


func capture() -> void:
	var auth: ResceneAuthScreen = (load("res://scenes/auth_screen.tscn") as PackedScene).instantiate()
	root.add_child(auth)
	current_scene = auth
	await create_timer(0.3).timeout
	auth._username.text = "remineplayer"
	auth._password.text = "preview-only"
	await snap("mint-login.png")
	auth.queue_free()
	await process_frame
	GameServices.progression().state = {"level":3,"level_xp":266,"level_cost":400,"starlight":363,"clears":4,"max_combo":134,"energy":{"current":15,"max":15},"missions":[
		{"id":"opening","name":"Today's opening act","scope":"daily","description":"Clear one song.","target":1,"progress":1,"xp":75,"starlight":50,"claimed":false},
		{"id":"encore","name":"A little encore","scope":"daily","description":"Clear three songs.","target":3,"progress":2,"xp":150,"starlight":75,"claimed":false}],"unlocks":[]}
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.6).timeout
	await snap("mint-lobby.png")
	menu._open_songs()
	await snap("mint-song-selection.png")
	menu._open_progression()
	await snap("mint-missions.png")
	GameServices.commerce().catalog = [{"id":"scene_02","price":450,"available":true,"stock":50,"max_quantity":1,"generation":"individual_randomized","initial_allocation":50}]
	menu._open_marketplace()
	(menu._dialog as MarketplaceView).open_item(MarketCatalog.find_item("scene_02"))
	await snap("mint-checkout.png")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()


func snap(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var saved: Error = root.get_texture().get_image().save_png("res://previews/" + filename)
	if saved != OK: push_error("Could not save palette preview")
