class_name RhythmSwipeNotes
extends Node2D
## Crisp floating chevrons share the note perspective; no particles or blur pass.
var _arrow: PackedVector2Array = PackedVector2Array([
	Vector2(0, -27), Vector2(27, 0), Vector2(17, 10), Vector2(7, 0),
	Vector2(7, 24), Vector2(-7, 24), Vector2(-7, 0), Vector2(-17, 10), Vector2(-27, 0)])
var _outline: PackedVector2Array = PackedVector2Array([
	Vector2(0, -27), Vector2(27, 0), Vector2(17, 10), Vector2(7, 0),
	Vector2(7, 24), Vector2(-7, 24), Vector2(-7, 0), Vector2(-17, 10), Vector2(-27, 0), Vector2(0, -27)])
var _chevron: PackedVector2Array = PackedVector2Array([Vector2(-13, 40), Vector2(0, 27), Vector2(13, 40)])
var highway: RhythmHighway

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if highway == null or highway.game == null or highway.game.judge == null: return
	var game: RhythmStage = highway.game
	for note: Dictionary in highway.visible_notes():
		if note.kind != "swipe": continue
		var point: Vector2 = highway.project(StrictData.number(note.lane), StrictData.number(note.time) - game.song_time)
		var depth: float = clampf((point.y - highway.TOP_Y) / (highway.HIT_Y - highway.TOP_Y), 0.0, 1.1)
		var scale_factor: float = lerpf(highway.TOP_WIDTH, highway.HIT_WIDTH, depth) / highway.HIT_WIDTH * highway.ROAD_SCALE
		var bob: float = sin(game.visual_age * 8.5 + StrictData.number(note.id) * 0.35) * 7.0
		point.y -= (67.0 + bob) * scale_factor
		draw_set_transform(point, 0.0, Vector2.ONE * scale_factor)
		draw_polyline(_outline, Color(0.4, 1.0, 0.82, 0.14), 15.0, true)
		draw_colored_polygon(_arrow, Color("bbffe6"))
		draw_polyline(_outline, Color("f3fff9"), 2.0, true)
		# A fading second chevron reinforces the upward gesture.
		draw_polyline(_chevron, Color(0.64, 1.0, 0.85, 0.45), 3.0, true)
	draw_set_transform(Vector2.ZERO)
