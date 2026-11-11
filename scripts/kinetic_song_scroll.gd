class_name KineticSongScroll
extends ScrollContainer
## One scroll owner for touch, mouse dragging, wheels and trackpads.
## Rows center where possible; first/last rows stay flush with the list edges.

signal movement_started
signal focused_index_changed(index: int)
signal settled(index: int)

var interaction_allowed: Callable
var row_step: float = 125.0
var row_height: float = 113.0
var row_count: int = 0
var velocity: float = 0.0
var _offset: float = 0.0
var _target: float = 0.0
var _snapping: bool = false
var _moving: bool = false
var _pressed: bool = false
var _dragging: bool = false
var _touch_index: int = -1
var _press_point: Vector2
var _last_point: Vector2
var _last_motion_time: float = 0.0
var _last_index: int = -1
var _writing_bar: bool = false
var _bar_idle: float = 0.0
var _scrollbar_pressed: bool = false
var _focus_override: int = -1


func _ready() -> void:
	follow_focus = false
	var _int_1: int = get_v_scroll_bar().value_changed.connect(_bar_changed)
	var _int_2: int = get_v_scroll_bar().gui_input.connect(_scrollbar_input)


func _allowed() -> bool:
	return is_visible_in_tree() and (not interaction_allowed.is_valid() or interaction_allowed.call())


func _input(event: InputEvent) -> void:
	if not _allowed():
		_cancel_pointer()
		return
	if event is InputEventScreenTouch:
		var point: Vector2 = _local_point((event as InputEventScreenTouch).position)
		if (event as InputEventScreenTouch).pressed and _contains(point) and (_touch_index == -1 or _touch_index == (event as InputEventScreenTouch).index):
			# A fresh press can recover a release lost outside the game window.
			_touch_index = (event as InputEventScreenTouch).index
			_begin_pointer(point)
			get_viewport().set_input_as_handled()
		elif not (event as InputEventScreenTouch).pressed and (event as InputEventScreenTouch).index == _touch_index:
			if (event as InputEventScreenTouch).canceled:
				_cancel_pointer()
			else:
				_end_pointer(point)
			_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		_move_pointer(_local_point((event as InputEventScreenDrag).position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var point: Vector2 = _local_point((event as InputEventMouseButton).position)
		# Godot emits mouse events for touch BEFORE the touch event itself.
		# Letting those reach gui_input starts a second, native drag controller,
		# especially when a gesture begins between rows or after short results.
		# Handle emulated/forwarded mouse input here too, rather than dropping it.
		if (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _contains(point, true):
			if (event as InputEventMouseButton).pressed:
				_begin_motion()
				_snapping = false
				velocity += (1.0 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * 1050.0 * (event as InputEventMouseButton).factor
			get_viewport().set_input_as_handled()
		elif (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _touch_index != -1:
				get_viewport().set_input_as_handled()
				return
			if not (event as InputEventMouseButton).pressed:
				_scrollbar_pressed = false
			if (event as InputEventMouseButton).pressed and _contains(point):
				_begin_pointer(point)
				get_viewport().set_input_as_handled()
			elif not (event as InputEventMouseButton).pressed and _pressed and _touch_index == -1:
				_end_pointer(point)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressed:
		if _touch_index != -1:
			# The corresponding ScreenDrag is the one that moves a captured touch.
			get_viewport().set_input_as_handled()
			return
		if (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_pointer(_local_point((event as InputEventMouseMotion).position))
		else:
			_cancel_pointer()
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture and _contains(_local_point((event as InputEventPanGesture).position), true):
		_begin_motion()
		_snapping = false
		_set_offset(StrictData.number(_offset + (event as InputEventPanGesture).delta.y * 50.0))
		velocity = (event as InputEventPanGesture).delta.y * 140.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _allowed() or _pressed or _scrollbar_pressed or not _moving:
		return
	if _bar_idle > 0.0:
		_bar_idle -= delta
		if _bar_idle > 0.0:
			return
	if _snapping:
		_set_offset(lerpf(_offset, _target, 1.0 - exp(-20.0 * delta)))
		if absf(_target - _offset) < 0.35:
			_set_offset(_target)
			_snapping = false
			_moving = false
			settled.emit(_index())
	else:
		var decay: float = exp(-7.0 * delta)
		var previous: float = _offset
		_set_offset(_offset + velocity * (1.0 - decay) / 7.0)
		velocity *= decay
		if is_equal_approx(previous, _offset):
			velocity = 0.0
		if absf(velocity) < 28.0:
			_target = _offset_for_index(_index())
			_snapping = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_pointer()


func _cancel_pointer() -> void:
	_pressed = false
	_dragging = false
	_touch_index = -1
	_scrollbar_pressed = false
	velocity = 0.0
	_snapping = false


func focus_index(index: int, immediate: bool = false) -> void:
	velocity = 0.0
	_bar_idle = 0.0
	# Edge rows share clamped scroll positions, so retain an explicit tap/focus.
	_focus_override = clampi(index, 0, maxi(0, row_count - 1))
	_target = _offset_for_index(_focus_override)
	_begin_motion(true)
	if immediate:
		_set_offset(_target)
		_moving = false
		_snapping = false
		settled.emit(_index())
	else:
		_snapping = true


func reset_motion() -> void:
	velocity = 0.0
	_moving = false
	_snapping = false
	_pressed = false
	_touch_index = -1
	_scrollbar_pressed = false
	_bar_idle = 0.0
	_focus_override = -1


func _begin_pointer(point: Vector2) -> void:
	_pressed = true
	_dragging = false
	_press_point = point
	_last_point = point
	_last_motion_time = Time.get_ticks_msec() / 1000.0
	velocity = 0.0
	_bar_idle = 0.0
	_snapping = false
	_offset = get_v_scroll_bar().value


func _move_pointer(point: Vector2) -> void:
	if not _pressed:
		return
	if not _dragging and point.distance_to(_press_point) < 10.0:
		return
	if not _dragging:
		_dragging = true
		_begin_motion()
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = clampf(now - _last_motion_time, 0.004, 0.08)
	var movement: float = point.y - _last_point.y
	_set_offset(_offset - movement)
	var outward_at_top: bool = _offset <= 0.0 and movement > 0.0
	var outward_at_bottom: bool = _offset >= _maximum() and movement < 0.0
	if outward_at_top or outward_at_bottom:
		# Pulling against an edge must not build up hidden outward momentum.
		velocity = 0.0
	else:
		if absf(movement) > 0.5 and signf(velocity) != signf(-movement):
			# A reversed finger/mouse direction takes over immediately.
			velocity = 0.0
		velocity = lerpf(velocity, clampf(-movement / elapsed, -4200.0, 4200.0), 0.65)
	_last_point = point
	_last_motion_time = now


func _end_pointer(point: Vector2) -> void:
	_pressed = false
	if not _dragging:
		var index: int = clampi(roundi((_offset + point.y - row_height * 0.5) / row_step), 0, maxi(0, row_count - 1))
		focus_index(index)
	elif Time.get_ticks_msec() / 1000.0 - _last_motion_time > 0.12:
		velocity = 0.0
	_dragging = false


func _begin_motion(preserve_focus: bool = false) -> void:
	if not preserve_focus:
		_focus_override = -1
	if not _moving:
		_moving = true
		movement_started.emit()


func _set_offset(value: float) -> void:
	_offset = clampf(value, 0.0, _maximum())
	_writing_bar = true
	get_v_scroll_bar().value = _offset
	_writing_bar = false
	var index: int = _index()
	if index != _last_index:
		_last_index = index
		focused_index_changed.emit(index)


func _bar_changed(value: float) -> void:
	if _writing_bar:
		return
	_offset = value
	velocity = 0.0
	_begin_motion()
	_snapping = false
	_bar_idle = 0.12
	var index: int = _index()
	if index != _last_index:
		_last_index = index
		focused_index_changed.emit(index)


func _scrollbar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_scrollbar_pressed = (event as InputEventMouseButton).pressed
		if (event as InputEventMouseButton).pressed:
			velocity = 0.0
			_snapping = false
			_begin_motion()


func _index() -> int:
	if _focus_override >= 0:
		return _focus_override
	if _offset <= 0.5:
		return 0
	if _maximum() - _offset <= 0.5:
		return maxi(0, row_count - 1)
	return clampi(roundi((_offset + (size.y - row_height) * 0.5) / row_step), 0, maxi(0, row_count - 1))


func _offset_for_index(index: int) -> float:
	return clampf(StrictData.number(index) * row_step - (size.y - row_height) * 0.5, 0.0, _maximum())


func _maximum() -> float:
	return maxf(0.0, get_v_scroll_bar().max_value - get_v_scroll_bar().page)


func _local_point(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _contains(point: Vector2, include_scrollbar: bool = false) -> bool:
	# Leave the native scrollbar usable, including its draggable thumb.
	var margin: float = 0.0 if include_scrollbar else 16.0
	return Rect2(Vector2.ZERO, size - Vector2(margin, 0)).has_point(point)
