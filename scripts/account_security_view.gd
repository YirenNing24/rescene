class_name AccountSecurityView
extends MenuDestination
var _current: LineEdit
var _next: LineEdit
var _confirm: LineEdit
var _status: Label
var _codes: TextEdit
var _count: Label
var _busy: bool = false
var _buttons: Array[Button] = []

func _ready() -> void:
	name = "AccountSecurity"; mouse_filter = Control.MOUSE_FILTER_STOP
	body = Control.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(body)
	var _frame: Panel = host._panel(body, Rect2(45, 160, host._width - 90, 880), Color("151324"), Color(host.LILAC, 0.4), 26)
	var _back: Button = host._button(body, "‹", Rect2(75, 195, 66, 62), go_back)
	var _title: Label = host._label(body, "ACCOUNT SECURITY", Rect2(170, 200, 1500, 54), 36, host.WHITE, host.BOLD)
	var _subtitle: Label = host._label(body, "Your account, wallet and collection stay together. Keep your recovery codes private.", Rect2(173, 270, 1800, 38), 20, host.LILAC)
	var _left: Label = host._label(body, "Change password", Rect2(108, 358, 800, 55), 43, host.WHITE, host.SERIF)
	_current = _field("CURRENT PASSWORD", Rect2(110, 452, 820, 65))
	_next = _field("NEW PASSWORD", Rect2(110, 567, 820, 65))
	_confirm = _field("CONFIRM NEW PASSWORD", Rect2(110, 682, 820, 65))
	var change: Button = host._button(body, "CHANGE PASSWORD", Rect2(110, 802, 820, 73), func() -> void: _change.call_deferred(), true)
	change.name = "ChangePassword"; _buttons.append(change)
	var warning: Label = host._label(body, "All existing logins will end. Log in with the new password afterward.", Rect2(114, 909, 800, 70), 19, host.MUTED)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var x: float = host._width * 0.46
	var _right: Label = host._label(body, "Recovery codes", Rect2(x, 358, host._width - x - 110, 55), 43, host.WHITE, host.SERIF)
	_count = host._label(body, "Loading…", Rect2(x + 4, 430, host._width - x - 110, 32), 19, host.LILAC)
	var hint: Label = host._label(body, "Enter your current password on the left to generate eight one-time codes. New codes replace all previous codes.", Rect2(x + 4, 484, host._width - x - 115, 96), 21, host.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var generate: Button = host._button(body, "GENERATE NEW RECOVERY CODES", Rect2(x, 606, host._width - x - 105, 67), func() -> void: _generate.call_deferred())
	generate.name = "GenerateRecoveryCodes"; _buttons.append(generate)
	_codes = TextEdit.new(); _codes.name = "RecoveryCodes"; _codes.editable = false
	_codes.placeholder_text = "Your codes appear here once. Save them somewhere private."
	_codes.add_theme_font_override("font", host.FONT); _codes.add_theme_font_size_override("font_size", 20)
	_codes.add_theme_stylebox_override("read_only", host._style(Color("201b32"), Color(host.LILAC, 0.25), 14))
	host._at(body, _codes, Rect2(x, 699, host._width - x - 105, 230))
	_codes.mouse_filter = Control.MOUSE_FILTER_STOP
	var copy: Button = host._button(body, "COPY CODES", Rect2(x, 948, 220, 50), func() -> void:
		if not _codes.text.is_empty(): DisplayServer.clipboard_set(_codes.text); _status.text = "Codes copied. Store them privately.")
	_buttons.append(copy)
	_status = host._label(body, "", Rect2(110, 1004, host._width - 220, 29), 17, host.LILAC)
	_refresh.call_deferred()

func _field(caption: String, rect: Rect2) -> LineEdit:
	var _caption: Label = host._label(body, caption, Rect2(rect.position - Vector2(0, 35), Vector2(rect.size.x, 25)), 14, host.LILAC, host.BOLD)
	var field: LineEdit = LineEdit.new(); field.secret = true; field.max_length = 72
	field.add_theme_font_override("font", host.FONT); field.add_theme_font_size_override("font_size", 23)
	field.add_theme_stylebox_override("normal", host._style(Color("211c34"), Color(host.LILAC, 0.4), 14)); field.add_theme_stylebox_override("focus", host._style(Color("211c34"), host.LILAC, 14))
	host._at(body, field, rect); return field

func _refresh() -> void:
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/account/security")
	if not is_inside_tree(): return
	if response.ok: _count.text = "%d ONE-TIME CODES REMAINING" % StrictData.integer(StrictData.dictionary(StrictData.dictionary(response.data).get("security", {})).get("recovery_codes_remaining", 0))
	else: _status.text = str(response.get("message", "Could not load account security."))

func _set_busy(value: bool) -> void:
	_busy = value
	for button: Button in _buttons: button.disabled = value

func _generate() -> void:
	if _busy: return
	_set_busy(true)
	var response: Dictionary = await GameServices.session()._send("/api/v1/account/recovery-codes", HTTPClient.METHOD_POST, {"password":_current.text})
	if not is_inside_tree(): return
	_set_busy(false); _current.clear()
	if response.ok:
		var codes: PackedStringArray = PackedStringArray()
		for raw: Variant in StrictData.array(StrictData.dictionary(response.data).get("recovery_codes", [])):
			var _appended: bool = codes.append(str(raw))
		_codes.text = "\n".join(codes); _count.text = "8 ONE-TIME CODES REMAINING"
		_status.text = "Save these codes now. They cannot be displayed again."
	else: _status.text = str(response.get("message", "Could not generate recovery codes."))

func _change() -> void:
	if _busy: return
	if _next.text != _confirm.text: _status.text = "The new passwords do not match."; return
	_set_busy(true)
	var response: Dictionary = await GameServices.session()._send("/api/v1/account/password", HTTPClient.METHOD_POST, {"current_password":_current.text,"new_password":_next.text})
	if not is_inside_tree(): return
	_current.clear(); _next.clear(); _confirm.clear(); _set_busy(false)
	if response.ok: GameServices.session().logout("Password changed. Log in with your new password.")
	else: _status.text = str(response.get("message", "Could not change your password."))

func snapshot() -> Dictionary:
	return {"codes":_codes.text, "status":_status.text}

func restore(saved: Dictionary) -> void:
	_codes.text = str(saved.get("codes", "")); _status.text = str(saved.get("status", ""))
