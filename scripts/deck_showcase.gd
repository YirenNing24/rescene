class_name DeckShowcase
extends Control
## Visual carousel only. Every equipped card contributes throughout the song.
const PANEL_SIZE: Vector2 = Vector2(244, 410)
const PORTRAIT_RECT: Rect2 = Rect2(32, 47, 180, 278)
var host: ResceneMainMenu
var set_id: String = "pulse"
var deck_ids: Array[String] = []
var _slots: Array[int] = []
var _slot: int = -1
var _portrait: Control
var _member_label: Label
var _detail_label: Label
var _pips: Array[Panel] = []
var _clock: float = 0.0
var _skill_until: float = 0.0
var _skill_slot: int = -1
var _skill_text: String = ""
var _portraits: Dictionary[int, Control] = {}
var _details: Dictionary[int, Dictionary] = {}
var _pip_active: StyleBoxFlat
var _pip_idle: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _panel: Panel = host._panel(self, Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.075, 0.065, 0.14, 0.78), Color(host.LILAC, 0.3), 21)
	var _caption: Label = host._label(self, str(SongSets.find_set(set_id).get("name", "")).to_upper() + " / YOUR TEAM", Rect2(12, 16, 220, 20), 11, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_member_label = host._label(self, "", Rect2(12, 333, 220, 28), 18, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_detail_label = host._label(self, "", Rect2(12, 365, 220, 22), 12, host.LILAC, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
	_detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pip_active = host._style(host.LILAC, Color.TRANSPARENT, 2)
	_pip_idle = host._style(Color(host.LILAC, 0.18), Color.TRANSPARENT, 2)
	for index: int in 5:
		var pip: Panel = host._panel(self, Rect2(37 + index * 36, 396, 26, 4), Color(host.LILAC, 0.18), Color.TRANSPARENT, 2)
		_pips.append(pip)
	configure(deck_ids)

func configure(ids: Array[String]) -> void:
	for portrait: Control in _portraits.values(): portrait.hide(); portrait.queue_free()
	_portraits.clear(); _details.clear()
	deck_ids = ids.duplicate(); _slot = -1
	_slots.clear()
	_skill_slot = -1; _skill_until = 0.0; _skill_text = ""
	for index: int in mini(5, deck_ids.size()):
		if GameServices.commerce().owned(deck_ids[index]) > 0:
			_slots.append(index)
			_details[index] = GameServices.commerce().item_details(deck_ids[index])
			if is_instance_valid(_member_label):
				var portrait: Control = Control.new(); portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
				host._at(self, portrait, PORTRAIT_RECT)
				var art: MemberCardArt = MemberCardArt.new(); art.host = host; art.item_id = deck_ids[index]
				host._at(portrait, art, Rect2(Vector2.ZERO, PORTRAIT_RECT.size))
				portrait.hide(); _portraits[index] = portrait
	visible = not _slots.is_empty()
	for index: int in _pips.size():
		_pips[index].visible = _slots.size() > 1 and index < _slots.size()
		_pips[index].position.x = PANEL_SIZE.x * 0.5 - float(_slots.size() * 36 - 10) * 0.5 + index * 36
	if is_instance_valid(_member_label): show_time(_clock)

func show_time(seconds: float) -> void:
	_clock = maxf(0.0, seconds)
	if _slots.is_empty(): return
	var active_skill: bool = _clock < _skill_until and _skill_slot in _slots
	var slot: int = _skill_slot if active_skill else _slots[floori(_clock / 4.5) % _slots.size()]
	var phase: float = 2.0 if active_skill else fposmod(_clock, 4.5)
	if slot != _slot:
		_slot = slot
		if is_instance_valid(_portrait): _portrait.hide()
		_portrait = _portraits[slot]
		_portrait.show()
		var details: Dictionary = _details[slot]
		if not details.is_empty():
			_member_label.text = SongSets.MEMBERS[slot] + "  " + "★".repeat(clampi(StrictData.integer(details.get("stars", 1)), 1, 5))
			_detail_label.text = "LV. %d  /  %s" % [StrictData.integer(details.get("level", 1)), str(details.get("skill", ""))]
		for index: int in _pips.size(): _pips[index].add_theme_stylebox_override("panel", _pip_active if index == _slots.find(slot) else _pip_idle)
	if active_skill: _detail_label.text = _skill_text
	elif _slot == slot and _detail_label.text == _skill_text and not _skill_text.is_empty():
		_slot = -1; _skill_text = ""; show_time(seconds); return
	if is_instance_valid(_portrait) and _slots.size() == 1:
		_portrait.position = PORTRAIT_RECT.position
		_portrait.modulate.a = 1.0
	elif is_instance_valid(_portrait):
		_portrait.position.x = PORTRAIT_RECT.position.x + (1.0 - minf(1.0, phase / 0.35)) * 12.0
		_portrait.modulate.a = minf(1.0, phase / 0.3) * minf(1.0, (4.5 - phase) / 0.3)
		_portrait.position.y = PORTRAIT_RECT.position.y + sin(phase * 1.4) * 2.0

func show_skill(skill_name: String, description: String) -> void:
	var strongest: int = -1
	var best_stars: int = -1
	for index: int in _slots:
		var item: Dictionary = _details[index]
		if str(item.get("skill", "")) == skill_name and StrictData.integer(item.get("stars",0)) > best_stars:
			strongest = index; best_stars = StrictData.integer(item.get("stars",0))
	if strongest < 0: return
	_skill_slot = strongest; _skill_until = _clock+2.0; _skill_text = skill_name.to_upper()+"  ·  "+description
	_slot = -1; show_time(_clock)
	_detail_label.add_theme_color_override("font_color",host.WHITE)
	if _slots.size() == 1: return
	var effect: Tween = create_tween()
	var _fade: PropertyTweener = effect.tween_property(_detail_label,"modulate:a",0.55,0.16)
	var _return: PropertyTweener = effect.tween_property(_detail_label,"modulate:a",1.0,0.16)
