class_name MarketGridScroll
extends KineticSongScroll
## Reuse the song browser's single gesture owner, with per-cell tap picking.

signal item_tapped(index: int)

var columns: int = 4
var column_step: float = 0.0
var tile_width: float = 0.0
var item_count: int = 0

func _end_pointer(point: Vector2) -> void:
	var tap: bool = not _dragging and point.distance_to(_press_point) < 10.0 and _contains(point)
	var content: Vector2 = point + Vector2(0.0, _offset)
	super._end_pointer(point)
	if not tap or column_step <= 0.0: return
	var column: int = floori(content.x / column_step)
	var row: int = floori(content.y / row_step)
	if column < 0 or column >= columns or fposmod(content.x, column_step) > tile_width or fposmod(content.y, row_step) > row_height: return
	var index: int = row * columns + column
	if index >= 0 and index < item_count: item_tapped.emit(index)
