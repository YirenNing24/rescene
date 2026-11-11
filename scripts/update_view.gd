class_name AppUpdateView
extends Control

const FONT: FontFile = preload("res://assets/fonts/Montserrat-Medium.otf")
const BOLD: FontFile = preload("res://assets/fonts/Montserrat-SemiBold.otf")
var service: AppUpdateService
var _status: Label
var _notes: Label
var _progress: ProgressBar
var _amount: Label
var _primary: Button
var _pause: Button
var _close: Button

static func open(parent: Node) -> AppUpdateView:
	var view: AppUpdateView = AppUpdateView.new()
	parent.add_child(view)
	return view

func _ready() -> void:
	service = get_node("/root/AppUpdates") as AppUpdateService
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0.025, 0.03, 0.07, 0.9)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(840, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("181a30")
	style.border_color = Color("8c83bd")
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	var title: Label = _label("KEEP YOUR RHYTHM", 36)
	title.add_theme_font_override("font", BOLD)
	column.add_child(title)
	column.add_child(_label("Installed version · " + service.current_version(), 18))
	_status = _label("", 25)
	column.add_child(_status)
	_notes = _label("", 20)
	_notes.max_lines_visible = 5
	column.add_child(_notes)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 18
	_progress.show_percentage = false
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color("2c2b46")
	track.set_corner_radius_all(9)
	_progress.add_theme_stylebox_override("background", track)
	var fill: StyleBoxFlat = track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("cabaff")
	_progress.add_theme_stylebox_override("fill", fill)
	column.add_child(_progress)
	_amount = _label("", 18)
	column.add_child(_amount)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_primary = _button("Check for updates", _activate)
	row.add_child(_primary)
	_pause = _button("Pause", service.pause)
	row.add_child(_pause)
	_close = _button("Close", _dismiss)
	row.add_child(_close)
	var _changed: int = service.changed.connect(_refresh)
	_refresh()
	if not service.active() and service.phase in ["idle", "error", "current"]: service.check.call_deferred()

func _label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size.x = 750
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("e6e0ff"))
	return label

func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230, 64)
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 20)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color("cfc3ff")
	normal.set_corner_radius_all(16)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("e2d9ff")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("202039"))
	button.add_theme_color_override("font_hover_color", Color("202039"))
	button.add_theme_color_override("font_pressed_color", Color("202039"))
	var _pressed: int = button.pressed.connect(action)
	return button

func _refresh() -> void:
	_status.text = service.message
	_notes.text = ""
	_notes.visible = service.available()
	if service.available(): _notes.text = "Version %s · %.1f MB\n%s" % [str(service.release.version), float(StrictData.integer(service.release.bytes)) / 1000000.0, str(service.release.release_notes)]
	_progress.visible = service.available()
	_progress.max_value = float(StrictData.integer(service.release.get("bytes", 1)))
	_progress.value = float(service.downloaded)
	_amount.text = "%.1f / %.1f MB" % [float(service.downloaded) / 1000000.0, float(StrictData.integer(service.release.get("bytes", 0))) / 1000000.0] if service.available() else ""
	_amount.visible = service.available()
	_primary.text = "Install update" if service.phase == "ready" else "Resume download" if service.phase == "paused" else "Download update" if service.available() else "Check again"
	_primary.disabled = service.active() or (service.available() and not OS.has_feature("android") and service.test_origin.is_empty())
	_pause.visible = service.phase == "downloading"
	_close.text = "Close & pause" if service.phase == "downloading" else "Close"

func _activate() -> void:
	if service.phase == "ready": await service.install()
	elif service.available(): await service.download()
	else: await service.check()

func _dismiss() -> void:
	service.pause()
	service.dismissed_code = StrictData.integer(service.release.get("version_code", 0))
	queue_free()
