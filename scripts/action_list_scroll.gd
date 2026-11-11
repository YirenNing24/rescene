class_name ActionListScroll
extends KineticSongScroll
## One gesture owner allows dragging over rows and buttons without activating them.

var actions: Array[Button] = []

func _offset_for_index(_index_value: int) -> float:
	# Free scrolling lists should settle in place, without song-row centering.
	return _offset

func _end_pointer(point: Vector2) -> void:
	var tap: bool = _pressed and not _dragging and point.distance_to(_press_point) < 10.0 and _contains(point)
	super._end_pointer(point)
	if not tap: return
	var canvas_point: Vector2 = get_global_transform_with_canvas() * point
	for button: Button in actions:
		if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree(): continue
		var button_point: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * canvas_point
		if Rect2(Vector2.ZERO, button.size).has_point(button_point):
			button.pressed.emit()
			return
