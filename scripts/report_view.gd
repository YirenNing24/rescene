class_name ReportView
extends Control
var host: ResceneMainMenu
var player_id: String
var target_type: String = "player"
var target_id: String = ""
var _reason: OptionButton
var _details: TextEdit
var _status: Label
var _submit: Button
var _busy: bool = false
var _request: Dictionary = {}
const REASONS: Array[String] = ["harassment", "spam", "inappropriate_content", "cheating", "other"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil: ColorRect = ColorRect.new(); veil.color = Color(0.015, 0.01, 0.04, 0.85)
	host._at(self, veil, Rect2(0, 0, host._width, 1080))
	var x: float = (host._width - 940.0) * 0.5
	var _frame: Panel = host._panel(self, Rect2(x, 215, 940, 670), Color("201b32"), host.LILAC, 27)
	var _title: Label = host._label(self, "Report " + target_type, Rect2(x + 50, 256, 800, 60), 40, host.WHITE, host.SERIF)
	var _hint: Label = host._label(self, "Our moderators will review the report. You can also block this player.", Rect2(x + 54, 335, 830, 40), 20, host.MUTED)
	_reason = OptionButton.new()
	for reason: String in REASONS: _reason.add_item(reason.replace("_", " ").capitalize())
	_reason.add_theme_font_override("font", host.FONT); _reason.add_theme_font_size_override("font_size", 24)
	_reason.add_theme_stylebox_override("normal", host._style(Color("302841"), Color(host.LILAC, 0.4), 14))
	host._at(self, _reason, Rect2(x + 50, 403, 840, 65))
	_details = TextEdit.new(); _details.placeholder_text = "What happened? (Optional, up to 1,500 UTF-8 bytes)"; _details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_details.add_theme_font_override("font", host.FONT); _details.add_theme_font_size_override("font_size", 22)
	_details.add_theme_stylebox_override("normal", host._style(Color("151324"), Color(host.LILAC, 0.3), 14))
	host._at(self, _details, Rect2(x + 50, 493, 840, 188)); _details.mouse_filter = Control.MOUSE_FILTER_STOP
	_status = host._label(self, "", Rect2(x + 55, 699, 830, 62), 20, host.LILAC); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var _close: Button = host._button(self, "CLOSE", Rect2(x + 50, 787, 270, 62), func() -> void:
		if not _busy: hide(); queue_free())
	_submit = host._button(self, "SEND REPORT", Rect2(x + 350, 787, 540, 62), func() -> void: _send.call_deferred(), true)

func _send() -> void:
	if _busy: return
	if _details.text.to_utf8_buffer().size() > 1500: _status.text = "Please shorten your report to 1,500 UTF-8 bytes."; return
	if _request.is_empty():
		_request = {"request_id":Crypto.new().generate_random_bytes(16).hex_encode(), "target_type":target_type, "player_id":player_id, "target_id":target_id, "reason":REASONS[_reason.selected], "details":_details.text}
	_busy = true; _submit.disabled = true; _details.editable = false; _reason.disabled = true
	var response: Dictionary = await GameServices.session()._send("/api/v1/reports", HTTPClient.METHOD_POST, _request)
	if not is_inside_tree(): return
	_busy = false
	if response.ok: _status.text = "Report received. Thank you for helping keep the community welcoming."
	else: _status.text = str(response.get("message", "Could not send. Try again.")); _submit.disabled = false; _submit.text = "RETRY REPORT"
