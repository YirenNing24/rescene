class_name MarketplaceView
extends MenuDestination
## Only server-listed items may open checkout. Concept products stay previews.

var category: String = "featured"
var release_id: String = ""
var _release_filter: OptionButton
var query: String = ""
var sort_index: int = 0
var _products: Array[Dictionary] = []
var _category_buttons: Dictionary[String, Button] = {}
var _scroll: MarketGridScroll
var _grid: VBoxContainer
var _hero: Control
var _section: Label
var _count: Label
var _empty: Label
var _detail: Control
var _selected: Dictionary = {}
var _quantity: int = 1
var _quantity_label: Label
var _total_label: Label
var _minus: Button
var _plus: Button
var _checkout: Button
var _search: LineEdit
var _sort: OptionButton
var _footer: Label
var _notice: Label
var _confirming: bool = false
var _catalog_signature: String = ""

func _ready() -> void:
	name = "MarketplaceView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var shield: Panel = host._panel(body, Rect2(30, 155, host._width - 60, 885), Color("141529"), Color(0.72, 0.68, 0.95, 0.32), 26)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_header()
	_navigation()
	_feature()
	_section = host._label(body, "", Rect2(350, 535, 1000, 34), 24, host.WHITE, host.BOLD)
	_count = host._label(body, "", Rect2(host._width - 500, 540, 430, 27), 14, host.MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	_empty = host._label(body, "No items found.\nTry another search or category.", Rect2(550, 500, host._width - 800, 140), 28, host.MUTED, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
	_footer = host._label(body, "Collect release-specific LE cards, refinement items and Energy Drinks. Card packs are previews.", Rect2(350, 1008, host._width - 430, 25), 13, host.MUTED)
	var releases: OptionButton = OptionButton.new()
	_release_filter = releases
	releases.name = "MarketReleaseFilter"
	releases.fit_to_longest_item = false
	releases.add_item("All releases")
	for entry: Dictionary in CardReleases.RELEASES:
		releases.add_item(str(entry.name))
		if str(entry.set_id) == release_id: releases.select(releases.item_count - 1)
	releases.add_theme_font_size_override("font_size", 18)
	host._at(body, releases, Rect2(host._width - 1000, 527, 450, 48))
	var _release_connection: int = releases.item_selected.connect(func(index: int) -> void:
		release_id = "" if index == 0 else str(CardReleases.RELEASES[index-1].set_id)
		if index > 0: category = "cards"
		_render_products())
	_render_products()
	_refresh_marketplace.call_deferred()
	var _commerce_connection: int = GameServices.commerce().changed.connect(_commerce_changed)
	GameServices.commerce().refresh.call_deferred()
	var _inventory: Button = host._button(body, "INVENTORY  →", Rect2(58, 944, 254, 64), host._open_inventory)
	_inventory.add_theme_font_size_override("font_size", 17)

func _commerce_changed() -> void:
	if not is_instance_valid(_footer): return
	var commerce: CommerceService = GameServices.commerce()
	_footer.text = commerce.message if not commerce.message.is_empty() else "Collect release-specific LE cards, refinement items and Energy Drinks. Card packs are previews."
	var signature: String = JSON.stringify(commerce.catalog)
	if signature != _catalog_signature:
		_catalog_signature = signature
		var offset: int = _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
		_render_products()
		_scroll.set_deferred("scroll_vertical", offset)
	_update_checkout()

func _update_checkout() -> void:
	if not is_instance_valid(_checkout): return
	var commerce: CommerceService = GameServices.commerce()
	var product: Dictionary = commerce.product(str(_selected.get("id", "")))
	var available: bool = StrictData.boolean(product.get("available", false))
	_checkout.disabled = not available or commerce.pending() or (str(product.get("generation", "")) != "individual_randomized" and _quantity > StrictData.integer(product.get("stock", 0)))
	if not available: _checkout.text = "SOLD OUT" if product.has("initial_allocation") and StrictData.integer(product.get("stock", 0)) == 0 else "CURRENTLY UNAVAILABLE" if not product.is_empty() else "PURCHASES COMING SOON"
	elif commerce.pending(): _checkout.text = "PROCESSING…"
	else: _checkout.text = ("CONFIRM · %d STARL" if _confirming else "BUY · %d STARL") % (_quantity * StrictData.integer(product.get("price", 0)))
	if available:
		_total_label.text = str(_quantity * StrictData.integer(product.get("price", 0)))
		if _confirming: _notice.text = "Pay %s STARL for %d × %s? Tap Confirm to purchase." % [_total_label.text, _quantity, str(_selected.get("name", "item"))]
		elif str(_selected.get("category", "")) == "cards": _notice.text = "%d / 50 left in this initial sale · Future admin mints & artwork reissues allowed." % StrictData.integer(product.get("stock", 0)) if product.has("initial_allocation") else "One unique LE card with permanent random stats and one skill. Equip it in the matching release and member slot."
		elif str(_selected.get("category", "")) == "upgrades": _notice.text = "Refinement-only card XP. Level attempts can fail; review the odds in Collection."
		else: _notice.text = "100 STARL each · +5 energy when used · Items arrive after confirmation."
		if commerce.pending(): _notice.text = commerce.message

func _checkout_pressed() -> void:
	if _checkout.disabled: return
	if not _confirming: _confirming = true; _update_checkout(); return
	_confirming = false
	GameServices.commerce().purchase.call_deferred(str(_selected.get("id", "")), _quantity)

func _refresh_marketplace() -> void:
	if not GameServices.session().is_authenticated(): return
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/marketplace")
	if not is_instance_valid(_footer) or not StrictData.boolean(response.get("ok", false)): return
	var marketplace: Dictionary = StrictData.dictionary(StrictData.dictionary(response.get("data")).get("marketplace"))
	if str(marketplace.get("status", "")) == "connected" and str(marketplace.get("total_listings", "")) == "0":
		_footer.text = "COLLECTION OPENS SOON  ·  No items listed yet. Explore the preview collection."

func _header() -> void:
	var back: Button = host._button(body, "", Rect2(58, 181, 66, 64), go_back)
	back.name = "MarketplaceBack"
	var arrow: TextureRect = host._icon(back, "arrow", Rect2(17, 16, 32, 32))
	arrow.rotation = PI
	arrow.pivot_offset = Vector2(16, 16)
	var _title: Label = host._label(body, "MARKETPLACE", Rect2(150, 185, 730, 44), 34, host.WHITE, host.BOLD)
	var _subtitle: Label = host._label(body, "LITTLE THINGS. YOUR NEXT BIG SCENE.", Rect2(153, 239, 1100, 25), 13, host.LILAC)
	_search = LineEdit.new()
	_search.name = "MarketSearch"
	_search.placeholder_text = "Search items"
	_search.text = query
	_search.add_theme_font_override("font", host.FONT)
	_search.add_theme_font_size_override("font_size", 20)
	_search.add_theme_color_override("font_color", host.WHITE)
	_search.add_theme_color_override("font_placeholder_color", host.MUTED)
	_search.add_theme_stylebox_override("normal", host._style(Color("1e1d34"), Color(host.LILAC, 0.32), 18))
	_search.add_theme_stylebox_override("focus", host._style(Color("25213c"), host.LILAC, 18))
	host._at(body, _search, Rect2(host._width - 1020, 186, 625, 62))
	var _search_connection: int = _search.text_changed.connect(func(value: String) -> void: query = value; _render_products())
	_sort = OptionButton.new()
	_sort.name = "MarketSort"
	for label: String in ["Featured first", "Price: low to high", "Price: high to low"]: _sort.add_item(label)
	_sort.selected = sort_index
	_sort.add_theme_font_size_override("font_size", 17)
	host._at(body, _sort, Rect2(host._width - 375, 186, 305, 62))
	var _sort_connection: int = _sort.item_selected.connect(func(index: int) -> void: sort_index = index; _render_products())

func _navigation() -> void:
	for index: int in MarketCatalog.CATEGORIES.size():
		var entry: Dictionary = MarketCatalog.CATEGORIES[index]
		var button: Button = host._button(body, "", Rect2(58, 300 + index * 88, 254, 70), func() -> void: set_category(str(entry.id)))
		button.name = "MarketCategory_" + str(entry.id)
		var _icon: TextureRect = host._icon(button, str(entry.icon), Rect2(20, 22, 26, 26), host.LILAC)
		var _label: Label = host._label(button, str(entry.label), Rect2(63, 21, 178, 31), 20, host.WHITE, host.BOLD)
		_category_buttons[str(entry.id)] = button
	host._line(body, Rect2(76, 786, 214, 1), Color(host.LILAC, 0.18))
	var _collection: Label = _wrapped(body, "Collect a little\nstarlight.", Rect2(78, 824, 220, 105), 31, host.LILAC, host.ITALIC)

func _feature() -> void:
	_hero = Control.new()
	host._at(body, _hero, Rect2(350, 290, host._width - 420, 218))
	var width: float = _hero.size.x
	var _panel: Panel = host._panel(_hero, Rect2(0, 0, width, 218), Color("2b2744"), Color(host.LILAC, 0.34), 22)
	var _eyebrow: Label = host._label(_hero, "NINE RELEASES / FIVE VOICES", Rect2(32, 25, width - 750, 24), 13, host.LILAC, host.BOLD)
	var _headline: Label = host._label(_hero, "A new scene to collect.", Rect2(28, 60, width - 750, 72), 52, host.WHITE, host.ITALIC)
	var _copy: Label = host._label(_hero, "Photo cards, foil packs, and little boosts for your next stage.", Rect2(33, 143, width - 730, 34), 18, host.MUTED)
	var browse: Button = host._button(_hero, "EXPLORE CARDS  →", Rect2(width - 393, 141, 352, 50), func() -> void: set_category("cards"))
	browse.name = "ExploreMarketCards"
	browse.add_theme_font_size_override("font_size", 15)
	for index: int in 3:
		var artwork: MarketArtwork = MarketArtwork.new()
		artwork.host = host
		artwork.item = MarketCatalog.find_item(str(["scene_01", "le_scenedrome_03", "le_dearest_05"][index]))
		host._at(_hero, artwork, Rect2(width - 800 + index * 142, -7 + absf(float(index - 1)) * 10.0, 235, 225))
	var _badge: Label = host._label(_hero, "45 LE CARDS\nNINE RELEASES", Rect2(width - 330, 28, 270, 60), 18, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)

func set_category(value: String) -> void:
	category = value
	if category not in ["cards", "featured"]:
		release_id = ""; _release_filter.select(0)
	_render_products()

func snapshot() -> Dictionary:
	return {"release_id":release_id, "category":category, "query":query, "sort_index":sort_index, "scroll":_scroll.scroll_vertical,
		"item_id":str(_selected.get("id", "")) if is_instance_valid(_detail) else "", "quantity":_quantity}

func restore_detail(saved: Dictionary) -> void:
	_scroll.get_v_scroll_bar().set_deferred("value", StrictData.number(saved.get("scroll", 0)))
	var item: Dictionary = MarketCatalog.find_item(str(saved.get("item_id", "")))
	if not item.is_empty():
		open_item(item)
		set_quantity(StrictData.integer(saved.get("quantity", 1)))

func _render_products() -> void:
	if not is_instance_valid(_hero): return
	if is_instance_valid(_scroll): _scroll.hide(); _scroll.queue_free()
	_products = MarketCatalog.filtered(category, query, sort_index, release_id)
	var featured: bool = category == "featured" and query.strip_edges().is_empty()
	_hero.visible = featured
	var title_y: float = 535.0 if featured else 296.0
	_section.position.y = title_y
	_count.position.y = title_y + 5.0
	_release_filter.position.y = title_y - 8.0
	_release_filter.visible = category in ["cards", "featured"]
	for entry: Dictionary in MarketCatalog.CATEGORIES:
		var active: bool = category == entry.id
		_category_buttons[str(entry.id)].add_theme_stylebox_override("normal", host._style(Color("393051") if active else Color("1b1b30"), Color(host.LILAC, 0.65 if active else 0.14), 16))
		if active: _section.text = "CURATED FOR YOU" if featured else str(entry.label).to_upper()
	_count.text = "%02d ITEMS  /  STARLIGHT" % _products.size()
	_empty.visible = _products.is_empty()
	_scroll = MarketGridScroll.new()
	_scroll.name = "MarketplaceGrid"
	_scroll.interaction_allowed = func() -> bool: return not is_instance_valid(_detail)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.get_v_scroll_bar().custom_minimum_size.x = 8
	_scroll.row_height = 348.0
	_scroll.row_step = 368.0
	_scroll.row_count = ceili(float(_products.size()) / 4.0)
	_scroll.item_count = _products.size()
	var grid_width: float = host._width - 430.0
	var tile_width: float = (grid_width - 16.0 - 60.0) / 4.0
	_scroll.tile_width = tile_width
	_scroll.column_step = tile_width + 20.0
	var top: float = title_y + 55.0
	host._at(body, _scroll, Rect2(350, top, grid_width, 991.0 - top))
	var _tap_connection: int = _scroll.item_tapped.connect(func(index: int) -> void:
		if index >= 0 and index < _products.size(): open_item(_products[index]))
	_grid = VBoxContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("separation", 20)
	_scroll.add_child(_grid)
	var row: Control
	for index: int in _products.size():
		if index % 4 == 0:
			row = Control.new()
			row.custom_minimum_size = Vector2(grid_width - 16, 348)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.add_child(row)
		_tile(row, _products[index], Rect2((index % 4) * (tile_width + 20), 0, tile_width, 348))

func _tile(parent: Control, item: Dictionary, rect: Rect2) -> void:
	var accent: Color = Color(str(item.accent))
	var tile: Button = host._button(parent, "", rect, func() -> void: open_item(item))
	tile.name = "MarketItem_" + str(item.id)
	tile.tooltip_text = str(item.name)
	tile.add_theme_stylebox_override("normal", host._style(Color("202036"), Color(accent, 0.23), 19))
	tile.add_theme_stylebox_override("hover", host._style(Color("2c2845"), Color(accent, 0.85), 19))
	var live: bool = StrictData.boolean(GameServices.commerce().product(str(item.id)).get("available", false))
	var _tag: Label = host._label(tile, ("LIVE · " if live else "") + str(item.tag), Rect2(23, 18, rect.size.x - 46, 21), 12, accent, host.BOLD)
	var artwork: MarketArtwork = MarketArtwork.new()
	artwork.host = host
	artwork.item = item
	host._at(tile, artwork, Rect2(25, 42, rect.size.x - 50, 178))
	var title: Label = host._label(tile, str(item.name), Rect2(24, 229, rect.size.x - 48, 34), 24, host.WHITE, host.BOLD)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size.x = rect.size.x - 48
	host._line(tile, Rect2(24, 278, rect.size.x - 48, 1), Color(accent, 0.16))
	var _star: TextureRect = host._icon(tile, "star", Rect2(24, 299, 23, 23), accent)
	var _price: Label = host._label(tile, str(item.price), Rect2(58, 296, rect.size.x - 180, 31), 24, host.WHITE, host.BOLD)
	var _view: Label = host._label(tile, "VIEW  ↗", Rect2(rect.size.x - 113, 301, 88, 25), 13, accent, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)

func open_item(item: Dictionary) -> void:
	_close_detail()
	_confirming = false
	_selected = item
	_quantity = 1
	_scroll.reset_motion()
	_detail = Control.new()
	_detail.name = "MarketItemDetail"
	_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail)
	_detail.size = Vector2(host._width, 1080)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.015, 0.018, 0.045, 0.86)
	host._at(_detail, shade, Rect2(0, 0, host._width, 1080))
	var width: float = 1260.0
	var x: float = (host._width - width) * 0.5
	var window: Panel = host._panel(_detail, Rect2(x, 205, width, 690), Color("1c1c32"), Color(Color(str(item.accent)), 0.65), 26)
	var close: Button = host._icon_button(window, "close", Rect2(width - 78, 18, 58, 58), _close_detail)
	close.name = "CloseMarketItem"
	var _art_panel: Panel = host._panel(window, Rect2(32, 32, 410, 626), Color("29243f"), Color.TRANSPARENT, 19)
	var artwork: MarketArtwork = MarketArtwork.new()
	artwork.host = host
	artwork.item = item
	host._at(window, artwork, Rect2(45, 92, 384, 448))
	var _series: Label = host._label(window, "RESCÉNE  /  MARKETPLACE", Rect2(65, 591, 344, 27), 13, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var accent: Color = Color(str(item.accent))
	var _tag: Label = host._label(window, str(item.tag), Rect2(488, 47, 620, 27), 15, accent, host.BOLD)
	var title: Label = host._label(window, str(item.name), Rect2(484, 98, 676, 64), 39, host.WHITE, host.BOLD)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size.x = 676
	var _description: Label = _wrapped(window, str(item.description), Rect2(489, 188, 677, 100), 22, host.MUTED)
	var _contents: Label = host._label(window, str(item.contents), Rect2(489, 309, 677, 31), 23, accent, host.BOLD)
	var _detail_label: Label = _wrapped(window, str(item.detail), Rect2(489, 349, 677, 90), 16, host.MUTED)
	_minus = host._button(window, "−", Rect2(489, 445, 56, 54), func() -> void: set_quantity(_quantity - 1))
	_minus.name = "MarketQuantityMinus"
	_quantity_label = host._label(window, "1", Rect2(553, 457, 70, 31), 23, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_plus = host._button(window, "+", Rect2(630, 445, 56, 54), func() -> void: set_quantity(_quantity + 1))
	_plus.name = "MarketQuantityPlus"
	_minus.add_theme_stylebox_override("disabled", host._style(Color("252238"), Color(accent, 0.15), 16))
	_plus.add_theme_stylebox_override("disabled", host._style(Color("252238"), Color(accent, 0.15), 16))
	var _currency: TextureRect = host._icon(window, "star", Rect2(889, 456, 29, 29), accent)
	_total_label = host._label(window, "", Rect2(928, 451, 239, 40), 31, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_checkout = host._button(window, "PURCHASES COMING SOON", Rect2(489, 531, 679, 72), _checkout_pressed, true)
	_checkout.name = "MarketplaceCheckout"
	_checkout.disabled = true
	_checkout.add_theme_stylebox_override("disabled", host._style(Color("37314e"), Color(accent, 0.25), 18))
	_checkout.add_theme_color_override("font_disabled_color", accent)
	_notice = host._label(window, "Preview item. Purchases are not available yet.", Rect2(489, 626, 700, 26), 14, host.MUTED)
	set_quantity(1)

func set_quantity(value: int) -> void:
	_confirming = false
	var product: Dictionary = GameServices.commerce().product(str(_selected.get("id", "")))
	var maximum: int = StrictData.integer(product.get("max_quantity", 99))
	_quantity = clampi(value, 1, maximum)
	if not is_instance_valid(_quantity_label): return
	_quantity_label.text = str(_quantity)
	_total_label.text = str(StrictData.integer(_selected.get("price", 0)) * _quantity)
	_minus.disabled = _quantity == 1
	_plus.disabled = _quantity == maximum
	_update_checkout()

func _close_detail() -> void:
	if is_instance_valid(_detail): _detail.hide(); _detail.queue_free()
	_detail = null

func go_back() -> void:
	if is_instance_valid(_detail): _close_detail()
	else: host._close_dialog()

func _wrapped(parent: Control, text: String, rect: Rect2, font_size: int, tint: Color, font: Font = null) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_font_override("font", font if font != null else host.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	host._at(parent, label, rect)
	return label
