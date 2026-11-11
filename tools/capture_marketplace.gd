extends SceneTree
## Storefront UI review without an account, purchases or network requests.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.6).timeout
	menu._open_destination("SHOP")
	var market: MarketplaceView = menu._dialog as MarketplaceView
	await save("marketplace-20-9.png")
	market.set_category("cards")
	await save("marketplace-cards-20-9.png")
	market.open_item(MarketCatalog.find_item("encore_pack"))
	await save("marketplace-pack-detail-20-9.png")
	market.go_back()
	market.set_category("energy")
	await save("marketplace-energy-20-9.png")
	market.open_item(MarketCatalog.find_item("energy_drink"))
	await save("marketplace-energy-detail-20-9.png")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()

func save(filename: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://previews/" + filename)
	if error != OK: push_error("Could not capture marketplace: " + filename)
