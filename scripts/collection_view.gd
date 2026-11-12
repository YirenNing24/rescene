class_name CollectionView
extends MenuDestination

var selected_id: String = ""
var selected_set: String = "pulse"
var selected_member: int = -1
var archived: bool = false
var inventory_mode: bool = false
var _enhancing: bool = false
var _stars: bool = false
var _material_id: String = "prism_shards"
var _donors: Array[String] = []
var _quote: Dictionary = {}
var _payload: Dictionary = {}
var _quoting: bool = false

func _ready() -> void:
	name = "CollectionView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _connection: int = GameServices.commerce().changed.connect(_render)
	_render()
	GameServices.commerce().refresh.call_deferred()

func state() -> Dictionary:
	return {"selected_id":selected_id, "selected_set":selected_set, "selected_member":selected_member, "archived":archived, "inventory_mode":inventory_mode, "enhancing":_enhancing, "stars":_stars, "donors":_donors.duplicate()}

func restore(value: Dictionary) -> void:
	selected_id = str(value.get("selected_id", "")); selected_set = str(value.get("selected_set", "pulse"))
	selected_member = StrictData.integer(value.get("selected_member", -1)); archived = StrictData.boolean(value.get("archived", false)); inventory_mode = StrictData.boolean(value.get("inventory_mode", false))
	_enhancing = StrictData.boolean(value.get("enhancing", false)); _stars = StrictData.boolean(value.get("stars", false))
	_donors.clear()
	for donor: Variant in StrictData.array(value.get("donors", [])): _donors.append(str(donor))

func _render() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(body): body.hide(); body.queue_free()
	body = Control.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(body)
	var panel: Panel = host._panel(body, Rect2(30, 155, host._width - 60, 885), Color("141529"), Color(host.LILAC, 0.32), 26)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var _back: Button = host._button(body, "←", Rect2(58, 184, 66, 64), _back_pressed)
	var _title: Label = host._label(body, "YOUR COLLECTION", Rect2(150, 186, 700, 48), 34, host.WHITE, host.BOLD)
	var selector: OptionButton = OptionButton.new(); selector.name = "SongSetSelector"
	selector.fit_to_longest_item = false
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selector.clip_text = true
	for entry: Dictionary in SongSets.SETS: selector.add_item(str(entry.name))
	for index: int in SongSets.SETS.size():
		if str(SongSets.SETS[index].id) == selected_set: selector.select(index)
	var _set_connection: int = selector.item_selected.connect(func(index: int) -> void:
		selected_set = str(SongSets.SETS[index].id); selected_id = ""; selected_member = -1; inventory_mode = false; archived = false; _quote.clear(); _render())
	host._at(body, selector, Rect2(790, 188, 410, 64))
	var _inventory: Button = host._button(body, "SET DECK" if inventory_mode else "ALL SET CARDS", Rect2(1224, 188, 310, 64), func() -> void: inventory_mode = not inventory_mode; selected_id = ""; selected_member = -1; archived = false; _render())
	var _archive: Button = host._button(body, "SET DECK" if archived else "ARCHIVE", Rect2(host._width - 676, 188, 218, 64), func() -> void: archived = not archived; selected_id = ""; _render())
	var _shop: Button = host._button(body, "MARKETPLACE  →", Rect2(host._width - 434, 188, 364, 64), host._open_marketplace)
	var set_data: Dictionary = SongSets.find_set(selected_set)
	var songs: Array = StrictData.array(set_data.get("songs", []))
	var titles: PackedStringArray = []
	for title: Variant in songs:
		var _title_added: bool = titles.append(str(title))
	var subtitle: Label = host._label(body, "FIRST SCENE ARCHIVE" if archived else "  ·  ".join(titles), Rect2(153, 270, host._width - 300, 30), 16, host.LILAC)
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var _message: Label = host._label(body, GameServices.commerce().message, Rect2(90, 995, host._width - 180, 28), 16, host.LILAC)
	if selected_id.is_empty():
		if archived: _archive_grid()
		elif inventory_mode: _inventory_grid()
		else: _deck_grid()
	else: _detail()
	if not _quote.is_empty(): _confirmation()

func _deck_grid() -> void:
	var commerce: CommerceService = GameServices.commerce()
	var deck: Array[String] = commerce.deck_ids(selected_set)
	var width: float = (host._width - 180 - 88) / 5.0
	var equipped: int = 0
	var team: Array[Dictionary] = []
	for index: int in 5:
		var id: String = deck[index]
		var details: Dictionary = commerce.item_details(id)
		if not details.is_empty(): equipped += 1; team.append(StrictData.dictionary(details.get("stats", {})))
		var tile: Button = host._button(body, "", Rect2(90 + index * (width + 22), 335, width, 585), _select_member.bind(index))
		tile.name = "DeckSlot_%d" % index
		tile.add_theme_stylebox_override("normal", host._style(Color("242039"), Color(host.LILAC, 0.42 if not details.is_empty() else 0.18), 20))
		var _member: Label = host._label(tile, SongSets.MEMBERS[index].to_upper(), Rect2(20, 21, width - 40, 30), 16, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		if not details.is_empty():
			var art: MemberCardArt = MemberCardArt.new(); art.host = host; art.item_id = id
			art.previewable = true
			host._at(tile, art, Rect2(18, 66, width - 36, 385))
			var _level: Label = host._label(tile, "LV. %d   %s" % [StrictData.integer(details.get("level", 1)), _star_text(StrictData.integer(details.get("stars", 1)))], Rect2(20, 473, width - 40, 30), 20, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
			var _skill: Label = host._label(tile, str(details.get("skill", "")), Rect2(20, 520, width - 40, 27), 16, host.LILAC, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var _symbol: Label = host._label(tile, "+", Rect2(20, 205, width - 40, 105), 75, Color(host.LILAC, 0.42), host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
			var _empty: Label = host._label(tile, "CHOOSE A CARD", Rect2(20, 462, width - 40, 30), 17, host.MUTED, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var stats: Dictionary = CardBoosts.combined(team)
	var _summary: Label = host._label(body, "%d / 5 EQUIPPED   ·   PERFECT SCORE +%.2f%%   ·   PERFECT RECOVERY +%.2f HP" % [equipped, StrictData.number(stats.perfect_score_bp) / 100.0, StrictData.number(stats.recovery_ppm) / 1000.0], Rect2(91, 949, host._width - 180, 30), 19, host.LILAC, host.BOLD)

func _select_member(index: int) -> void:
	selected_member = index; inventory_mode = true; selected_id = ""; _render()

func _inventory_grid() -> void:
	var cards: Array[Dictionary] = GameServices.commerce().cards_for_set(selected_set, selected_member)
	if cards.is_empty():
		var _empty: Label = host._label(body, "NO %sCARDS IN THIS SET YET" % ((SongSets.MEMBERS[selected_member].to_upper() + " ") if selected_member >= 0 else ""), Rect2(150, 500, host._width - 300, 60), 30, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		var _hint: Label = host._label(body, "Each member has their own slot. Cards from other song sets stay in their own inventory.", Rect2(150, 580, host._width - 300, 45), 19, host.MUTED, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var scroll: MarketGridScroll = MarketGridScroll.new(); scroll.name = "IndividualCardInventory"
	scroll.interaction_allowed = func() -> bool: return not host.card_viewer_open()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var width: float = (host._width - 180 - 96) / 5.0
	scroll.tile_width = width; scroll.column_step = width + 20.0; scroll.row_height = 565.0; scroll.row_step = 585.0; scroll.row_count = ceili(float(cards.size()) / 5.0); scroll.item_count = cards.size(); scroll.columns = 5
	scroll.artwork_rect = Rect2(14, 12, width - 28, 398)
	var _art_tap: int = scroll.item_art_tapped.connect(func(index: int) -> void:
		if index >= 0 and index < cards.size(): host._open_card_artwork(str(cards[index].id), scroll))
	var _tap: int = scroll.item_tapped.connect(func(index: int) -> void:
		if index >= 0 and index < cards.size(): selected_id = str(cards[index].id); _enhancing = false; _stars = false; _donors.clear(); _render())
	host._at(body, scroll, Rect2(90, 335, host._width - 180, 620))
	var rows: VBoxContainer = VBoxContainer.new(); rows.add_theme_constant_override("separation", 20); scroll.add_child(rows)
	var row: Control
	for index: int in cards.size():
		if index % 5 == 0: row = Control.new(); row.custom_minimum_size = Vector2(host._width - 200, 565); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; rows.add_child(row)
		var details: Dictionary = cards[index]
		var tile: Panel = host._panel(row, Rect2((index % 5) * (width + 20), 0, width, 565), Color("242039"), Color(host.LILAC, 0.28), 18)
		var art: MemberCardArt = MemberCardArt.new(); art.host = host; art.item_id = str(details.id)
		host._at(tile, art, Rect2(14, 12, width - 28, 398))
		var _name: Label = host._label(tile, "%s  #%s" % [str(details.get("member", "")), str(details.get("token_id", ""))], Rect2(22, 421, width - 44, 33), 23, host.WHITE, host.BOLD)
		var _level: Label = host._label(tile, "LV. %d  /  %s" % [StrictData.integer(details.get("level", 1)), _star_text(StrictData.integer(details.get("stars", 1)))], Rect2(22, 465, width - 44, 28), 17, host.LILAC, host.BOLD)
		var _skill: Label = host._label(tile, str(details.get("skill", "")) + ("  /  LOCKED" if StrictData.boolean(details.get("locked", false)) else ""), Rect2(22, 507, width - 44, 27), 15, host.MUTED)

func _archive_grid() -> void:
	var width: float = (host._width - 268) / 5.0
	for index: int in 5:
		var id: String = "legacy_scene_%02d" % (index + 1)
		var tile: Button = host._button(body, "", Rect2(90 + index * (width + 22), 335, width, 595), func() -> void: selected_id = id; _render())
		var art: MemberCardArt = MemberCardArt.new(); art.host = host; art.item_id = id
		art.previewable = true
		host._at(tile, art, Rect2(18, 20, width - 36, 450))
		var _name: Label = host._label(tile, SongSets.MEMBERS[index], Rect2(22, 487, width - 44, 35), 27, host.WHITE, host.BOLD)
		var _owned: Label = host._label(tile, "%d OWNED / COSMETIC" % GameServices.commerce().owned(id), Rect2(22, 540, width - 44, 28), 16, host.LILAC)

func _detail() -> void:
	var commerce: CommerceService = GameServices.commerce()
	var details: Dictionary = commerce.item_details(selected_id)
	var item: Dictionary = MarketCatalog.find_item(selected_id)
	var art: MemberCardArt = MemberCardArt.new(); art.host = host; art.item_id = selected_id
	art.previewable = true
	host._at(body, art, Rect2(100, 326, 620, 635))
	var _name: Label = host._label(body, str(details.get("member", item.get("member_name", ""))), Rect2(790, 330, 1000, 78), 62, host.WHITE, host.SERIF)
	var level: int = StrictData.integer(details.get("level", 1))
	var stars: int = StrictData.integer(details.get("stars", 1))
	var _identity: Label = host._label(body, "FIRST SCENE / COSMETIC" if archived else "%s  /  #%s   ·   LV. %d / 100   ·   %s" % [str(details.get("series", "")), str(details.get("token_id", "")), level, _star_text(stars)], Rect2(796, 425, host._width - 940, 32), 19, host.LILAC, host.BOLD)
	if archived:
		var _archive_note: Label = host._label(body, "Original First Scene collectibles remain in your wallet.\nThey do not provide gameplay bonuses or PULSE deck slots.", Rect2(796, 550, host._width - 940, 120), 24, host.MUTED)
		return
	if _enhancing: _refine_view(details); return
	if _stars: _star_view(details); return
	var lock: Button = host._button(body, "UNLOCK" if StrictData.boolean(details.get("locked", false)) else "LOCK CARD", Rect2(host._width - 355, 335, 235, 58), _toggle_lock)
	lock.disabled = commerce.pending(); lock.name = "LockIndividualCard"
	var stats: Dictionary = StrictData.dictionary(details.get("stats", {}))
	var width: float = (host._width - 960) * 0.5
	var _score_panel: Panel = host._panel(body, Rect2(795, 490, width, 105), Color("242039"), Color(host.LILAC, 0.22), 15)
	var _score_caption: Label = host._label(body, "PERFECT SCORE", Rect2(820, 508, width - 50, 25), 15, host.MUTED, host.BOLD)
	var _score: Label = host._label(body, "+%.2f%%" % (StrictData.number(stats.get("perfect_score_bp", 0)) / 100.0), Rect2(820, 542, width - 50, 42), 30, host.WHITE, host.BOLD)
	var _heal_panel: Panel = host._panel(body, Rect2(815 + width, 490, width, 105), Color("242039"), Color(host.LILAC, 0.22), 15)
	var _heal_caption: Label = host._label(body, "PERFECT RECOVERY / NOTE HEAD", Rect2(840 + width, 508, width - 50, 25), 15, host.MUTED, host.BOLD)
	var _heal: Label = host._label(body, "+%.2f HP" % (StrictData.number(stats.get("recovery_ppm", 0)) / 1000.0), Rect2(840 + width, 542, width - 50, 42), 30, host.WHITE, host.BOLD)
	var _skill_panel: Panel = host._panel(body, Rect2(795, 620, host._width - 940, 128), Color("242039"), Color(host.LILAC, 0.22), 15)
	var _skill: Label = host._label(body, str(details.get("skill", "")) + "  /  " + _star_text(stars), Rect2(820, 638, host._width - 990, 33), 23, host.LILAC, host.BOLD)
	var description: Label = host._label(body, str(details.get("skill_description", "")), Rect2(820, 682, host._width - 990, 56), 18, host.WHITE)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var member: int = StrictData.integer(details.get("member_index", 0))
	var equipped: bool = commerce.deck_ids(selected_set)[member] == selected_id
	var action_width: float = (host._width - 980) / 3.0
	var equip: Button = host._button(body, "REMOVE FROM SLOT" if equipped else "EQUIP · " + SongSets.MEMBERS[member].to_upper(), Rect2(795, 792, action_width, 75), _equip_card.bind(member, equipped), true)
	equip.name = "EquipMemberCard"; equip.disabled = commerce.pending()
	var refine: Button = host._button(body, "MAX LEVEL" if level >= 100 else "REFINE CARD", Rect2(813 + action_width, 792, action_width, 75), func() -> void: _enhancing = true; _render())
	refine.name = "EnhanceMemberCard"; refine.disabled = commerce.pending() or level >= 100
	var star: Button = host._button(body, "STAR UPGRADE", Rect2(831 + action_width * 2, 792, action_width, 75), func() -> void: _stars = true; _donors.clear(); _render())
	star.name = "StarUpgradeCard"; star.disabled = commerce.pending()
	var _note: Label = host._label(body, "Levels improve base stats by up to 20%. Stars strengthen the skill.\nXP comes only from refinement items. All five deck cards contribute; duplicate skills use the strongest star level.", Rect2(797, 911, host._width - 950, 65), 17, host.MUTED)

func _refine_view(details: Dictionary) -> void:
	var commerce: CommerceService = GameServices.commerce()
	var level: int = StrictData.integer(details.get("level", 1))
	var _xp: Label = host._label(body, "%d / %d XP   ·   NEXT LEVEL SUCCESS %.0f%%" % [StrictData.integer(details.get("training_xp", 0)), StrictData.integer(details.get("level_cost", 20)), StrictData.number(details.get("success_chance_bp", 0)) / 100.0], Rect2(796, 492, host._width - 940, 32), 20, host.LILAC, host.BOLD)
	for index: int in 3:
		var id: String = ["prism_shards", "resonance_core", "aurora_catalyst"][index]
		var product: Dictionary = commerce.product(id)
		var button: Button = host._button(body, "%s   /   +%d XP   /   %d OWNED" % [str(MarketCatalog.find_item(id).get("name", "")), StrictData.integer(product.get("training_xp", 0)), commerce.owned(id)], Rect2(796, 551 + index * 83, host._width - 940, 66), func() -> void: _material_id = id; _render())
		button.name = "Material_" + id
		button.add_theme_stylebox_override("normal", host._style(Color("3a2f55") if id == _material_id else Color("242039"), host.LILAC if id == _material_id else Color(host.LILAC, 0.22), 14))
		button.disabled = commerce.pending() or commerce.owned(id) < 1
	var confirm: Button = host._button(body, "REVIEW REFINEMENT", Rect2(796, 828, 675, 76), _review.bind("refine"), true)
	confirm.name = "ConfirmCardEnhancement"; confirm.disabled = commerce.pending() or _quoting or level >= 100 or commerce.owned(_material_id) < 1
	var _buy: Button = host._button(body, "GET REFINEMENT ITEMS", Rect2(1495, 828, host._width - 1640, 76), func() -> void: host._open_marketplace({"category":"upgrades"}))
	var _hint: Label = host._label(body, "One bundle grants XP and attempts one level if enough XP. Failure keeps XP and level; the bundle is consumed.", Rect2(797, 938, host._width - 950, 40), 17, host.MUTED)

func _star_view(details: Dictionary) -> void:
	var stars: int = StrictData.integer(details.get("stars", 1))
	var progress: int = StrictData.integer(details.get("star_progress", 0))
	var _progress: Label = host._label(body, "GUARANTEED  /  %d OF %d DONORS  /  %d SELECTED" % [progress, stars * 2 if stars < 5 else 0, _donors.size()], Rect2(796, 489, host._width - 940, 35), 20, host.LILAC, host.BOLD)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host._at(body, scroll, Rect2(796, 547, host._width - 940, 265))
	var list: VBoxContainer = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 10); scroll.add_child(list)
	for donor: Dictionary in GameServices.commerce().cards_for_set(selected_set):
		var id: String = str(donor.id)
		if id == selected_id: continue
		var protected: bool = StrictData.boolean(donor.get("locked", false)) or StrictData.boolean(donor.get("equipped", false)) or StrictData.boolean(donor.get("listed", false)) or StrictData.boolean(donor.get("in_use", false))
		var button: Button = Button.new(); button.custom_minimum_size = Vector2(0, 56)
		button.text = "%s  %s #%s  ·  LV. %d  ·  %s  ·  %d XP%s" % ["✓" if _donors.has(id) else "+", str(donor.get("member", "")), str(donor.get("token_id", "")), StrictData.integer(donor.get("level", 1)), _star_text(StrictData.integer(donor.get("stars", 1))), StrictData.integer(donor.get("training_xp", 0)), "  /  PROTECTED" if protected else ""]
		button.disabled = protected or GameServices.commerce().pending()
		var _donor_connection: int = button.pressed.connect(func() -> void:
			if _donors.has(id): _donors.erase(id)
			elif _donors.size() < 32: _donors.append(id)
			_render())
		list.add_child(button)
	var confirm: Button = host._button(body, "REVIEW · SACRIFICE %d CARDS" % _donors.size(), Rect2(796, 837, host._width - 940, 76), _review.bind("star"), true)
	confirm.name = "ReviewSacrifice"; confirm.disabled = _donors.is_empty() or _quoting or GameServices.commerce().pending()
	var _warning: Label = host._label(body, "Every donor counts as ONE. Its level, XP, stars, skill and progress are destroyed. Excess donors are also destroyed.", Rect2(797, 941, host._width - 950, 40), 17, Color("edbfd2"))

func _review(kind: String) -> void:
	if _quoting or GameServices.commerce().pending(): return
	_payload = {"kind":kind, "card_id":selected_id}
	if kind == "refine": _payload.item_id = _material_id
	if kind == "star": _payload.donors = _donors.duplicate()
	_quoting = true
	var expected: String = selected_id
	var quote: Dictionary = await GameServices.commerce().quote_card(_payload)
	_quoting = false
	if not is_inside_tree() or selected_id != expected: return
	_quote = quote; _render()

func _confirmation() -> void:
	var veil: ColorRect = ColorRect.new(); veil.color = Color(0.025, 0.02, 0.06, 0.82); host._at(body, veil, Rect2(0, 155, host._width, 885))
	var x: float = (host._width - 1360) * 0.5
	var _panel: Panel = host._panel(body, Rect2(x, 300, 1360, 650), Color("211d35"), Color(host.LILAC, 0.7), 24)
	var sacrifice: bool = str(_payload.get("kind", "")) == "star"
	var _title: Label = host._label(body, "PERMANENT SACRIFICE" if sacrifice else "CONFIRM REFINEMENT", Rect2(x + 50, 337, 1260, 47), 34, host.WHITE, host.BOLD)
	var summary: String = "★ %d → %d  /  RECEIVER PROGRESS AFTER: %d" % [StrictData.integer(_quote.get("stars_before", 1)), StrictData.integer(_quote.get("stars_after", 1)), StrictData.integer(_quote.get("star_progress_after", 0))] if sacrifice else "LEVEL %d → %d IF SUCCESSFUL  /  %.0f%% SUCCESS" % [StrictData.integer(_quote.get("level_before", 1)), StrictData.integer(_quote.get("level_after", 1)), StrictData.number(_quote.get("success_chance_bp", 0)) / 100.0]
	if not sacrifice and StrictData.integer(_quote.get("level_after", 1)) == StrictData.integer(_quote.get("level_before", 1)):
		summary = "+%d XP  /  MORE XP NEEDED BEFORE A LEVEL ATTEMPT" % StrictData.integer(_quote.get("xp_added", 0))
	var _summary: Label = host._label(body, summary, Rect2(x + 50, 406, 1260, 37), 23, host.LILAC, host.BOLD)
	var warning: RichTextLabel = RichTextLabel.new(); warning.name = "CardActionWarnings"; warning.add_theme_font_size_override("normal_font_size", 22); warning.add_theme_color_override("default_color", Color("edc6d6"))
	var lines: PackedStringArray = []
	for value: Variant in StrictData.array(_quote.get("warnings", [])):
		var _warning_added: bool = lines.append("• " + str(value))
	warning.text = "\n\n".join(lines); host._at(body, warning, Rect2(x + 50, 478, 1260, 290))
	var _cancel: Button = host._button(body, "CANCEL", Rect2(x + 50, 822, 450, 74), func() -> void: _quote.clear(); _render())
	var confirm: Button = host._button(body, "CONFIRM · DESTROY %d CARDS" % _donors.size() if sacrifice else "CONFIRM · USE 1 BUNDLE", Rect2(x + 525, 822, 785, 74), _confirm_action, true)
	confirm.name = "ConfirmIndividualCardAction"

func _confirm_action() -> void:
	var quote: Dictionary = _quote.duplicate(true); var payload: Dictionary = _payload.duplicate(true)
	_quote.clear(); _render()
	GameServices.commerce().card_action.call_deferred(payload, quote)

func _toggle_lock() -> void:
	var details: Dictionary = GameServices.commerce().item_details(selected_id)
	var payload: Dictionary = {"kind":"lock", "card_id":selected_id, "locked":not StrictData.boolean(details.get("locked", false))}
	var quote: Dictionary = await GameServices.commerce().quote_card(payload)
	if not quote.is_empty(): await GameServices.commerce().card_action(payload, quote)

func _equip_card(member: int, equipped: bool) -> void:
	var payload: Dictionary = {"kind":"equip", "set_id":selected_set, "member_index":member, "card_id":"" if equipped else selected_id}
	var quote: Dictionary = await GameServices.commerce().quote_card(payload)
	if not quote.is_empty(): await GameServices.commerce().card_action(payload, quote)

func _star_text(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, 5)) + "☆".repeat(5 - clampi(stars, 0, 5))

func _back_pressed() -> void:
	_quote.clear()
	if _enhancing or _stars: _enhancing = false; _stars = false; _render()
	elif not selected_id.is_empty(): selected_id = ""; _render()
	elif inventory_mode: inventory_mode = false; selected_member = -1; _render()
	else: go_back()
