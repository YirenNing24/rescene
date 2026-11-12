class_name RhythmHighway
extends Control
## Perspective highway and note ribbons, rendered natively in the 2D canvas.

const TOP_Y: float = 175.0
const HIT_Y: float = 895.0
const TOP_WIDTH: float = 290.0
const HIT_WIDTH: float = 1580.0
const CENTER_X: float = 1200.0
const CATCHER_RADIUS: float = 104.0
const CATCHER_FLATTEN: float = 0.33
const CATCHER_INNER_RADIUS: float = 86.0
const NOTE_PALETTE: Array[Color] = [
	Color("a99acb"), # lavender
	Color("929fc9"), # periwinkle
	Color("86a9be"), # mist blue
	Color("87b4af"), # sea glass
	Color("bd9fb6"), # dusty rose
	Color("b293bd"), # orchid
	Color("b3adc7"), # silver lilac
]
const RIBBON_PALETTE: Array[Color] = [
	Color("b58aef"), Color("d799cc"), Color("aea0ee"),
	Color("8fc5e7"), Color("99a6ed"),
]
const RIBBON_COLUMNS: int = 5

var game: RhythmStage
var combo_effects: RhythmComboEffects
var sustain_effects: RhythmSustainEffects
var effects: Array[Dictionary] = []
var _note_colors: Dictionary[int, Color] = {}
var _color_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _press_times: Array[float] = [-10.0, -10.0, -10.0, -10.0, -10.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rng.randomize()
	_fx_rng.randomize()
	reset_note_colors()
	combo_effects = RhythmComboEffects.new()
	combo_effects.highway = self
	add_child(combo_effects)
	for catchers: bool in [true, false]:
		var layer: RhythmDiscLayer = RhythmDiscLayer.new()
		layer.highway = self
		layer.catchers = catchers
		add_child(layer)
	sustain_effects = RhythmSustainEffects.new()
	sustain_effects.highway = self
	add_child(sustain_effects)
	var fireworks: RhythmHitEffects = RhythmHitEffects.new()
	fireworks.highway = self
	add_child(fireworks)


func reset_presses() -> void:
	_press_times.fill(-10.0)


func press(lane: float) -> void:
	_press_times[clampi(roundi(lane), 0, 4)] = game.visual_age


func catcher_strength(lane: int) -> float:
	for pointer: Dictionary in game.judge.pointers.values():
		if absf(StrictData.number(pointer.lane) - lane) <= RhythmJudge.TRACE_TOLERANCE:
			_press_times[lane] = game.visual_age
			return 1.0
	return pow(clampf(1.0 - (game.visual_age - _press_times[lane]) / 0.24, 0.0, 1.0), 2.0)


func reset_note_colors() -> void:
	_note_colors.clear()
	if game != null and game.judge != null:
		for note: Dictionary in game.judge.notes:
			var _color_1: Color = note_color(note)


func note_color(note: Dictionary) -> Color:
	var id: int = note.id
	if not _note_colors.has(id):
		_note_colors[id] = NOTE_PALETTE[_color_rng.randi_range(0, NOTE_PALETTE.size() - 1)]
	return _note_colors[id]


func _process(_delta: float) -> void:
	if game == null:
		return
	while not effects.is_empty() and game.visual_age - effects[0].born > RhythmHitEffects.BURST_LIFE:
		effects.pop_front()
	queue_redraw()


func hit(_label: String, lane: float, value: float, note_id: int = -1) -> void:
	if value <= 0.0:
		return
	press(lane)
	var tint: Color = NOTE_PALETTE[0]
	var sustain: bool = false
	if note_id >= 0 and note_id < StrictData.array(game.judge.notes).size():
		var note: Dictionary = game.judge.notes[note_id]
		tint = note_color(note)
		sustain = note.state == 1 and note.next_tick < StrictData.array(note.checkpoints).size() - 1
	var particles: Array[Dictionary] = []
	var count: int = 12 if sustain else (48 if value >= 0.8 else 32)
	if game.mobile_rendering: count = 6 if sustain else (24 if value >= 0.8 else 16)
	for index: int in count:
		var angle: float = -PI + PI * (StrictData.number(index) + _fx_rng.randf_range(0.05, 0.95)) / count
		if index % 5 == 0:
			angle = _fx_rng.randf_range(0.0, TAU)
		var speed: float = _fx_rng.randf_range(210.0, 620.0) * (0.5 if sustain else 1.0)
		var velocity: Vector2 = Vector2(cos(angle), sin(angle) * 1.05) * speed
		if velocity.y > 0.0: velocity.y *= 0.3
		particles.append({"velocity": velocity, "drag": _fx_rng.randf_range(1.1, 2.4),
			"gravity": _fx_rng.randf_range(210.0, 340.0), "life": _fx_rng.randf_range(0.5, 1.1),
			"delay": _fx_rng.randf_range(0.0, 0.045), "size": _fx_rng.randf_range(1.8, 3.8),
			"star": index % 6 == 0, "tint": tint.lerp(Color("f6eaff"), _fx_rng.randf_range(0.05, 0.45)),
			"phase": _fx_rng.randf_range(0.0, TAU)})
	var limit: int = 8 if game.mobile_rendering else RhythmHitEffects.MAX_BURSTS
	if effects.size() >= limit:
		effects.pop_front()
	effects.append({"lane": lane, "born": game.visual_age, "color": tint,
		"power": 0.38 if sustain else 1.0, "particles": particles})


func project(lane: float, until: float) -> Vector2:
	var approach: float = game.approach_seconds
	var progress: float = clampf(1.0 - until / approach, 0.0, 1.08)
	var depth: float = pow(progress, 2.0)
	var width: float = lerpf(TOP_WIDTH, HIT_WIDTH, depth)
	return Vector2(CENTER_X + ((lane + 0.5) / 5.0 - 0.5) * width, lerpf(TOP_Y, HIT_Y, depth))


func screen_lane(point: Vector2) -> float:
	return (point.x - CENTER_X) / HIT_WIDTH * 5.0 + 2.0


func _draw() -> void:
	if game == null or game.judge == null:
		return
	_draw_road()
	var now: float = game.song_time
	var notes: Array[Dictionary] = game.judge.notes
	for index: int in range(notes.size() - 1, -1, -1):
		var note: Dictionary = notes[index]
		if note.state >= 2 or note.time > now + game.approach_seconds:
			continue
		var end: float = note.time + note.duration
		if end < now - 0.2:
			continue
		var color: Color = note_color(note)
		if note.kind != "tap":
			_draw_ribbon(note, color, now)


func _draw_road() -> void:
	var excitement: float = game.momentum_visual / 3.0
	var accent: Color = RhythmMomentum.color(game.momentum_visual)
	var shimmer: float = 0.92 + 0.08 * sin(game.visual_age * 4.0)
	var bottom_y: float = HIT_Y + 120.0
	var bottom_width: float = HIT_WIDTH + 230.0
	var surface: PackedVector2Array = PackedVector2Array([
		Vector2(CENTER_X - TOP_WIDTH * 0.5, TOP_Y), Vector2(CENTER_X + TOP_WIDTH * 0.5, TOP_Y),
		Vector2(CENTER_X + bottom_width * 0.5, bottom_y), Vector2(CENTER_X - bottom_width * 0.5, bottom_y)])
	# Broad feathered side washes tint the environment with no extra screen pass.
	if excitement > 0.001:
		for side: float in [-1.0, 1.0]:
			var top: Vector2 = Vector2(CENTER_X + side * TOP_WIDTH * 0.5, TOP_Y)
			var bottom: Vector2 = Vector2(CENTER_X + side * bottom_width * 0.5, bottom_y)
			draw_polygon(PackedVector2Array([top, bottom, bottom + Vector2(side * 450.0, 0.0), top + Vector2(side * 310.0, 0.0)]),
				PackedColorArray([Color(accent, 0.0), Color(accent, excitement * 0.28 * shimmer), Color(accent, 0.0), Color(accent, 0.0)]))
	draw_colored_polygon(surface, Color(0.025, 0.03, 0.085, 0.88).lerp(Color(accent * 0.16, 0.9), excitement))
	for lane: int in 5:
		var start_x: float = CENTER_X - TOP_WIDTH * 0.5 + TOP_WIDTH / 5.0 * lane
		var end_x: float = CENTER_X - bottom_width * 0.5 + bottom_width / 5.0 * lane
		var polygon: PackedVector2Array = PackedVector2Array([Vector2(start_x, TOP_Y), Vector2(start_x + TOP_WIDTH / 5.0, TOP_Y),
			Vector2(end_x + bottom_width / 5.0, bottom_y), Vector2(end_x, bottom_y)])
		if lane % 2 == 0:
			draw_colored_polygon(polygon, Color(0.5, 0.42, 0.85, 0.055))
	for line: int in 6:
		var start: Vector2 = Vector2(CENTER_X + (StrictData.number(line) / 5.0 - 0.5) * TOP_WIDTH, TOP_Y)
		var finish: Vector2 = Vector2(CENTER_X + (StrictData.number(line) / 5.0 - 0.5) * bottom_width, bottom_y)
		if line == 0 or line == 5:
			draw_line(start, finish, Color(accent, 0.12 + excitement * 0.12 * shimmer), 24.0 + excitement * 10.0, true)
			draw_line(start, finish, Color(Color("bfa8ff").lerp(accent, excitement), 0.5 + excitement * 0.25), 9.0, true)
			draw_line(start, finish, Color("ebe8ff").lerp(accent.lightened(0.45), excitement), 2.5, true)
		else:
			draw_line(start, finish, Color(accent, 0.12 + excitement * 0.08), 1.3, true)
	var beat: float = game.chart.get("quarter", 0.5)
	var first: int = floori(game.song_time / beat)
	for index: int in range(first, first + 12):
		var remaining: float = index * beat - game.song_time
		if remaining < 0.0 or remaining > game.approach_seconds:
			continue
		var a: Vector2 = project(-0.5, remaining)
		var b: Vector2 = project(4.5, remaining)
		draw_line(a, b, Color(0.75, 0.72, 1, 0.09), 1.0, true)
	# The road-plane hit band shares the catchers' full vertical footprint.
	var band_top: float = HIT_Y - CATCHER_RADIUS * CATCHER_FLATTEN
	var band_bottom: float = HIT_Y + CATCHER_RADIUS * CATCHER_FLATTEN
	var top_half: float = lerpf(TOP_WIDTH, bottom_width, (band_top - TOP_Y) / (bottom_y - TOP_Y)) * 0.5 - 14.0
	var bottom_half: float = lerpf(TOP_WIDTH, bottom_width, (band_bottom - TOP_Y) / (bottom_y - TOP_Y)) * 0.5 - 14.0
	var band: PackedVector2Array = PackedVector2Array([
		Vector2(CENTER_X - top_half, band_top), Vector2(CENTER_X + top_half, band_top),
		Vector2(CENTER_X + bottom_half, band_bottom), Vector2(CENTER_X - bottom_half, band_bottom)])
	draw_polygon(band, PackedColorArray([
		Color(0.65, 0.48, 0.92, 0.09), Color(0.65, 0.48, 0.92, 0.09),
		Color(0.43, 0.27, 0.75, 0.2), Color(0.43, 0.27, 0.75, 0.2)]))
	draw_line(band[0], band[1], Color(0.8, 0.7, 1, 0.3), 1.5, true)
	draw_line(band[3], band[2], Color(0.76, 0.6, 1, 0.1), 8.0, true)
	draw_line(band[3], band[2], Color(0.8, 0.7, 1, 0.5), 2.0, true)


func _draw_ribbon(note: Dictionary, tint: Color, now: float) -> void:
	var strip: Dictionary = _ribbon_strip(note, tint, now)
	if strip.is_empty():
		return
	# Known adjacent triangles avoid polygon ear-clipping at tight turns and
	# near-zero-length tails. No whole-ribbon polygon needs triangulation.
	var indices: PackedInt32Array = strip.indices
	var points: PackedVector2Array = strip.points
	var colors: PackedColorArray = strip.colors
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
	var spine: PackedVector2Array = strip.spine
	var spine_colors: PackedColorArray = strip.spine_colors
	draw_polyline(spine, Color(_ribbon_tint(note, now, tint), 0.10), 14.0, true)
	draw_polyline_colors(spine, spine_colors, 2.5, true)
	if note.kind == "slide":
		for control: Dictionary in note.curve:
			var t: float = note.time + StrictData.number(control.at) * note.duration
			if t >= strip.begin and t <= strip.finish:
				var p: Vector2 = project(StrictData.number(control.lane), t - now)
				draw_circle(p, 5.0 + (p.y - TOP_Y) / 100.0, Color(_ribbon_tint(note, t, tint), 0.8), true, -1, true)


func _ribbon_tint(note: Dictionary, time: float, fallback: Color, across: float = 0.0) -> Color:
	if note.kind != "slide": return fallback
	var along: float = clampf((time - StrictData.number(note.time)) / maxf(0.001, StrictData.number(note.duration)), 0.0, 1.0)
	var phase: float = fposmod(game.visual_age * 0.24 + along * 0.5 + StrictData.number(note.id) * 0.11 + across, 1.0) * RIBBON_PALETTE.size()
	var index: int = floori(phase)
	var blend: float = smoothstep(0.0, 1.0, phase - float(index))
	return RIBBON_PALETTE[index].lerp(RIBBON_PALETTE[(index + 1) % RIBBON_PALETTE.size()], blend).lerp(fallback, 0.12)


func _ribbon_strip(note: Dictionary, tint: Color, now: float) -> Dictionary:
	var begin: float = maxf(StrictData.number(note.time), now) if note.state == 1 else note.time
	var finish: float = minf(StrictData.number(note.time + note.duration), now + game.approach_seconds)
	if finish - begin <= 0.00001:
		return {}
	var points: PackedVector2Array = PackedVector2Array()
	var spine: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var spine_colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var segments: int = 36
	for index: int in segments + 1:
		var t: float = lerpf(begin, finish, StrictData.number(index) / segments)
		var lane: float = RhythmChart.lane_at(note, t)
		var point: Vector2 = project(lane, t - now)
		if not spine.is_empty() and point.distance_squared_to(spine[-1]) < 0.0001:
			continue
		var progress: float = clampf((point.y - TOP_Y) / (HIT_Y - TOP_Y), 0.0, 1.0)
		var curved: bool = note.kind == "slide"
		var half_width: float = lerpf(18.0, 96.0, progress) if curved else lerpf(9.0, 45.0, progress)
		var feather: float = 2.5
		var row_offsets: PackedFloat32Array = PackedFloat32Array([-half_width - feather, -half_width, 0.0, half_width, half_width + feather])
		for offset: float in row_offsets:
			var _point_added: bool = points.append(point + Vector2(offset, 0.0))
		var _bool_4: bool = spine.append(point)
		var center: Color = _ribbon_tint(note, t, tint)
		var pulse: float = 0.88 + 0.12 * sin(game.visual_age * TAU * 1.6 - (t - StrictData.number(note.time)) * 3.0) if curved else 1.0
		var opacity: float = lerpf(0.18, 0.80 if note.state == 1 else 0.66, progress) * pulse if curved else lerpf(0.07, 0.5 if note.state == 1 else 0.3, progress)
		var left: Color = _ribbon_tint(note, t, tint, -0.08)
		var right: Color = _ribbon_tint(note, t, tint, 0.08)
		colors.append_array(PackedColorArray([Color(left, 0.0), Color(left, opacity * 0.86),
			Color(center, opacity), Color(right, opacity * 0.86), Color(right, 0.0)]))
		var _spine_color_added: bool = spine_colors.append(Color(center.lerp(Color("eee9ff"), 0.3), 0.70 * pulse))
	if spine.size() < 2:
		return {}
	for index: int in spine.size() - 1:
		for column: int in RIBBON_COLUMNS - 1:
			var vertex: int = index * RIBBON_COLUMNS + column
			var next: int = vertex + RIBBON_COLUMNS
			if absf((points[vertex + 1] - points[vertex]).cross(points[next] - points[vertex])) < 0.0001:
				continue
			indices.append_array(PackedInt32Array([vertex, vertex + 1, next, vertex + 1, next + 1, next]))
	if indices.is_empty():
		return {}
	return {"points": points, "colors": colors, "indices": indices, "spine": spine, "spine_colors": spine_colors, "begin": begin, "finish": finish}
