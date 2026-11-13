class_name ProgressionView
extends MenuDestination
## Missions and cosmetic unlocks, using the lobby's existing native UI styling.

var tab: String = "missions"
var _message: Label
var _busy: bool = false
var _scroll: ScrollContainer
var _rendered_tab: String = ""

func _ready() -> void:
	name = "ProgressionView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _int_1: int = GameServices.progression().changed.connect(_render)
	_render()

func _render() -> void:
	var scroll_position: int = _scroll.scroll_vertical if is_instance_valid(_scroll) and _rendered_tab == tab else 0
	_rendered_tab = tab
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var _panel_2: Panel = host._panel(body, Rect2(30, 155, host._width-60, 885), Color(0.055,0.06,0.13,1.0), Color(0.72,0.68,0.95,0.35), 26)
	var back: Button = host._button(body, "‹", Rect2(60, 185, 72, 65), host._close_dialog)
	back.add_theme_font_size_override("font_size", 35)
	var _label_3: Label = host._label(body, "YOUR JOURNEY", Rect2(159, 185, 670, 50), 36, host.WHITE, host.BOLD)
	var _label_4: Label = host._label(body, "EVERY BEAT, A LITTLE CLOSER TO YOUR SCENE", Rect2(162, 243, 1000, 26), 13, host.LILAC)
	var _button_5: Button = host._button(body, "MISSIONS", Rect2(1100, 189, 340, 64), func() -> void: tab = "missions"; _render(), tab == "missions", true, host.LILAC)
	var _button_6: Button = host._button(body, "UNLOCKS", Rect2(1460, 189, 340, 64), func() -> void: tab = "unlocks"; _render(), tab == "unlocks", true, host.LILAC)
	var _button_7: Button = host._button(body, "REFRESH", Rect2(host._width-350, 189, 260, 64), func() -> void: GameServices.progression().refresh.call_deferred())
	_summary()
	if GameServices.progression().state.is_empty():
		var _label_8: Label = host._label(body, "Your journey is loading…" if GameServices.progression().loading else "Connect to the server to load your journey.", Rect2(700, 450, 1500, 60), 28, host.MUTED)
	else:
		var scroll: ActionListScroll = ActionListScroll.new()
		_scroll = scroll
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.row_count = StrictData.array(GameServices.progression().state.get(tab, [])).size()
		scroll.row_height = 166.0 if tab == "missions" else 146.0
		scroll.row_step = scroll.row_height + 16.0
		host._at(body, scroll, Rect2(650, 320, host._width-740, 610))
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		var list: VBoxContainer = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 16)
		scroll.add_child(list)
		if tab == "missions":
			for mission: Dictionary in GameServices.progression().state.get("missions", []): _mission_row(list, mission)
		else:
			for item: Dictionary in GameServices.progression().state.get("unlocks", []): _unlock_row(list, item)
		scroll.set_deferred("scroll_vertical", scroll_position)
	_message = host._label(body, GameServices.progression().error_message, Rect2(653, 954, host._width-750, 55), 19, host.LILAC)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _message.text.is_empty():
		_message.text = "Daily missions reset at 00:00 UTC. Claim completed rewards here." if tab == "missions" else "Cosmetics only. Every song and difficulty is available from the start."

func _summary() -> void:
	var state: Dictionary = GameServices.progression().state
	var _panel_9: Panel = host._panel(body, Rect2(60, 320, 545, 680), Color(0.16,0.14,0.26,0.72), Color(0.7,0.65,0.95,0.28), 22)
	var _label_10: Label = host._label(body, "BACKSTAGE PASS", Rect2(90, 349, 470, 30), 16, host.LILAC, host.BOLD)
	var _label_11: Label = host._label(body, "LEVEL %02d" % StrictData.integer(state.get("level", 1)), Rect2(88, 409, 470, 90), 59, host.WHITE, host.BOLD)
	var _label_12: Label = host._label(body, GameServices.progression().equipped_title(), Rect2(93, 509, 470, 42), 29, host.LILAC, host.SERIF)
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxf(1, StrictData.number(state.get("level_cost", 200)))
	bar.value = StrictData.number(state.get("level_xp", 0))
	bar.add_theme_stylebox_override("background", host._style(Color(0.07,0.07,0.15), Color.TRANSPARENT, 8))
	bar.add_theme_stylebox_override("fill", host._style(host.MINT, Color.TRANSPARENT, 8))
	host._at(body, bar, Rect2(93, 582, 470, 16))
	var xp: String = "%d / %d XP" % [state.get("level_xp",0), state.get("level_cost",200)]
	if StrictData.integer(state.get("level", 1)) == 100: xp = "MAX LEVEL"
	var _label_13: Label = host._label(body, xp, Rect2(93, 617, 470, 30), 20, host.MUTED)
	var _label_14: Label = host._label(body, "%s  STARLIGHT" % GameServices.progression().starlight_text(), Rect2(93, 699, 470, 40), 27, host.WHITE, host.BOLD)
	_label_14.tooltip_text = GameServices.progression().starlight_hint()
	var _label_15: Label = host._label(body, "%d  SONGS CLEARED" % StrictData.integer(state.get("clears",0)), Rect2(93, 760, 470, 35), 20, host.MUTED)
	var _label_16: Label = host._label(body, "%d  BEST COMBO" % StrictData.integer(state.get("max_combo",0)), Rect2(93, 813, 470, 35), 20, host.MUTED)
	var note: Label = Label.new()
	note.name = "ProgressionHint"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Clear songs with 50%+ accuracy to earn XP. First clears earn a bonus. Each song attempt costs 1 energy."
	note.add_theme_font_override("font", host.FONT)
	note.add_theme_font_size_override("font_size",18)
	note.add_theme_color_override("font_color",host.LILAC)
	host._at(body,note,Rect2(93,885,470,90))

func _mission_row(list: VBoxContainer, mission: Dictionary) -> void:
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0, 166)
	list.add_child(row)
	var width: float = host._width-765
	var _panel_17: Panel = host._panel(row, Rect2(0,0,width,166), Color(0.13,0.12,0.22,0.9), Color(0.68,0.64,0.88,0.3), 18)
	var title: String = mission.name + ("  /  DAILY" if mission.scope == "daily" else "  /  CAREER")
	var _label_18: Label = host._label(row, title, Rect2(24,17,width-530,34), 23, host.WHITE, host.BOLD)
	var _label_19: Label = host._label(row,str(mission.description), Rect2(25,61,width-540,30), 19, host.MUTED)
	var meter: ProgressBar = ProgressBar.new()
	meter.max_value = StrictData.number(mission.target)
	meter.value = StrictData.number(mission.progress)
	meter.show_percentage = false
	meter.add_theme_stylebox_override("background", host._style(Color(0.05,0.05,0.12), Color.TRANSPARENT, 5))
	meter.add_theme_stylebox_override("fill", host._style(host.MINT, Color.TRANSPARENT, 5))
	host._at(row, meter, Rect2(25,119,width-810,9))
	var _label_20: Label = host._label(row, "%d / %d" % [mission.progress,mission.target], Rect2(width-760,106,200,30), 16, host.LILAC)
	var _label_21: Label = host._label(row, "+%d XP" % StrictData.integer(mission.xp), Rect2(width-530,41,260,34), 25, host.LILAC, host.BOLD)
	var _label_22: Label = host._label(row, "+%d Starlight" % StrictData.integer(mission.starlight), Rect2(width-530,87,260,30), 18, host.MUTED)
	var label: String = "CLAIMED" if mission.claimed else ("CLAIM" if mission.progress >= mission.target else "IN PROGRESS")
	var button: Button = host._button(row, label, Rect2(width-260,45,235,74), func() -> void: await _claim(mission),StrictData.boolean(not mission.claimed and mission.progress >= mission.target))
	button.disabled = _busy or mission.claimed or mission.progress < mission.target
	button.add_theme_font_size_override("font_size",17)
	(_scroll as ActionListScroll).actions.append(button)
	_style_disabled(button)

func _unlock_row(list: VBoxContainer, item: Dictionary) -> void:
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0, 146)
	list.add_child(row)
	var width: float = host._width-765
	var tint: Color = Color(str(item.color)) if item.kind == "frame" else host.LILAC
	var _panel_23: Panel = host._panel(row, Rect2(0,0,width,146), Color(0.13,0.12,0.22,0.9), Color(tint,0.4), 18)
	var _texturerect_24: TextureRect = host._icon(row, "person" if item.kind == "frame" else "star", Rect2(28,43,55,55), tint)
	var _label_25: Label = host._label(row,str(item.name + "  /  " + str(item.kind).to_upper()), Rect2(116,24,width-460,38), 27, host.WHITE, host.BOLD)
	var _label_26: Label = host._label(row,str("UNLOCKED  ·  " + item.requirement if item.unlocked else item.requirement), Rect2(118,82,width-460,32), 19, host.MUTED)
	var label: String = "EQUIPPED" if item.equipped else ("EQUIP" if item.unlocked else "LOCKED")
	var button: Button = host._button(row, label, Rect2(width-260,36,235,74), func() -> void: await _equip(str(item.id)),StrictData.boolean(item.unlocked and not item.equipped))
	button.disabled = _busy or not item.unlocked or item.equipped
	(_scroll as ActionListScroll).actions.append(button)
	_style_disabled(button)

func _style_disabled(button: Button) -> void:
	button.add_theme_stylebox_override("disabled", host._style(Color(0.09,0.09,0.17), Color(0.5,0.48,0.65,0.25),16))
	button.add_theme_color_override("font_disabled_color", host.MUTED)

func _claim(mission: Dictionary) -> void:
	if _busy: return
	_busy = true
	_render()
	var response: Dictionary = await GameServices.progression().claim(str(mission.id), str(GameServices.progression().state.get("day", "")))
	if not is_inside_tree(): return
	_busy = false
	_render()
	if response.ok:
		_message.text = "REWARD CLAIMED  /  +%d XP  ·  +%d Starlight" % [response.data.reward.xp,response.data.reward.starlight]
		if response.data.reward.level_after > response.data.reward.level_before: _message.text += "  ·  LEVEL UP!"
	else: _message.text = response.message

func _equip(cosmetic_id: String) -> void:
	if _busy: return
	_busy = true
	_render()
	var response: Dictionary = await GameServices.progression().equip(cosmetic_id)
	if not is_inside_tree(): return
	_busy = false
	_render()
	if not response.ok: _message.text = response.message
