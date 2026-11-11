class_name PlayerProfile
extends MenuDestination
## A full lobby destination. Account data comes from the existing session;
## the host refreshes the wallet once on entry, with no status polling.

const BACKDROP: Shader = preload("res://shaders/results_backdrop.gdshader")
const PORTRAIT_SHADE: Shader = preload("res://shaders/profile_portrait.gdshader")

signal return_requested

var public_data: Dictionary = {}
var tab: String = "info"
var _scroll: ScrollContainer
var _rendered_tab: String = ""
var _busy: bool = false
var _message: String = ""
var _message_label: Label
var _wallet_address: LineEdit
var _wallet_copy: Button
var _content_width: float
var _hero_x: float
var _selected_photo: int = 0
var _picker: FileDialog
var _photo_viewer: Control


func _ready() -> void:
	name = "PlayerProfile"
	mouse_filter = Control.MOUSE_FILTER_STOP
	if public_data.is_empty():
		var _int_1: int = GameServices.progression().changed.connect(_render)
		var _int_2: int = GameServices.session().wallet_updated.connect(_render)
		var _int_3: int = GameServices.scores().changed.connect(_render)
		var _cards_connection: int = GameServices.commerce().changed.connect(_render)
	var _media_connection: int = GameServices.photos().changed.connect(_render)
	var _social_connection: int = GameServices.social().changed.connect(_render)
	_render()
	modulate.a = 0.0
	var _propertytweener_4: PropertyTweener = create_tween().tween_property(self, "modulate:a", 1.0, 0.22)


func _render() -> void:
	var scroll_position: int = _scroll.scroll_vertical if is_instance_valid(_scroll) and _rendered_tab == tab else 0
	_rendered_tab = tab
	_scroll = null
	_wallet_address = null
	_wallet_copy = null
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	_hero_x = host._width - 865.0
	_content_width = _hero_x - 410.0
	_background()
	_header()
	_navigation()
	_showcase()
	match tab:
		"records": _records()
		"unlocks": _unlocks()
		"wallet": _wallet()
		"gallery": _gallery()
		_: _overview()
	_message_label = host._label(body, GameServices.photos().message if public_data.is_empty() and not GameServices.photos().message.is_empty() else _message, Rect2(355, 1018, _content_width, 27), 17, host.LILAC)
	if is_instance_valid(_scroll): _scroll.set_deferred("scroll_vertical", scroll_position)


func _background() -> void:
	var backdrop: TextureRect = TextureRect.new()
	backdrop.texture = host.ART
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = BACKDROP
	backdrop.material = shader_material
	host._at(body, backdrop, Rect2(0, 0, host._width, 1080))
	host._line(body, Rect2(302, 160, 1, 844), Color(host.LILAC, 0.14))
	host._line(body, Rect2(48, 136, host._width - 96, 1), Color(host.LILAC, 0.22))


func _header() -> void:
	var back: Button = host._button(body, "", Rect2(48, 42, 70, 65), go_back, false, false)
	back.name = "BackToMenu"
	back.tooltip_text = "Back"
	var arrow: TextureRect = host._icon(back, "arrow", Rect2(19, 17, 32, 32))
	arrow.rotation = PI
	arrow.pivot_offset = Vector2(16, 16)
	var _label_5: Label = host._label(body, "PLAYER PROFILE", Rect2(147, 43, 900, 48), 32, host.WHITE, host.BOLD)
	var _label_6: Label = host._label(body, "YOUR BACKSTAGE PASS", Rect2(150, 98, 800, 22), 12, host.LILAC)
	var _label_7: Label = host._label(body, "R E S C É N E   /   R H Y T H M", Rect2(host._width - 609, 57, 550, 28), 17, host.MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)


func _navigation() -> void:
	var destinations: Array = [["info", "person", "Info"], ["gallery", "album", "Gallery"], ["records", "music", "Records"], ["unlocks", "star", "Unlocks"], ["wallet", "gem", "Wallet"]]
	if not public_data.is_empty(): destinations = destinations.slice(0, 3)
	for index: int in destinations.size():
		var item: Array = destinations[index]
		var active: bool = tab == item[0]
		var button: Button = host._button(body, "", Rect2(48, 181 + index * 90, 224, 78), func() -> void: set_tab(str(item[0])), false, false)
		button.name = "Tab_" + str(item[0])
		if active:
			button.add_theme_stylebox_override("normal", host._style(Color(0.57, 0.48, 0.79, 0.23), Color(host.LILAC, 0.3), 16))
			host._line(button, Rect2(0, 20, 3, 38), host.LILAC)
		var _texturerect_8: TextureRect = host._icon(button,str(item[1]), Rect2(22, 24, 27, 27), host.LILAC if active else host.MUTED)
		var _label_9: Label = host._label(button,str(item[2]), Rect2(68, 22, 146, 33), 22, host.WHITE if active else host.MUTED, host.BOLD)
	if public_data.is_empty():
		var _collection: Button = host._button(body, "COLLECTION  →", Rect2(48, 667, 224, 65), host._open_collection)
		_collection.add_theme_font_size_override("font_size", 17)
		var security: Button = host._button(body, "SECURITY", Rect2(48, 749, 224, 60), host._open_account_security)
		security.name = "AccountSecurityButton"; security.add_theme_font_size_override("font_size", 16)
	var _label_10: Label = host._label(body, "YOUR MUSIC.\nYOUR MOMENT.", Rect2(67, 827, 210, 72), 24, Color(host.LILAC, 0.75), host.ITALIC)
	if GameServices.session().is_authenticated() and public_data.is_empty():
		var logout: Button = host._button(body, "LOG OUT", Rect2(48, 916, 224, 65), func() -> void: GameServices.session().logout())
		logout.name = "LogOut"
		logout.add_theme_font_size_override("font_size", 16)
	var _label_11: Label = host._label(body, "RESCÉNE RHYTHM", Rect2(66, 1021, 230, 25), 11, host.MUTED)


func set_tab(destination: String) -> void:
	if destination not in ["info", "gallery", "records", "unlocks", "wallet"]: return
	if not public_data.is_empty() and destination not in ["info", "gallery", "records"]: return
	tab = destination
	if public_data.is_empty(): host._profile_tab = destination
	_message = ""
	_render()


func _showcase() -> void:
	var width: float = host._width - _hero_x - 49
	var frame: Panel = host._panel(body, Rect2(_hero_x, 170, width, 835), Color("131425"), Color(host.LILAC, 0.28), 25)
	frame.name = "MemberShowcase"
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var photos: Array = StrictData.array(_media().get("gallery", []))
	if not photos.is_empty():
		_selected_photo = clampi(_selected_photo, 0, photos.size() - 1)
		var selected: Dictionary = StrictData.dictionary(photos[_selected_photo])
		_photo(frame, str(selected.get("url", "")), Rect2(2, 2, width - 4, 831), 24.0)
		var _shade: Panel = host._panel(frame, Rect2(2, 605, width - 4, 228), Color(0.045, 0.04, 0.095, 0.88), Color.TRANSPARENT, 0)
		var _caption: Label = host._label(frame, "YOUR GALLERY" if public_data.is_empty() else "PLAYER GALLERY", Rect2(34, 632, width - 68, 27), 15, host.LILAC, host.BOLD)
		var view: Button = host._button(frame, "VIEW PHOTO  ↗", Rect2(width - 253, 618, 220, 52), func() -> void: _view_photo(_selected_photo))
		view.add_theme_font_size_override("font_size", 15)
		for index: int in photos.size():
			var thumbnail: Button = host._button(frame, "", Rect2(34 + index * 93, 707, 80, 80), func() -> void: _selected_photo = index; _render())
			thumbnail.name = "GalleryShowcase_%d" % index
			_photo(thumbnail, str(StrictData.dictionary(photos[index]).get("url", "")), Rect2(4, 4, 72, 72), 12)
			if index == _selected_photo: thumbnail.add_theme_stylebox_override("normal", host._style(Color(host.LILAC, 0.25), host.LILAC, 15))
		var _count: Label = host._label(frame, "%02d / %02d" % [_selected_photo + 1, photos.size()], Rect2(width - 150, 770, 118, 28), 16, host.LILAC, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
		return
	var equipped: String = GameServices.commerce().equipped_card if public_data.is_empty() else str(StrictData.dictionary(public_data.get("progression")).get("equipped_card", ""))
	if not equipped.is_empty() and not MarketCatalog.find_item(equipped).is_empty():
		frame.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		var card: MemberCardArt = MemberCardArt.new(); card.name = "FavoriteCollectible"; card.host = host; card.item_id = equipped
		host._at(frame, card, Rect2(50, 60, width - 100, 615))
		var item: Dictionary = MarketCatalog.find_item(equipped)
		var _favorite: Label = host._label(frame, "FAVORITE CARD  /  " + str(item.get("member_name", "")).to_upper(), Rect2(48, 703, width - 96, 28), 15, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		if public_data.is_empty():
			var _collection: Button = host._button(frame, "YOUR COLLECTION  →", Rect2(70, 757, width - 140, 53), host._open_collection)
		return
	var image: TextureRect = TextureRect.new()
	var crop: AtlasTexture = AtlasTexture.new()
	crop.atlas = host.ART
	var centers: Array[float] = [0.306, 0.393, 0.488, 0.578, 0.668]
	var dimensions: Vector2 = host.ART.get_size()
	crop.region = Rect2((StrictData.number(centers[host._selected_member]) - 0.117) * dimensions.x, 0.365 * dimensions.y, 0.234 * dimensions.x, 0.635 * dimensions.y)
	image.texture = crop
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = PORTRAIT_SHADE
	image.material = shader_material
	host._at(frame, image, Rect2(2, 2, width - 4, 831))
	var _panel_12: Panel = host._panel(frame, Rect2(27, 28, 272, 42), Color(0.08, 0.08, 0.17, 0.67), Color(host.LILAC, 0.3), 21)
	var _label_13: Label = host._label(frame, "RESCÉNE  /  SCENE %02d" % (host._selected_member + 1), Rect2(43, 39, 245, 23), 13, host.WHITE, host.BOLD)
	var _label_14: Label = host._label(frame, "YOUR STAGE. YOUR SCENE.", Rect2(39, 565, width - 78, 25), 13, host.LILAC, host.BOLD)
	var _label_15: Label = host._label(frame, "In every beat,\na little more you.", Rect2(35, 604, width - 65, 121), 48, host.WHITE, host.ITALIC)
	var thumb_width: float = 62.0
	for index: int in 5:
		var selected: bool = host._selected_member == index
		var button: Button = host._button(frame, "", Rect2(39 + index * (thumb_width + 14), 743, thumb_width, 65), func() -> void:
			host._selected_member = index
			host._save_profile()
			_render())
		button.name = "Scene_" + str(index)
		button.disabled = not public_data.is_empty()
		button.tooltip_text = "Feature scene %02d" % (index + 1)
		button.add_theme_stylebox_override("normal", host._style(Color(0.25, 0.21, 0.38, 0.8), host.LILAC if selected else Color(host.LILAC, 0.22), 12))
		var portrait: TextureRect = TextureRect.new()
		portrait.texture = host._portrait(index)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		host._at(button, portrait, Rect2(5, 5, thumb_width - 10, 55))
	var _label_16: Label = host._label(frame, "%02d / 05" % (host._selected_member + 1), Rect2(width - 156, 765, 118, 30), 19, host.LILAC, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)


func _overview() -> void:
	var state: Dictionary = GameServices.progression().state if public_data.is_empty() else public_data.get("progression", {})
	var frame: Color = GameServices.progression().frame_color() if public_data.is_empty() else Color(str(state.get("frame_color", "c7bbff")))
	var avatar: Panel = host._panel(body, Rect2(355, 192, 122, 122), Color(frame, 0.1), Color(frame, 0.8), 30)
	avatar.name = "ProfileAvatar"
	var avatar_data: Dictionary = StrictData.dictionary(_media().get("avatar", {}))
	if not avatar_data.is_empty(): _photo(avatar, str(avatar_data.get("url", "")), Rect2(4, 4, 114, 114), 27)
	else:
		var _person: TextureRect = host._icon(avatar, "person", Rect2(34, 29, 54, 60), frame)
	if public_data.is_empty():
		var edit: Button = host._button(avatar, "+", Rect2(80, 82, 42, 42), func() -> void: _choose_photo("avatar"), true)
		edit.name = "ChangeAvatar"; edit.tooltip_text = "Upload profile picture"; edit.disabled = GameServices.photos().busy
	var username: Label = _fit_label(body, host._profile_name if public_data.is_empty() else str(public_data.get("username", "Player")), Rect2(507, 192, _content_width - 152, 58), 42, host.WHITE, host.BOLD)
	username.name = "ProfileUsername"
	_chip("LEVEL %02d" % StrictData.integer(state.get("level", 1)), Rect2(509, 269, 145, 39), frame)
	var _label_18: Label = _fit_label(body, GameServices.progression().equipped_title() if public_data.is_empty() else str(state.get("title_name", "First Scene")), Rect2(674, 271, _content_width - 319, 37), 23, host.LILAC, host.ITALIC)
	var uid: String = str(GameServices.session().user.get("id", "")) if public_data.is_empty() else str(public_data.get("id", ""))
	var id_text: String = "UID  " + uid if not uid.is_empty() else "LOCAL PLAYER"
	var _label_19: Label = _fit_label(body, id_text, Rect2(359, 342, _content_width - 80, 26), 15, host.MUTED, host.FONT)
	if not uid.is_empty():
		var copy: Button = host._button(body, "COPY", Rect2(355 + _content_width - 78, 334, 78, 40), func() -> void: _copy(uid, "Player ID"), false, false)
		copy.add_theme_font_size_override("font_size", 12)
	var level: int = StrictData.integer(state.get("level", 1))
	var xp_text: String = "%d / %d XP" % [StrictData.integer(state.get("level_xp", 0)), StrictData.integer(state.get("level_cost", 200))]
	if level >= 100: xp_text = "MAX LEVEL"
	var _label_20: Label = host._label(body, "NEXT LEVEL" if level < 100 else "YOUR JOURNEY", Rect2(357, 402, 350, 24), 12, host.MUTED, host.BOLD)
	var _label_21: Label = host._label(body, xp_text, Rect2(355 + _content_width - 380, 398, 380, 30), 18, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "ProfileXP"
	bar.show_percentage = false
	bar.max_value = maxf(1, StrictData.number(state.get("level_cost", 200)))
	bar.value = StrictData.number(state.get("level_xp", 0)) if level < 100 else bar.max_value
	bar.add_theme_stylebox_override("background", host._style(Color(0.5, 0.46, 0.7, 0.16), Color.TRANSPARENT, 5))
	bar.add_theme_stylebox_override("fill", host._style(host.LILAC, Color.TRANSPARENT, 5))
	host._at(body, bar, Rect2(355, 441, _content_width, 10))
	var accuracy: String = "%.2f%%" % (StrictData.number(state.get("best_accuracy", 0)) / 100.0)
	var values: Array = [[str(StrictData.integer(state.get("clears", 0))), "SONG CLEARS", "music"], [accuracy, "BEST ACCURACY", "star"], [str(StrictData.integer(state.get("max_combo", 0))), "BEST COMBO", "heart"], [str(StrictData.integer(state.get("full_combos", 0))), "FULL COMBOS", "mission"]]
	var card_width: float = (_content_width - 36.0) / 4.0
	for index: int in values.size():
		var item: Array = values[index]
		var card: Panel = host._panel(body, Rect2(355 + index * (card_width + 12), 493, card_width, 156), Color(0.41, 0.37, 0.6, 0.13), Color(host.LILAC, 0.18), 18)
		var _texturerect_22: TextureRect = host._icon(card,str(item[2]), Rect2(20, 19, 24, 24), host.LILAC)
		_fit_label(card,str(item[0]), Rect2(19, 57, card_width - 35, 48), 31, host.WHITE, host.BOLD).name = "Stat_" + str(index)
		var _label_23: Label = host._label(card,str(item[1]), Rect2(20, 120, card_width - 32, 22), 11, host.MUTED, host.BOLD)
	_social_details()
	if not public_data.is_empty():
		var _label_24: Label = host._label(body, "RANKED RECORD COLLECTION", Rect2(358, 724, _content_width, 30), 16, host.LILAC, host.BOLD)
		var _label_25: Label = host._label(body, "%d charts. Their own rhythm." % StrictData.array(public_data.get("records", [])).size(), Rect2(355, 779, _content_width, 60), 36, host.WHITE, host.ITALIC)
		var _button_26: Button = host._button(body, "VIEW RECORDS  →", Rect2(355, 906, 285, 62), func() -> void: set_tab("records"))
		var relationship: Dictionary = StrictData.dictionary(StrictData.dictionary(public_data.get("social", {})).get("relationship", {}))
		var follow: Button = host._button(body, "UNFOLLOW" if StrictData.boolean(relationship.get("following", false)) else "FOLLOW", Rect2(355, 830, 260, 56), func() -> void: _profile_follow.call_deferred(), true)
		follow.disabled = _busy; follow.name = "FollowPlayer"
		var chat: Button = host._button(body, "MESSAGE", Rect2(634, 830, 260, 56), func() -> void: host._open_social(relationship))
		var _report: Button = host._button(body, "REPORT", Rect2(913, 830, 220, 56), func() -> void: _report_target("player", ""))
		chat.disabled = not StrictData.boolean(relationship.get("can_chat", false)); chat.name = "MessagePlayer"
		return
	_wallet_card(689)
	var unlocked: int = 0
	for item: Dictionary in state.get("unlocks", []):
		if item.unlocked: unlocked += 1
	var _label_27: Label = host._label(body, "%d  COSMETICS UNLOCKED" % unlocked, Rect2(357, 917, _content_width - 280, 27), 14, host.MUTED, host.BOLD)
	var view: Button = host._button(body, "VIEW UNLOCKS  →", Rect2(355 + _content_width - 265, 901, 265, 61), func() -> void: set_tab("unlocks"))
	view.add_theme_font_size_override("font_size", 15)
	if GameServices.progression().state.is_empty(): _message = "Your progression will appear here once it has loaded."


func _social_details() -> void:
	var counts: Dictionary = StrictData.dictionary(GameServices.social().summary.get("counts", {})) if public_data.is_empty() else StrictData.dictionary(StrictData.dictionary(public_data.get("social", {})).get("counts", {}))
	for index: int in 3:
		var key: String = ["followers", "following", "friends"][index]
		var button: Button = host._button(body, "%d %s" % [StrictData.integer(counts.get(key, 0)), key.to_upper()], Rect2(355 + index * (_content_width / 3.0), 657, _content_width / 3.0 - 8, 32), func() -> void: host._open_social({}, key), false, false)
		button.add_theme_font_size_override("font_size", 13)
		button.disabled = not public_data.is_empty()

func _profile_follow() -> void:
	if _busy or public_data.is_empty(): return
	_busy = true
	var relationship: Dictionary = StrictData.dictionary(StrictData.dictionary(public_data.get("social", {})).get("relationship", {}))
	var response: Dictionary = await GameServices.social().player_action(str(public_data.get("id", "")), "follow", not StrictData.boolean(relationship.get("following", false)))
	if not is_inside_tree(): return
	if response.ok:
		var profile: Dictionary = await GameServices.scores().player(str(public_data.get("id", "")))
		if not is_inside_tree(): return
		if profile.ok: public_data = StrictData.dictionary(StrictData.dictionary(profile.data).get("profile", {}))
	else: _message = str(response.get("message", "Could not follow this player."))
	_busy = false; _render()

func _media() -> Dictionary:
	return GameServices.photos().media if public_data.is_empty() else StrictData.dictionary(public_data.get("media", {}))


func _photo(parent: Node, path: String, rect: Rect2, radius: float = 18.0, cover: bool = true) -> void:
	var photo: ProfilePhoto = ProfilePhoto.new()
	photo.path = path; photo.radius = radius; photo.cover = cover
	host._at(parent, photo, rect)


func _gallery() -> void:
	var photos: Array = StrictData.array(_media().get("gallery", []))
	var own: bool = public_data.is_empty()
	var service: ProfileMediaService = GameServices.photos()
	_heading("Your moments." if own else "Their moments.", "%d / 5 GALLERY PHOTOS  ·  TAP A PHOTO TO VIEW" % photos.size())
	if own:
		var change: Button = host._button(body, "CHANGE AVATAR", Rect2(355, 332, 240, 56), func() -> void: _choose_photo("avatar"))
		change.name = "GalleryChangeAvatar"; change.disabled = service.busy
		var avatar: Dictionary = StrictData.dictionary(_media().get("avatar", {}))
		var remove_avatar: Button = host._button(body, "REMOVE AVATAR", Rect2(611, 332, 240, 56), func() -> void: _confirm_remove("avatar", str(avatar.get("id", ""))))
		remove_avatar.name = "RemoveAvatar"; remove_avatar.disabled = service.busy or avatar.is_empty()
		var add: Button = host._button(body, "UPLOADING…" if service.uploading else ("GALLERY FULL" if photos.size() >= 5 else "ADD PHOTO  +"), Rect2(355 + _content_width - 279, 332, 279, 56), func() -> void: _choose_photo("gallery"), true)
		add.name = "AddGalleryPhoto"; add.disabled = service.busy or photos.size() >= 5
	var cell_width: float = (_content_width - 32.0) / 3.0
	for index: int in 5:
		var column: int = index % 3
		var row: int = floori(float(index) / 3.0)
		var tile: Panel = host._panel(body, Rect2(355 + column * (cell_width + 16), 418 + row * 276, cell_width, 258), Color(0.14, 0.12, 0.23, 0.85), Color(host.LILAC, 0.25), 18)
		tile.name = "GallerySlot_%d" % index
		if index >= photos.size():
			if index == photos.size() and photos.size() < 5 and own:
				var empty_add: Button = host._button(tile, "+\nADD YOUR MOMENT", Rect2(10, 10, cell_width - 20, 238), func() -> void: _choose_photo("gallery"), false, false)
				empty_add.name = "EmptyGallerySlot"; empty_add.disabled = service.busy
			else:
				var _empty: Label = host._label(tile, "◇\nYOUR NEXT MEMORY" if own else "◇", Rect2(10, 84, cell_width - 20, 82), 19, Color(host.LILAC, 0.45), host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var item: Dictionary = StrictData.dictionary(photos[index])
		var open: Button = host._button(tile, "", Rect2(5, 5, cell_width - 10, 193), func() -> void: _view_photo(index), false, false)
		open.name = "ViewGalleryPhoto_%d" % index
		_photo(open, str(item.get("url", "")), Rect2(0, 0, cell_width - 10, 193), 14)
		if own:
			var replace: Button = host._button(tile, "REPLACE", Rect2(10, 208, (cell_width - 30) * 0.58, 39), func() -> void: _choose_photo("gallery", str(item.get("id", ""))))
			replace.name = "ReplaceGalleryPhoto_%d" % index; replace.disabled = service.busy; replace.add_theme_font_size_override("font_size", 12)
			var remove: Button = host._button(tile, "REMOVE", Rect2(20 + (cell_width - 30) * 0.58, 208, (cell_width - 30) * 0.42, 39), func() -> void: _confirm_remove("gallery", str(item.get("id", ""))))
			remove.name = "RemoveGalleryPhoto_%d" % index; remove.disabled = service.busy; remove.add_theme_font_size_override("font_size", 12)
		else:
			var _caption: Label = host._label(tile, "MOMENT %02d  ↗" % (index + 1), Rect2(15, 215, cell_width - 30, 25), 14, host.LILAC)
	if own:
		var _hint: Label = host._label(body, "JPG / PNG  ·  UP TO 8 MB EACH  ·  AVATAR + FIVE GALLERY PHOTOS", Rect2(357, 987, _content_width, 22), 12, host.MUTED, host.BOLD)
		for child: Node in body.find_children("*", "Button", true, false): _disabled_style(child as Button)


func _choose_photo(kind: String, replace_id: String = "") -> void:
	if not public_data.is_empty() or GameServices.photos().busy or is_instance_valid(_picker): return
	_picker = FileDialog.new()
	_picker.name = "ProfilePhotoPicker"
	_picker.title = "Choose a profile picture" if kind == "avatar" else "Choose a gallery photo"
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.use_native_dialog = true
	_picker.filters = PackedStringArray(["*.jpg,*.jpeg,*.png ; JPG and PNG photos"])
	add_child(_picker)
	var _picked: int = _picker.file_selected.connect(func(path: String) -> void:
		_picker.queue_free(); _picker = null
		GameServices.photos().upload.call_deferred(kind, path, replace_id))
	var _cancelled: int = _picker.canceled.connect(func() -> void: _picker.queue_free(); _picker = null)
	_picker.popup_centered_ratio(0.75)


func close_photo_overlay() -> bool:
	if not is_instance_valid(_photo_viewer): return false
	_photo_viewer.hide(); _photo_viewer.queue_free(); _photo_viewer = null
	return true


func _overlay() -> Control:
	var _closed: bool = close_photo_overlay()
	_photo_viewer = Control.new(); _photo_viewer.name = "ProfilePhotoOverlay"
	add_child(_photo_viewer); _photo_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	_photo_viewer.size = Vector2(host._width, 1080)
	var veil: ColorRect = ColorRect.new(); veil.color = Color(0.015, 0.012, 0.035, 0.96)
	host._at(_photo_viewer, veil, Rect2(0, 0, host._width, 1080))
	return _photo_viewer


func _view_photo(index: int) -> void:
	var photos: Array = StrictData.array(_media().get("gallery", []))
	if index < 0 or index >= photos.size(): return
	var overlay: Control = _overlay()
	_photo(overlay, str(StrictData.dictionary(photos[index]).get("url", "")), Rect2(110, 110, host._width - 220, 805), 14, false)
	var _title: Label = host._label(overlay, "MOMENT %02d / %02d" % [index + 1, photos.size()], Rect2(110, 42, 600, 42), 24, host.WHITE, host.BOLD)
	var _close: Button = host._button(overlay, "CLOSE  ×", Rect2(host._width - 290, 37, 180, 56), func() -> void: var _closed: bool = close_photo_overlay())
	var previous: Button = host._button(overlay, "← PREVIOUS", Rect2(110, 948, 250, 62), func() -> void: _view_photo(index - 1))
	previous.disabled = index == 0
	var next: Button = host._button(overlay, "NEXT →", Rect2(host._width - 360, 948, 250, 62), func() -> void: _view_photo(index + 1))
	next.disabled = index >= photos.size() - 1
	if not public_data.is_empty():
		var photo_id: String = str(StrictData.dictionary(photos[index]).get("id", ""))
		var _report: Button = host._button(overlay, "REPORT PHOTO", Rect2(host._width * 0.5 - 150, 948, 300, 62), func() -> void: _report_target("photo", photo_id))


func _confirm_remove(kind: String, id: String) -> void:
	if not public_data.is_empty() or GameServices.photos().busy: return
	var overlay: Control = _overlay()
	var width: float = 900.0
	var panel: Panel = host._panel(overlay, Rect2((host._width - width) * 0.5, 330, width, 400), Color("211d35"), Color(host.LILAC, 0.6), 24)
	var _heading_text: Label = host._label(panel, "REMOVE PHOTO?", Rect2(44, 40, 810, 50), 32, host.WHITE, host.BOLD)
	var _explanation: Label = host._label(panel, "Your avatar will return to its default." if kind == "avatar" else "This photo will be removed from your player gallery.", Rect2(44, 125, 810, 60), 22, host.LILAC)
	var _cancel: Button = host._button(panel, "KEEP PHOTO", Rect2(44, 265, 360, 67), func() -> void: var _closed: bool = close_photo_overlay())
	var confirm: Button = host._button(panel, "REMOVE PHOTO", Rect2(428, 265, 428, 67), func() -> void:
		var _closed: bool = close_photo_overlay()
		GameServices.photos().remove.call_deferred(kind, id), true)
	confirm.name = "ConfirmRemoveProfilePhoto"


func _wallet_card(y: float) -> void:
	var card: Panel = host._panel(body, Rect2(355, y, _content_width, 181), Color(0.08, 0.08, 0.16, 0.74), Color(host.LILAC, 0.22), 20)
	var _texturerect_28: TextureRect = host._icon(card, "gem", Rect2(25, 24, 25, 25), host.LILAC)
	var _label_29: Label = host._label(card, "ACCOUNT WALLET", Rect2(65, 26, 390, 25), 13, host.LILAC, host.BOLD)
	var address: String = str(StrictData.dictionary(GameServices.session().user.get("wallet", {})).get("address", ""))
	_wallet_address = LineEdit.new()
	_wallet_address.name = "WalletAddress"
	_wallet_address.editable = false
	_wallet_address.text = address
	_wallet_address.placeholder_text = "No wallet address available"
	_wallet_address.add_theme_font_override("font", host.FONT)
	_wallet_address.add_theme_font_size_override("font_size", 19)
	_wallet_address.add_theme_color_override("font_uneditable_color", host.WHITE)
	_wallet_address.add_theme_color_override("font_placeholder_color", host.MUTED)
	_wallet_address.add_theme_stylebox_override("read_only", host._style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	_wallet_address.add_theme_stylebox_override("focus", host._style(Color.TRANSPARENT, Color(host.LILAC, 0.35), 6))
	host._at(card, _wallet_address, Rect2(10, 68, _content_width - 210, 42))
	_wallet_copy = host._button(card, "COPY ADDRESS", Rect2(_content_width - 193, 69, 170, 48), func() -> void: _copy(address, "Wallet address"))
	_wallet_copy.name = "CopyWalletAddress"
	_wallet_copy.add_theme_font_size_override("font_size", 12)
	_wallet_copy.disabled = address.is_empty()
	_disabled_style(_wallet_copy)
	var _label_30: Label = host._label(card, "Linked to your RESCÉNE account", Rect2(27, 135, _content_width - 54, 24), 14, host.MUTED)


func _wallet() -> void:
	_heading("Your wallet", "ONE ACCOUNT. YOUR OWN ADDRESS.")
	_wallet_card(354)
	var _label_31: Label = host._label(body, "ACCOUNT DETAILS", Rect2(358, 592, _content_width, 28), 14, host.LILAC, host.BOLD)
	_detail("USERNAME", host._profile_name, 647)
	_detail("PLAYER ID", str(GameServices.session().user.get("id", "Local player")), 727)
	var joined: String = str(GameServices.session().user.get("created_at", "")).left(10)
	_detail("JOINED", joined if not joined.is_empty() else "—", 807)
	host._label(body, "Your wallet stays linked when you log in on another device.", Rect2(358, 925, _content_width - 10, 63), 18, host.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _records() -> void:
	_heading("Your records" if public_data.is_empty() else "Ranked records", "PERSONAL BESTS  /  CLOUD & DEVICE" if public_data.is_empty() else "PERSONAL BESTS  /  VALIDATED ONLINE RUNS")
	var records: Array[Dictionary] = RhythmRecords.all_scores()
	if not public_data.is_empty():
		records.clear()
		for record: Dictionary in public_data.get("records", []): records.append(record)
	if records.is_empty():
		var _texturerect_32: TextureRect = host._icon(body, "music", Rect2(363, 385, 62, 62), host.LILAC)
		var _label_33: Label = host._label(body, "Your first score belongs here.", Rect2(358, 484, _content_width, 72), 36, host.WHITE, host.ITALIC)
		host._label(body, "Complete a song to start your collection of personal bests.", Rect2(360, 577, _content_width - 30, 72), 20, host.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if public_data.is_empty():
			var play: Button = host._button(body, "EXPLORE SONGS  →", Rect2(355, 700, 340, 70), _open_songs, true)
			play.name = "ExploreSongs"
		return
	var list: VBoxContainer = _make_scroll(335, 641)
	for record: Dictionary in records:
		var row: Control = Control.new()
		row.custom_minimum_size = Vector2(0, 124)
		list.add_child(row)
		var width: float = _content_width - 17
		var _panel_34: Panel = host._panel(row, Rect2(0, 0, width, 124), Color(0.2, 0.18, 0.32, 0.65), Color(host.LILAC, 0.18), 16)
		var cover: TextureRect = TextureRect.new()
		cover.texture = _record_cover(str(record.get("title", "")))
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		host._at(row, cover, Rect2(14, 14, 96, 96))
		var _label_35: Label = _fit_label(row, str(record.get("title", "Unknown song")), Rect2(132, 21, width - 360, 36), 23, host.WHITE, host.BOLD)
		var _label_36: Label = host._label(row, "%s · %.2f%% · %s" % [str(record.get("difficulty", "Normal")).to_upper(), StrictData.number(record.get("accuracy", 0)), str(record.get("source", "cloud")).to_upper()], Rect2(133, 74, width - 350, 27), 14, host.MUTED)
		var _label_37: Label = host._label(row, "%07d" % StrictData.integer(record.get("score", 0)), Rect2(width - 231, 22, 208, 36), 28, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		var _label_38: Label = host._label(row, str(record.get("rank", "")), Rect2(width - 130, 74, 105, 27), 18, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		if public_data.is_empty() and record.has("song_id"):
			var board: Button = host._button(row, "", Rect2(0, 0, width, 124), func() -> void: _open_record_board(record), false, false)
			board.name = "RecordRankings"
			board.tooltip_text = "View this chart's leaderboard"
			board.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			board.add_theme_stylebox_override("hover", host._style(Color(host.LILAC, 0.08), Color(host.LILAC, 0.4), 16))
	if public_data.is_empty() and not GameServices.scores().error_message.is_empty(): _message = GameServices.scores().error_message + " Showing saved records."


func _unlocks() -> void:
	_heading("Your signature", "EARN TITLES AND FRAMES. MAKE THEM YOURS.")
	var items: Array = GameServices.progression().state.get("unlocks", [])
	if items.is_empty():
		host._label(body, "Your unlocks will appear when your progression loads.", Rect2(358, 402, _content_width - 30, 90), 22, host.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var list: VBoxContainer = _make_scroll(335, 641)
	for item: Dictionary in items:
		var row: Control = Control.new()
		row.custom_minimum_size = Vector2(0, 130)
		list.add_child(row)
		var width: float = _content_width - 17
		var tint: Color = Color(str(item.color)) if item.kind == "frame" else host.LILAC
		var _panel_39: Panel = host._panel(row, Rect2(0, 0, width, 130), Color(0.2, 0.18, 0.32, 0.65), Color(tint, 0.2), 16)
		var _texturerect_40: TextureRect = host._icon(row, "person" if item.kind == "frame" else "star", Rect2(23, 37, 45, 45), tint)
		var _label_41: Label = _fit_label(row,str(item.name), Rect2(93, 18, width - 290, 37), 24, host.WHITE, host.BOLD)
		var _label_42: Label = _fit_label(row, str(item.kind).to_upper() + "  /  " + str(item.requirement), Rect2(95, 76, width - 300, 27), 14, host.MUTED, host.FONT)
		var caption: String = "EQUIPPED" if item.equipped else ("EQUIP" if item.unlocked else "LOCKED")
		var button: Button = host._button(row, caption, Rect2(width - 184, 37, 164, 55), func() -> void: await _equip(str(item.id)),StrictData.boolean(item.unlocked and not item.equipped))
		button.name = "Equip_" + str(item.id)
		button.disabled = _busy or not item.unlocked or item.equipped
		button.add_theme_font_size_override("font_size", 14)
		_disabled_style(button)


func _equip(cosmetic_id: String) -> void:
	if _busy or not public_data.is_empty(): return
	_busy = true
	_message = ""
	_render()
	var response: Dictionary = await GameServices.progression().equip(cosmetic_id)
	if not is_inside_tree(): return
	_busy = false
	_message = "Signature updated." if response.ok else str(response.message)
	_render()


func _make_scroll(y: float, height: float) -> VBoxContainer:
	_scroll = ScrollContainer.new()
	_scroll.name = "ProfileList"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	host._at(body, _scroll, Rect2(355, y, _content_width, height))
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	_scroll.add_child(list)
	return list


func _heading(title: String, subtitle: String) -> void:
	var _label_43: Label = host._label(body, title, Rect2(351, 184, _content_width, 83), 57, host.WHITE, host.SERIF)
	var _label_44: Label = host._label(body, subtitle, Rect2(357, 282, _content_width, 25), 12, host.LILAC, host.BOLD)


func _detail(caption: String, value: String, y: float) -> void:
	var _label_45: Label = host._label(body, caption, Rect2(358, y, 210, 30), 13, host.MUTED, host.BOLD)
	var _label_46: Label = _fit_label(body, value, Rect2(574, y - 3, _content_width - 220, 36), 20, host.WHITE, host.FONT)
	host._line(body, Rect2(355, y + 49, _content_width, 1), Color(host.LILAC, 0.13))


func _chip(text: String, rect: Rect2, color: Color) -> void:
	var chip: Panel = host._panel(body, rect, Color(color, 0.12), Color(color, 0.27), 10)
	var _label_47: Label = host._label(chip, text, Rect2(0, 8, rect.size.x, 25), 14, color, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)


func _fit_label(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, font: Font) -> Label:
	var label: Label = host._label(parent, text, rect, font_size, color, font)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.size = rect.size
	return label


func _disabled_style(button: Button) -> void:
	button.add_theme_stylebox_override("disabled", host._style(Color(0.1, 0.1, 0.18), Color(host.LILAC, 0.18), 14))
	button.add_theme_color_override("font_disabled_color", host.MUTED)


func _copy(value: String, caption: String) -> void:
	if value.is_empty(): return
	DisplayServer.clipboard_set(value)
	_message = caption + " copied."
	if is_instance_valid(_message_label): _message_label.text = _message


func _open_songs() -> void:
	host._profile_mode = false
	host._open_songs()

func _open_record_board(record: Dictionary) -> void:
	for song: Dictionary in SongCatalog.SONGS:
		if song.id == str(record.get("song_id", "")):
			host._open_leaderboard(song, str(record.get("difficulty", "Normal")))
			return

func go_back() -> void:
	if close_photo_overlay(): return
	if public_data.is_empty(): host._close_profile()
	else: return_requested.emit()


func _record_cover(title: String) -> Texture2D:
	for song: Dictionary in SongCatalog.SONGS:
		if song.title == title: return load(str(song.cover_path))
	return host.ART

func _report_target(kind: String, target: String) -> void:
	var view: ReportView = ReportView.new(); view.host = host; view.player_id = str(public_data.get("id", "")); view.target_type = kind; view.target_id = target; add_child(view)
