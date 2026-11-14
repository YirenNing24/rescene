class_name LeaderboardView
extends MenuDestination
## Full ranking destination over the lobby. Requests are generation-scoped so
## quickly changing difficulty can never display another chart's results.

const BACKDROP: Shader = preload("res://shaders/results_backdrop.gdshader")

var song: Dictionary
var difficulty: String = "Normal"
var view: String = "top"
var board: Dictionary = {}
var loading: bool = false
var error_message: String = ""
var _generation: int = 0
var _public_view: PlayerProfile
var _opening_player: bool = false

func _ready() -> void:
	name = "LeaderboardView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	await refresh()

func _exit_tree() -> void:
	_generation += 1

func refresh() -> void:
	_generation += 1
	var generation: int = _generation
	loading = true
	error_message = ""
	board = {}
	_render()
	var response: Dictionary = await GameServices.scores().leaderboard(str(song.id), difficulty)
	if not is_inside_tree() or generation != _generation: return
	loading = false
	if response.ok: board = StrictData.dictionary(response.data).get("leaderboard", {})
	else: error_message = response.get("message", "Rankings could not be loaded.")
	_render()

func _render() -> void:
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var image: TextureRect = TextureRect.new()
	image.texture = host.ART
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = BACKDROP
	image.material = shader_material
	host._at(body, image, Rect2(0, 0, host._width, 1080))
	var back: Button = host._button(body, "‹", Rect2(54, 45, 70, 68), go_back, false, false)
	back.name = "Back"
	back.add_theme_font_size_override("font_size", 38)
	var _label_1: Label = host._label(body, "GLOBAL LEADERBOARD", Rect2(154, 48, 1100, 50), 33, host.WHITE, host.BOLD)
	var _label_2: Label = host._label(body, "EVERY BEAT EARNS ITS PLACE", Rect2(157, 105, 1000, 23), 12, host.LILAC)
	host._line(body, Rect2(58, 149, host._width - 116, 1), Color(host.LILAC, 0.2))
	var cover: TextureRect = TextureRect.new()
	cover.texture = load(str(song.cover_path))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var _panel_3: Panel = host._panel(body, Rect2(59, 199, 572, 572), Color.TRANSPARENT, Color(host.LILAC, 0.45), 20)
	host._at(body, cover, Rect2(72, 212, 546, 546))
	_fit(str(song.title), Rect2(62, 798, 570, 57), 37, host.WHITE, host.BOLD)
	var _label_4: Label = host._label(body, "RESCÉNE   /   " + difficulty.to_upper(), Rect2(65, 870, 570, 28), 16, host.LILAC)
	var me: Dictionary = board.get("me", {}) if board.get("me") is Dictionary else {}
	var my_rank: String = "YOUR RANK  /  #%d" % StrictData.integer(me.get("position", 0)) if not me.is_empty() else "YOUR NEXT CLEAR COULD BE HERE"
	var _label_5: Label = host._label(body, my_rank, Rect2(65, 939, 560, 34), 19, host.WHITE, host.BOLD)
	var detail: String = "%07d  ·  %.2f%%  ·  %d COMBO" % [StrictData.integer(me.get("score",0)),StrictData.number(me.get("accuracy",0)),StrictData.integer(me.get("max_combo",0))] if not me.is_empty() else "Complete an online Free Play run to rank."
	var _label_6: Label = host._label(body, detail, Rect2(65, 990, 590, 28), 15, host.MUTED)
	var publication: Dictionary = board.get("on_chain", {}) if board.get("on_chain") is Dictionary else {}
	if not publication.is_empty():
		var state: String = str(publication.get("status", "not_published"))
		var chain_text: String = "ON-CHAIN  /  " + ("CONFIRMED" if state == "confirmed" else "RETRYING" if StrictData.boolean(publication.get("retrying", false)) else "WAITING FOR A VERIFIED BEST" if state == "not_published" else "SYNCING")
		var _chain_label: Label = host._label(body, chain_text, Rect2(65, 1032, 590, 22), 12, host.LILAC)
	var x: float = 706.0
	var width: float = host._width - x - 58
	var names: Array[String] = ["Easy", "Normal", "Hard", "Ultra Hard"]
	var tab_width: float = (width - 36) / 4.0
	for index: int in names.size():
		var item: String = names[index]
		var button: Button = host._button(body, item.to_upper(), Rect2(x + index * (tab_width + 12), 199, tab_width, 64), func() -> void:
			difficulty = item
			refresh.call_deferred(), difficulty == item, true, host.LILAC)
		button.name = "Difficulty_"+str(index)
		button.add_theme_font_size_override("font_size", 17)
	var _button_7: Button = host._button(body, "TOP 25", Rect2(x, 289, 204, 54), func() -> void: view="top"; _render(), view=="top", true, host.LILAC)
	var nearby: Button = host._button(body, "NEAR ME", Rect2(x+219, 289, 204, 54), func() -> void: view="nearby"; _render(), view=="nearby", true, host.LILAC)
	nearby.name = "NearMe"
	nearby.disabled = me.is_empty()
	var total: int = StrictData.integer(board.get("total",0))
	var _label_8: Label = host._label(body, "%d RANKED %s" % [total,"PLAYER" if total==1 else "PLAYERS"], Rect2(x+454, 304, width-670, 26), 13, host.MUTED, host.BOLD)
	var retry: Button = host._button(body, "REFRESH", Rect2(host._width-232, 289, 174, 54), refresh)
	retry.disabled = loading
	retry.add_theme_font_size_override("font_size", 14)
	if loading or not error_message.is_empty():
		host._label(body, "Loading rankings…" if loading else error_message, Rect2(x+20, 475, width-40, 130), 27, host.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var rows: Array = board.get("nearby", []) if view=="nearby" else board.get("top", [])
	if rows.is_empty():
		var _label_9: Label = host._label(body, "Be the opening act.", Rect2(x+22, 452, width-40, 90), 54, host.WHITE, host.ITALIC)
		var _label_10: Label = host._label(body, "This chart is waiting for its first ranked clear.", Rect2(x+25, 569, width-50, 63), 23, host.MUTED)
		return
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "RankingList"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host._at(body, scroll, Rect2(x, 372, width, 616))
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for row: Dictionary in rows: _row(list, row, width-18)
	var _label_11: Label = host._label(body, "SCORE  →  COMBO  →  EARLIEST CLEAR   ·   TAP A PLAYER TO VIEW THEIR PROFILE", Rect2(x+4, 1019, width, 25), 12, host.MUTED)

func _row(list: VBoxContainer, row: Dictionary, width: float) -> void:
	var mine: bool = str(row.get("user_id", "")) == str(GameServices.session().user.get("id", ""))
	var button: Button = host._button(list, "", Rect2(0, 0, width, 115), func() -> void: await open_player(str(row.user_id)))
	button.name = "Rank_"+str(StrictData.integer(row.position))
	button.custom_minimum_size = Vector2(0,115)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", host._style(Color(0.43,0.36,0.64,0.4) if mine else Color(0.1,0.1,0.2,0.84), host.LILAC if mine else Color(host.LILAC,0.23),18))
	var _label_12: Label = host._label(button, "%02d" % StrictData.integer(row.position), Rect2(23, 31, 100, 52), 32, host.LILAC, host.BOLD)
	var avatar_panel: Panel = host._panel(button, Rect2(124, 17, 80, 80), Color(host.LILAC, 0.12), Color(host.LILAC, 0.4), 18)
	avatar_panel.name = "RankingAvatar"
	var fallback: TextureRect = host._icon(avatar_panel, "person", Rect2(20, 20, 40, 40), host.LILAC)
	fallback.name = "AvatarFallback"
	var avatar: Dictionary = StrictData.dictionary(row.get("avatar", {}))
	if not str(avatar.get("url", "")).is_empty():
		var photo: ProfilePhoto = ProfilePhoto.new()
		photo.name = "RankingAvatarPhoto"
		photo.path = str(avatar.url)
		photo.radius = 15.0
		host._at(avatar_panel, photo, Rect2(3, 3, 74, 74))
	var label: Label = host._label(button, str(row.username)+("  /  YOU" if mine else ""), Rect2(224,20,width-592,36),25,host.WHITE,host.BOLD)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text=true
	label.size=Vector2(width-592,36)
	var _label_13: Label = host._label(button, "%.2f%% ACCURACY   ·   %d COMBO" % [StrictData.number(row.accuracy),StrictData.integer(row.max_combo)], Rect2(226,72,width-592,27),14,host.MUTED)
	var _label_14: Label = host._label(button, "%07d" % StrictData.integer(row.score), Rect2(width-330,22,245,46),32,host.WHITE,host.BOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	var _label_15: Label = host._label(button, str(row.rank), Rect2(width-170,76,82,25),16,host.LILAC,host.BOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	var _texturerect_16: TextureRect = host._icon(button,"arrow",Rect2(width-56,44,24,24),host.LILAC)

func open_player(user_id: String) -> void:
	if _opening_player: return
	_opening_player=true
	var response: Dictionary = await GameServices.scores().player(user_id)
	if not is_inside_tree(): return
	_opening_player=false
	if not response.ok:
		error_message=response.get("message","Player profile could not be loaded.")
		_render()
		return
	_public_view = PlayerProfile.new()
	_public_view.host=host
	_public_view.public_data=response.data.profile
	_public_view.size=size
	var _int_17: int = _public_view.return_requested.connect(go_back)
	add_child(_public_view)
	body.hide()

func go_back() -> void:
	if is_instance_valid(_public_view):
		_public_view.hide()
		_public_view.queue_free()
		_public_view=null
		body.show()
	else: host._close_dialog()

func _fit(text: String, rect: Rect2, font_size: int, color: Color, font: Font) -> void:
	var label: Label=host._label(body,text,rect,font_size,color,font)
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text=true
	label.size=rect.size
