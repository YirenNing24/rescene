class_name SongSelection
extends Control
## Song-selection view inside the lobby, retaining its background and HUD.

signal back_requested
signal preview_requested(song: Dictionary)
signal preview_stopped
signal start_requested(song: Dictionary, difficulty: String)

const WHITE: Color = Color("f4f1ff")
const MUTED: Color = Color("b7b9d5")
const LILAC: Color = Color("c7bbff")
const INK: Color = Color("202039")

var host: ResceneMainMenu
var selected: Dictionary
var difficulty: String = "Normal"
var query: String = ""
var sort_index: int = 0
var _filtered: Array[Dictionary] = []
var _rows: Dictionary[String, Button] = {}
var _detail: Control
var _scroll: KineticSongScroll
var _list: VBoxContainer
var _count: Label
var _empty: Label
var _preview_button: Button
var _difficulty_buttons: Array[Button] = []
var _previewing: bool = false
var _width: float
var _start_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _int_1: int = GameServices.scores().changed.connect(refresh_records)
	_width = host._width
	selected = SongCatalog.SONGS[0]
	for song: Dictionary in SongCatalog.SONGS:
		if song.title == "LOVE ATTACK":
			selected = song
			break
	_build_toolbar()
	_build_list()
	_render_detail()
	_filter_songs()


func _build_toolbar() -> void:
	var back: Button = host._button(self, "", Rect2(58, 173, 70, 70), func() -> void: back_requested.emit())
	var arrow: TextureRect = host._icon(back, "arrow", Rect2(21, 21, 28, 28))
	arrow.pivot_offset = Vector2(14, 14)
	arrow.rotation = PI
	var _label_2: Label = host._label(self, "SONG SELECTION", Rect2(153, 177, 760, 54), 35, WHITE, host.BOLD)
	var _label_3: Label = host._label(self, "FIND YOUR NEXT FAVORITE SCENE", Rect2(156, 235, 760, 22), 12, LILAC, host.FONT)
	var search: LineEdit = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search song"
	search.clear_button_enabled = true
	search.add_theme_font_override("font", host.FONT)
	search.add_theme_font_size_override("font_size", 21)
	search.add_theme_color_override("font_color", WHITE)
	search.add_theme_color_override("font_placeholder_color", MUTED)
	search.add_theme_stylebox_override("normal", host._style(Color(0.07, 0.08, 0.18, 0.87), Color(0.7, 0.66, 1, 0.4), 20))
	search.add_theme_stylebox_override("focus", host._style(Color(0.1, 0.1, 0.22, 0.94), LILAC, 20))
	host._at(self, search, Rect2(_right_x(), 183, _right_width() - 330, 66))
	var _int_4: int = search.text_changed.connect(func(value: String) -> void:
		query = value
		_filter_songs()
	)
	var sort: OptionButton = OptionButton.new()
	sort.name = "Sort"
	for text: String in ["Title  A – Z", "Title  Z – A", "Album", "Duration"]:
		sort.add_item(text)
	sort.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sort.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	host._at(self, sort, Rect2(_width - 368, 183, 310, 66))
	var _int_5: int = sort.item_selected.connect(func(index: int) -> void:
		sort_index = index
		_filter_songs()
	)
	var names: Array[String] = ["Easy", "Normal", "Hard", "Ultra Hard"]
	var tab_width: float = (_right_width() - 14.0 * (names.size() - 1)) / names.size()
	for index: int in names.size():
		var text: String = names[index]
		var button: Button = host._button(self, text.to_upper(), Rect2(_right_x() + index * (tab_width + 14), 273, tab_width, 66), func() -> void: _select_difficulty(text))
		_difficulty_buttons.append(button)
	_update_difficulty_styles()
	var _panel_6: Panel = host._panel(self, Rect2(_right_x(), 352, _right_width(), 35), Color(0.06, 0.07, 0.15, 0.72), Color.TRANSPARENT, 10)
	_count = host._label(self, "", Rect2(_right_x() + 12, 355, 760, 27), 16, WHITE, host.FONT)
	var _label_7: Label = host._label(self, "LOCAL LIBRARY", Rect2(_width - 328, 355, 252, 27), 13, LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)


func _build_list() -> void:
	_scroll = KineticSongScroll.new()
	_scroll.interaction_allowed = func() -> bool: return not is_instance_valid(host._dialog)
	_scroll.name = "SongList"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = false
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.get_v_scroll_bar().custom_minimum_size.x = 9
	_scroll.get_v_scroll_bar().step = 0.0
	host._at(self, _scroll, Rect2(_right_x(), 402, _right_width(), 490))
	# Containers must receive pointer/touch gestures to support dragging the list.
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var _int_8: int = _scroll.movement_started.connect(_stop_for_scroll)
	var _int_9: int = _scroll.focused_index_changed.connect(_focus_moved)
	var _int_10: int = _scroll.settled.connect(_focus_settled)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	_scroll.add_child(_list)
	_empty = host._label(self, "No songs found.\nTry a different search.", Rect2(_right_x() + 60, 494, _right_width() - 120, 140), 27, MUTED, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
	_empty.visible = false
	host._line(self, Rect2(_right_x(), 922, _right_width(), 1), Color(0.8, 0.77, 1, 0.23))
	var _label_11: Label = host._label(self, "SELECT A SONG. MAKE IT YOUR SCENE.", Rect2(_right_x(), 947, _right_width() - 430, 28), 14, WHITE, host.FONT)
	var _label_12: Label = host._label(self, "First half of each song  ·  1 energy per attempt", Rect2(_right_x(), 988, _right_width() - 430, 27), 16, MUTED, host.FONT)
	var start: Button = host._button(self, "START", Rect2(_width - 438, 947, 380, 82), func() -> void: start_requested.emit(selected, difficulty), true)
	start.name = "Start"
	_start_button = start
	start.add_theme_font_size_override("font_size", 34)
	var _texturerect_13: TextureRect = host._icon(start, "play", Rect2(307, 25, 32, 32), INK)


func _filter_songs() -> void:
	_scroll.reset_motion()
	preview_stopped.emit()
	_filtered.clear()
	for song: Dictionary in SongCatalog.SONGS:
		var haystack: String = song.title + " " + song.artist + " " + song.album
		if query.strip_edges().is_empty() or haystack.to_lower().contains(query.strip_edges().to_lower()):
			_filtered.append(song)
	_filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match sort_index:
			1: return String(str(a.title)).to_lower() > String(str(b.title)).to_lower()
			2:
				if a.album != b.album:
					return String(str(a.album)).to_lower() < String(str(b.album)).to_lower()
			3:
				if a.seconds != b.seconds:
					return a.seconds < b.seconds
		return String(str(a.title)).to_lower() < String(str(b.title)).to_lower()
	)
	for child: Node in _list.get_children():
		child.free()
	_rows.clear()
	for song: Dictionary in _filtered:
		_add_row(song)
	_scroll.row_count = _filtered.size()
	_count.text = "%02d / %02d SONGS   ·   %s" % [_filtered.size(), SongCatalog.SONGS.size(), difficulty.to_upper()]
	_empty.visible = _filtered.is_empty()
	_start_button.disabled = _filtered.is_empty()
	_preview_button.disabled = _filtered.is_empty()
	_update_row_styles()
	call_deferred("_focus_selection")


func _focus_selection() -> void:
	if _filtered.is_empty():
		return
	var index: int = 0
	for song_index: int in _filtered.size():
		if _filtered[song_index].id == selected.id:
			index = song_index
			break
	_scroll.focus_index(index, true)


func _stop_for_scroll() -> void:
	preview_stopped.emit()


func _focus_moved(index: int) -> void:
	if index >= 0 and index < _filtered.size() and selected.id != _filtered[index].id:
		select_song(_filtered[index])


func _focus_settled(index: int) -> void:
	if index >= 0 and index < _filtered.size():
		if selected.id != _filtered[index].id or not _previewing:
			select_song(_filtered[index], true)


func _add_row(song: Dictionary) -> void:
	var button: Button = host._button(_list, "", Rect2(0, 0, _right_width() - 18, 113), func() -> void:
		_scroll.focus_index(_filtered.find(song))
	)
	button.name = "Song_" + song.id
	button.custom_minimum_size = Vector2(0, 113)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = song.title + " · " + song.album
	var _int_14: int = button.focus_entered.connect(func() -> void:
		_scroll.focus_index(_filtered.find(song))
	)
	var cover: TextureRect = TextureRect.new()
	cover.texture = load(str(song.cover_path))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	host._at(button, cover, Rect2(14, 14, 85, 85))
	var title: Label = host._label(button,str(song.title), Rect2(122, 16, _right_width() - 285, 38), 25, WHITE, host.BOLD)
	title.name = "Title"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var artist: Label = host._label(button,str(song.artist + "   /   " + song.album), Rect2(123, 60, _right_width() - 300, 27), 15, MUTED, host.FONT)
	artist.name = "Artist"
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var duration: Label = host._label(button, format_time(ceili(StrictData.number(song.seconds * 0.5))), Rect2(_right_width() - 148, 22, 102, 32), 23, WHITE, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	duration.name = "Duration"
	var status: Label = host._label(button, "NOT PLAYED", Rect2(_right_width() - 186, 64, 140, 22), 10, MUTED, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	status.name = "Status"
	var record: Dictionary = RhythmRecords.best(str(song.id), difficulty)
	if not record.is_empty():
		status.text = "%s  ·  %07d" % [record.rank, record.score]
	_rows[song.id] = button


func select_song(song: Dictionary, audition: bool = false) -> void:
	selected = song
	_previewing = false
	_render_detail()
	_update_row_styles()
	if audition:
		_previewing = true
		_preview_button.text = "STOP PREVIEW"
		preview_requested.emit(song)


func _update_row_styles() -> void:
	for id: String in _rows:
		var button: Button = _rows[id]
		var active: bool = id == selected.id
		button.add_theme_stylebox_override("normal", host._style(Color("d8ceff") if active else Color(0.065, 0.075, 0.16, 0.89), WHITE if active else Color(0.7, 0.66, 1, 0.28), 16))
		button.add_theme_stylebox_override("hover", host._style(Color("e7dfff") if active else Color(0.16, 0.14, 0.29, 0.97), LILAC, 16))
		button.add_theme_stylebox_override("pressed", host._style(Color("cabcf4") if active else Color(0.19, 0.16, 0.33, 0.97), WHITE, 16))
		for label_name: String in ["Title", "Duration"]:
			(button.get_node(label_name) as Label).add_theme_color_override("font_color", INK if active else WHITE)
		for label_name: String in ["Artist", "Status"]:
			(button.get_node(label_name) as Label).add_theme_color_override("font_color", Color("5a5273") if active else MUTED)
		for label_name: String in ["Title", "Artist", "Duration", "Status"]:
			(button.get_node(label_name) as Label).add_theme_color_override("font_shadow_color", Color.TRANSPARENT if active else Color(0.025, 0.025, 0.07, 0.35))


func _render_detail() -> void:
	if is_instance_valid(_detail):
		_detail.free()
	_detail = Control.new()
	_detail.name = "SelectedSong"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)
	var cover_size: float = 560.0
	var cover_x: float = 193.0
	# A double pearl frame, echoing the reference's large left-side jacket.
	var _panel_15: Panel = host._panel(_detail, Rect2(cover_x - 17, 287, cover_size + 34, cover_size + 34), Color(0.10, 0.11, 0.23, 0.65), Color(0.8, 0.77, 1, 0.4), 26)
	var cover: TextureRect = TextureRect.new()
	cover.texture = load(str(selected.cover_path))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	host._at(_detail, cover, Rect2(cover_x, 304, cover_size, cover_size))
	var _panel_16: Panel = host._panel(_detail, Rect2(111, 742, 804, 142), Color(0.075, 0.075, 0.17, 0.96), Color(0.83, 0.79, 1, 0.65), 22)
	var title: Label = host._label(_detail,str(selected.title), Rect2(140, 758, 742, 60), 39, WHITE, host.BOLD)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var subtitle: Label = host._label(_detail,str(selected.artist + "   /   " + selected.album), Rect2(142, 826, 740, 30), 18, LILAC, host.FONT)
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_button = host._button(_detail, "PREVIEW", Rect2(111, 902, 225, 66), _toggle_preview)
	_preview_button.name = "Preview"
	var ranking: Button = host._button(_detail, "RANKINGS", Rect2(350, 902, 220, 66), func() -> void: host._open_leaderboard(selected, difficulty))
	ranking.name = "Rankings"
	var mastery: Button = host._button(_detail, "MASTERY", Rect2(584,902,220,66),func() -> void: host._open_mastery(selected))
	mastery.name = "Mastery"
	var _label_17: Label = host._label(_detail, format_time(ceili(StrictData.number(selected.seconds * 0.5))), Rect2(810, 916, 105, 30), 16, WHITE, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	host._line(_detail, Rect2(111, 991, 804, 1), Color(0.8, 0.77, 1, 0.2))
	var _label_18: Label = host._label(_detail, "PERSONAL BEST", Rect2(114, 1010, 320, 24), 12, LILAC, host.BOLD)
	var record: Dictionary = RhythmRecords.best(str(selected.id), difficulty)
	var best_text: String = "—  Your first score belongs here." if record.is_empty() else "%s / %07d / %.2f%% · %s" % [record.rank, record.score, record.accuracy, str(record.get("source", "device")).to_upper()]
	var _label_19: Label = host._label(_detail, best_text, Rect2(410, 1006, 505, 30), 17, MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	var _next_mastery: Label = host._label(_detail,"NEXT MASTERY  ·  "+GameServices.progression().next_mastery(str(selected.id),difficulty),Rect2(114,1040,800,25),13,LILAC,host.BOLD)


func refresh_records() -> void:
	for id: String in _rows:
		var status: Label = (_rows[id] as Button).get_node("Status")
		var record: Dictionary = RhythmRecords.best(id, difficulty)
		status.text = "NOT PLAYED" if record.is_empty() else "%s  ·  %07d" % [record.rank, record.score]
	_render_detail()


func _toggle_preview() -> void:
	if _previewing:
		preview_stopped.emit()
		preview_finished()
	else:
		_previewing = true
		_preview_button.text = "STOP PREVIEW"
		preview_requested.emit(selected)


func preview_finished() -> void:
	_previewing = false
	if is_instance_valid(_preview_button):
		_preview_button.text = "PREVIEW"


func _select_difficulty(value: String) -> void:
	difficulty = value
	_update_difficulty_styles()
	_count.text = "%02d / %02d SONGS   ·   %s" % [_filtered.size(), SongCatalog.SONGS.size(), difficulty.to_upper()]
	var playing: bool = _previewing
	refresh_records()
	_previewing = playing
	_preview_button.text = "STOP PREVIEW" if playing else "PREVIEW"


func _update_difficulty_styles() -> void:
	for button: Button in _difficulty_buttons:
		var active: bool = button.text == difficulty.to_upper()
		button.add_theme_stylebox_override("normal", host._style(Color(0.45, 0.38, 0.72, 0.65) if active else Color(0.07, 0.08, 0.18, 0.86), LILAC if active else Color(0.7, 0.66, 1, 0.23), 18))


func _right_x() -> float:
	return 1045.0


func _right_width() -> float:
	return _width - _right_x() - 58.0


static func format_time(seconds: int) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
