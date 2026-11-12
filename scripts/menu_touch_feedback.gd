class_name MenuTouchFeedback
extends CanvasLayer
## One input-transparent overlay for menu taps, including dialogs and login.

const DURATION: float = 0.42
const MAX_PULSES: int = 8
const LILAC: Color = Color("d4c4ff")
const ICE: Color = Color("c4e6f3")
const WHITE: Color = Color("fcf8ff")

class TouchPulse extends RefCounted:
	var point: Vector2
	var age: float = 0.0
	var phase: float

	func _init(at: Vector2, phase_angle: float) -> void:
		point = at
		phase = phase_angle

var _canvas: Control
var _glow: GradientTexture2D
var _pulses: Array[TouchPulse] = []
var _gameplay: Dictionary[int, bool] = {}
var _enabled: bool = true
var _last_touch_frame: int = -1
var _sequence: int = 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.name = "TouchSparkles"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = additive
	var _draw_connection: int = _canvas.draw.connect(_draw_feedback)
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 64
	_glow.height = 64
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://lobby.cfg") == OK:
		_enabled = StrictData.boolean(config.get_value("settings", "particles", true))
	set_process_input(_enabled)
	set_process(false)


func set_enabled(value: bool) -> void:
	_enabled = value
	set_process_input(_enabled and _gameplay.is_empty())
	if not value: _clear()


func set_gameplay_active(instance_id: int, active: bool) -> void:
	if active:
		_gameplay[instance_id] = true
		_clear()
	else:
		var _removed: bool = _gameplay.erase(instance_id)
	set_process_input(_enabled and _gameplay.is_empty())


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		_last_touch_frame = Engine.get_process_frames()
		if touch.pressed and not touch.canceled: _emit_pulse(touch.position)
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT: return
		if click.device == InputEvent.DEVICE_ID_EMULATION:
			# Android can dispatch the emulated click before the real touch.
			_emulated_click.call_deferred(click.position, Engine.get_process_frames())
		else:
			_emit_pulse(click.position)


func _emulated_click(point: Vector2, frame: int) -> void:
	if _last_touch_frame < frame: _emit_pulse(point)


func _emit_pulse(point: Vector2) -> void:
	if not _enabled or not _gameplay.is_empty(): return
	if _pulses.size() == MAX_PULSES:
		var _oldest: TouchPulse = _pulses.pop_front()
	_sequence += 1
	_pulses.append(TouchPulse.new(point, float(_sequence) * 2.39996))
	set_process(true)
	_canvas.queue_redraw()


func _clear() -> void:
	_pulses.clear()
	set_process(false)
	if is_instance_valid(_canvas): _canvas.queue_redraw()


func _process(delta: float) -> void:
	for index: int in range(_pulses.size() - 1, -1, -1):
		_pulses[index].age += delta
		if _pulses[index].age >= DURATION: _pulses.remove_at(index)
	_canvas.queue_redraw()
	if _pulses.is_empty(): set_process(false)


func _draw_feedback() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var unit: float = minf(viewport_size.x / 2400.0, viewport_size.y / 1080.0)
	for pulse: TouchPulse in _pulses:
		var progress: float = clampf(pulse.age / DURATION, 0.0, 1.0)
		var travel: float = 1.0 - pow(1.0 - progress, 3.0)
		var fade: float = pow(1.0 - progress, 1.5)
		var tint: Color = LILAC.lerp(ICE, (sin(pulse.phase) + 1.0) * 0.25)
		var radius: float = lerpf(10.0, 56.0, travel) * unit
		var glow_radius: float = lerpf(32.0, 52.0, travel) * unit
		_canvas.draw_texture_rect(_glow, Rect2(pulse.point - Vector2.ONE * glow_radius, Vector2.ONE * glow_radius * 2.0), false, Color(tint, fade * 0.65))
		_canvas.draw_arc(pulse.point, radius, 0.0, TAU, 64, Color(tint, fade * 0.8), 1.6 * unit, true)
		_canvas.draw_arc(pulse.point, radius * 0.74, pulse.phase + progress, pulse.phase + progress + PI * 1.35, 48, Color(WHITE, fade * 0.32), 1.0 * unit, true)
		for spark: int in 6:
			var angle: float = pulse.phase + TAU * float(spark) / 6.0
			var direction: Vector2 = Vector2.from_angle(angle)
			var point: Vector2 = pulse.point + direction * lerpf(17.0, 76.0 + float(spark % 3) * 7.0, travel) * unit
			var length: float = (4.0 + float(spark % 2) * 3.0) * fade * unit
			_canvas.draw_line(point - direction * 9.0 * unit, point, Color(tint, fade * 0.23), 1.0 * unit, true)
			_canvas.draw_line(point - Vector2.RIGHT * length, point + Vector2.RIGHT * length, Color(WHITE, fade * 0.9), 1.4 * unit, true)
			_canvas.draw_line(point - Vector2.DOWN * length * 1.4, point + Vector2.DOWN * length * 1.4, Color(tint, fade), 1.2 * unit, true)
