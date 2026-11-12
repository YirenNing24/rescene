extends SceneTree
var failures: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var cards: Array[Dictionary] = CardReleases.templates()
	check(cards.size() == 45, "Nine releases contain all five members")
	var identities: Dictionary[String, bool] = {}
	for release: Dictionary in CardReleases.RELEASES:
		var filtered: Array[Dictionary] = MarketCatalog.filtered("cards", "", 0, str(release.set_id))
		check(filtered.size() == 5, "Every release filter returns five cards")
		for member: int in 5:
			var item: Dictionary = filtered[member]
			var id: String = str(item.id)
			check(not identities.has(id), "Template identities are unique")
			identities[id] = true
			check(str(item.member_name) == SongSets.MEMBERS[member], "Member order is stable")
			check(ResourceLoader.exists(CardReleases.artwork(item)), "Approved runtime artwork exists")
			check(str(MarketCatalog.find_item(id).set_id) == str(release.set_id), "Template lookup retains release")
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	var featured: FeaturedCardSets = menu._canvas.get_node("FeaturedCardSets") as FeaturedCardSets
	featured._timer.stop()
	check(featured._fan.get_child_count() == 5, "Featured Scene previews all five members")
	for index: int in CardReleases.RELEASES.size():
		check(featured.release_index == index, "Slideshow cycles through every release")
		check(featured._title.text.begins_with(str(CardReleases.RELEASES[index].name)), "Preview caption matches the set")
		featured.advance()
		await create_timer(0.35).timeout
		check(featured.get_children().filter(func(node: Node) -> bool: return node.name == "RetiringFan").is_empty(), "Crossfade releases old artwork")
	check(featured.release_index == 0, "Slideshow wraps to PULSE")
	featured.hide()
	featured.advance()
	check(featured.release_index == 0, "Hidden lobby does not advance its slideshow")
	featured.show()
	featured.advance()
	await create_timer(0.35).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var _lobby_saved: Error = root.get_texture().get_image().save_png("res://previews/featured-le-slideshow.png")
	featured.pressed.emit()
	check((menu._dialog as MarketplaceView).release_id == "re:scene", "Tapping a preview opens that release in the shop")
	featured.advance()
	check(featured.release_index == 1, "Slideshow pauses behind an open shop")
	menu._close_dialog()
	menu._open_marketplace()
	var market: MarketplaceView = menu._dialog as MarketplaceView
	await create_timer(0.2).timeout
	for index: int in CardReleases.RELEASES.size():
		market._release_filter.select(index+1)
		market._release_filter.item_selected.emit(index+1)
		await process_frame
		check(market._products.size() == 5, "Release dropdown filters the real storefront")
		check(market._release_filter.position.y < market._scroll.position.y, "Dropdown stays above the scroll grid")
	market._release_filter.select(3)
	market._release_filter.item_selected.emit(3)
	await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var _saved: Error = root.get_texture().get_image().save_png("res://previews/marketplace-scenedrome-cards.png")
	menu.queue_free()
	await process_frame
	print("45 release card identities, artwork and storefront filters: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
