class_name CardArtworkViewer
extends CanvasLayer
## A full-height, uncropped card view above the current menu destination.

var host: ResceneMainMenu
var item_id: String
var _canvas: Control
var _layout_root: Control
var _artwork: MemberCardArt
var _close_button: Button
var _previous_focus: WeakRef
var _previous_quit_on_back: bool = true


func _ready() -> void:
	name = "CardArtworkViewer"
	layer = 60
	_previous_quit_on_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: _previous_focus = weakref(focused)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_root = Control.new()
	_canvas.add_child(_layout_root)
	var backdrop: Button = host._button(_layout_root, "", Rect2(), close)
	backdrop.name = "CloseCardBackdrop"
	backdrop.focus_mode = Control.FOCUS_NONE
	for style: String in ["normal", "hover", "pressed", "focus"]:
		backdrop.add_theme_stylebox_override(style, host._style(Color(0.025, 0.024, 0.055, 0.96), Color.TRANSPARENT, 0))
	var item: Dictionary = MarketCatalog.find_item(item_id)
	var _tag: Label = host._label(_layout_root, str(item.get("tag", "PHOTO CARD")), Rect2(60, 55, 500, 30), 17, host.LILAC, host.BOLD)
	_artwork = MemberCardArt.new()
	_artwork.host = host
	_artwork.item_id = item_id
	host._at(_layout_root, _artwork, Rect2())
	# The artwork catches clicks so admiring the card does not dismiss it.
	_artwork.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button = host._icon_button(_layout_root, "close", Rect2(0, 0, 80, 80), close)
	_close_button.name = "CloseCardArtwork"
	_close_button.tooltip_text = "Close card view"
	var caption: Label = host._label(_layout_root, str(item.get("name", "")), Rect2(), 25, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "CardCaption"
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var _resized: int = _canvas.resized.connect(_layout)
	_layout()
	_close_button.grab_focus()
	_layout_root.modulate.a = 0.0
	var _fade: PropertyTweener = create_tween().tween_property(_layout_root, "modulate:a", 1.0, 0.14)


func _layout() -> void:
	var factor: float = minf(_canvas.size.x / 2400.0, _canvas.size.y / 1080.0)
	if factor <= 0.0: return
	var width: float = _canvas.size.x / factor
	var height: float = _canvas.size.y / factor
	_layout_root.scale = Vector2.ONE * factor
	_layout_root.size = Vector2(width, height)
	(_layout_root.get_node("CloseCardBackdrop") as Button).size = _layout_root.size
	_artwork.position = Vector2((width - 760.0) * 0.5, 35)
	_artwork.size = Vector2(760, height - 125)
	_close_button.position = Vector2(width - 132, 38)
	_close_button.size = Vector2(80, 80)
	var caption: Label = _layout_root.get_node("CardCaption") as Label
	caption.position = Vector2(140, height - 64)
	caption.size = Vector2(width - 280, 36)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: close()


func _exit_tree() -> void:
	# Restore after the Android Back notification has finished dispatching.
	get_tree().quit_on_go_back = _previous_quit_on_back


func close() -> void:
	if is_queued_for_deletion(): return
	hide()
	set_process_input(false)
	if _previous_focus != null:
		var reference: Variant = _previous_focus.get_ref()
		if reference is Control:
			var focused: Control = reference
			if focused.is_visible_in_tree(): focused.grab_focus()
	queue_free()
