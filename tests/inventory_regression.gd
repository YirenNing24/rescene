extends SceneTree
var failures: int = 0
var menu: ResceneMainMenu

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var commerce: CommerceService = GameServices.commerce()
	commerce.catalog = [{"id":"energy_drink","price":100,"stock":10000,"available":true,"max_quantity":10}]
	commerce.inventory = [{"id":"energy_drink","quantity":2}]
	GameServices.progression().state = {"energy":{"current":9},"starlight_token":{"enabled":true}}
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu); current_scene = menu
	menu._open_destination("SHOP")
	var market: MarketplaceView = menu._dialog as MarketplaceView
	market.open_item(MarketCatalog.find_item("energy_drink"))
	check(not market._checkout.disabled and market._checkout.text.contains("100 STARL"), "Only live server listings enable checkout")
	market.set_quantity(99)
	check(market._quantity == 10 and market._total_label.text == "1000", "Server maximum quantity and price must drive checkout")
	market.set_quantity(1)
	market._checkout_pressed()
	check(market._checkout.text.contains("CONFIRM"), "Purchase needs an explicit price confirmation")
	commerce.operation = {"status":"pending","kind":"buy"}
	commerce.changed.emit()
	check(market._checkout.disabled, "Duplicate clicks while pending must be blocked")
	commerce.operation.clear()
	market.open_item(MarketCatalog.find_item("scene_01"))
	check(market._checkout.disabled, "Unminted cards must remain previews")
	menu._open_inventory()
	var inventory: InventoryView = menu._dialog as InventoryView
	check(inventory._balance.text == "2 OWNED" and not inventory._use.disabled, "Confirmed ownership is shown in Inventory")
	inventory._use_pressed()
	check(inventory._use.text.contains("CONFIRM"), "Consumption needs confirmation")
	GameServices.progression().state = {"energy":{"current":15}}
	inventory._render()
	check(inventory._use.disabled and inventory._use.text == "ENERGY FULL", "Full energy keeps the drink")
	GameServices.progression().state = {"energy":{"current":9}}
	commerce.inventory = [{"id":"energy_drink","quantity":0}]
	inventory._render()
	check(inventory._use.disabled, "Unowned items cannot be used")
	commerce.inventory = [{"id":"energy_drink","quantity":2}]
	menu._rebuild()
	await process_frame
	check(menu._dialog is InventoryView, "Inventory stays open after resize")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		var _saved: Error = root.get_texture().get_image().save_png("res://previews/inventory-20-9.png")
	menu.queue_free()
	commerce.catalog.clear(); commerce.inventory.clear(); GameServices.progression().state.clear()
	await create_timer(0.2).timeout
	print("Inventory, live checkout confirmation, quantity, ownership and full-energy gates: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
