class_name RhythmHighway
extends Control
## Perspective highway and note ribbons, rendered natively in the 2D canvas.

const TOP_Y: float = 175.0
const HIT_Y: float = 895.0
const ROAD_SCALE: float = 1960.0 / 1580.0
const TOP_WIDTH: float = 290.0 * ROAD_SCALE
const HIT_WIDTH: float = 1960.0
const CENTER_X: float = 1200.0
const CATCHER_RADIUS: float = 104.0 * ROAD_SCALE
const CATCHER_FLATTEN: float = 0.33
const CATCHER_INNER_RADIUS: float = 86.0 * ROAD_SCALE
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
var slide_touches: RhythmSlideTouches
var sustain_effects: RhythmSustainEffects
var effects: Array[Dictionary] = []
var _note_colors: Dictionary[int, Color] = {}
var _color_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fx_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _press_times: Array[float] = [-10.0, -10.0, -10.0, -10.0, -10.0]
var _visible: Array[Dictionary] = []
var _visible_end: int = 0
var _visible_time: float = -INF
var _visible_frame: int = -1
var _visible_generation: int = -1
var _visible_judge: RhythmJudge
var _visible_approach: float = -1.0
var _ribbon_indices: Dictionary[int, PackedInt32Array] = {}
var swipe_notes: RhythmSwipeNotes
var fireworks: RhythmHitEffects
var road_lights: RhythmRoadLights


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rng.randomize()
	_fx_rng.randomize()
	reset_note_colors()
	road_lights = RhythmRoadLights.new()
	road_lights.highway = self
	add_child(road_lights)
	combo_effects = RhythmComboEffects.new()
	combo_effects.highway = self
	add_child(combo_effects)
	for catchers: bool in [true, false]:
		var layer: RhythmDiscLayer = RhythmDiscLayer.new()
		layer.highway = self
		layer.catchers = catchers
		add_child(layer)
	swipe_notes = RhythmSwipeNotes.new()
	swipe_notes.highway = self
	add_child(swipe_notes)
	sustain_effects = RhythmSustainEffects.new()
	sustain_effects.highway = self
	add_child(sustain_effects)
	slide_touches = RhythmSlideTouches.new()
	slide_touches.highway = self
	add_child(slide_touches)
	fireworks = RhythmHitEffects.new()
	fireworks.highway = self
	add_child(fireworks)


func reset_presses() -> void:
	_press_times.fill(-10.0)
	if is_instance_valid(road_lights): road_lights.reset()


func press(lane: float) -> void:
	_press_times[clampi(roundi(lane), 0, 4)] = game.visual_age


func catcher_strength(lane: int) -> float:
	for pointer_id: int in game.judge.pointers:
		var pointer: Dictionary = game.judge.pointers[pointer_id]
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
	if note.kind == "swipe": return Color("a2f5d8")
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
	fireworks.emit_burst(lane, tint, sustain, value)


func project(lane: float, until: float) -> Vector2:
	var approach: float = game.approach_seconds
	var progress: float = clampf(1.0 - until / approach, 0.0, 1.08)
	var depth: float = progress * progress
	var width: float = lerpf(TOP_WIDTH, HIT_WIDTH, depth)
	return Vector2(CENTER_X + ((lane + 0.5) / 5.0 - 0.5) * width, lerpf(TOP_Y, HIT_Y, depth))


func screen_lane(point: Vector2) -> float:
	return (point.x - CENTER_X) / HIT_WIDTH * 5.0 + 2.0


static func road_width_at_y(y: float) -> float:
	return TOP_WIDTH + (HIT_WIDTH - TOP_WIDTH) * (y - TOP_Y) / (HIT_Y - TOP_Y)


func contains_hit_point(point: Vector2) -> bool:
	return point.y >= 690.0 and point.y <= 1060.0 and absf(point.x - CENTER_X) <= HIT_WIDTH * 0.5 + 75.0 * ROAD_SCALE


func _draw() -> void:
	if game == null or game.judge == null:
		return
	_draw_road()
	var now: float = game.song_time
	var notes: Array[Dictionary] = visible_notes()
	for index: int in range(notes.size() - 1, -1, -1):
		var note: Dictionary = notes[index]
		var color: Color = note_color(note)
		if note.kind in ["hold", "slide"]:
			_draw_ribbon(note, color, now)


func visible_notes() -> Array[Dictionary]:
	var judge: RhythmJudge = game.judge
	var now: float = game.song_time
	var frame: int = Engine.get_process_frames()
	if _visible_frame == frame and _visible_time == now and _visible_generation == judge.generation and _visible_judge == judge and _visible_approach == game.approach_seconds: return _visible
	if _visible_judge != judge or _visible_generation != judge.generation or now < _visible_time: _visible_end = judge.first_live
	_visible_judge = judge
	_visible_generation = judge.generation
	_visible_time = now
	_visible_frame = frame
	_visible_approach = game.approach_seconds
	_visible_end = maxi(judge.first_live, mini(_visible_end, judge.notes.size()))
	while _visible_end < judge.notes.size() and judge.notes[_visible_end].time <= now + game.approach_seconds: _visible_end += 1
	_visible.clear()
	for index: int in range(judge.first_live, _visible_end):
		var note: Dictionary = judge.notes[index]
		if note.state < 2 and note.time <= now + game.approach_seconds and note.time + note.duration >= now - 0.2: _visible.append(note)
	return _visible


func _draw_road() -> void:
	var excitement: float = game.momentum_visual / 3.0
	var accent: Color = RhythmRoadLights.rail_color(game.momentum_visual)
	var shimmer: float = 0.92 + 0.08 * sin(game.visual_age * 4.0)
	var bottom_y: float = HIT_Y + 120.0
	var bottom_width: float = road_width_at_y(bottom_y)
	var surface: PackedVector2Array = PackedVector2Array([
		Vector2(CENTER_X - TOP_WIDTH * 0.5, TOP_Y), Vector2(CENTER_X + TOP_WIDTH * 0.5, TOP_Y),
		Vector2(CENTER_X + bottom_width * 0.5, bottom_y), Vector2(CENTER_X - bottom_width * 0.5, bottom_y)])
	draw_colored_polygon(surface, Color(0.012, 0.02, 0.05, 0.95).lerp(Color(accent * 0.075, 0.96), excitement))
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
			draw_line(start, finish, Color(accent, 0.16 + excitement * 0.10 * shimmer), 29.0 + excitement * 8.0, true)
			draw_line(start, finish, Color(accent, 0.70 + excitement * 0.16), 10.0, true)
			draw_line(start, finish, accent.lightened(0.65), 2.8, true)
		else:
			draw_line(start, finish, Color(accent, 0.15 + excitement * 0.07), 1.3, true)
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
			Color(accent, 0.07), Color(accent, 0.07), Color(accent, 0.18), Color(accent, 0.18)]))
	draw_line(band[0], band[1], Color(accent.lightened(0.3), 0.35), 1.5, true)
	draw_line(band[3], band[2], Color(accent, 0.1), 8.0, true)
	draw_line(band[3], band[2], Color(accent.lightened(0.3), 0.6), 2.0, true)


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
	draw_polyline(spine, Color(_ribbon_tint(note, now, tint), 0.10), 14.0 * ROAD_SCALE, true)
	draw_polyline_colors(spine, spine_colors, 2.5 * ROAD_SCALE, true)
	if note.kind == "slide":
		for control: Dictionary in note.curve:
			var t: float = note.time + StrictData.number(control.at) * note.duration
			if t >= strip.begin and t <= strip.finish:
				var p: Vector2 = project(StrictData.number(control.lane), t - now)
				draw_circle(p, (5.0 + (p.y - TOP_Y) / 100.0) * ROAD_SCALE, Color(_ribbon_tint(note, t, tint), 0.8), true, -1, true)


func _ribbon_tint(note: Dictionary, time: float, fallback: Color, across: float = 0.0) -> Color:
	if note.kind != "slide": return fallback
	var along: float = clampf((time - StrictData.number(note.time)) / maxf(0.001, StrictData.number(note.duration)), 0.0, 1.0)
	var phase: float = fposmod(game.visual_age * 0.24 + along * 0.5 + StrictData.number(note.id) * 0.11 + across, 1.0) * RIBBON_PALETTE.size()
	var index: int = floori(phase)
	var blend: float = smoothstep(0.0, 1.0, phase - float(index))
	return RIBBON_PALETTE[index].lerp(RIBBON_PALETTE[(index + 1) % RIBBON_PALETTE.size()], blend).lerp(fallback, 0.12)


func _ribbon_strip(note: Dictionary, tint: Color, now: float) -> Dictionary:
	var note_time: float = StrictData.number(note.time)
	var duration: float = StrictData.number(note.duration)
	var begin: float = maxf(note_time, now) if note.state == 1 else note_time
	var finish: float = minf(note_time + duration, now + game.approach_seconds)
	if finish - begin <= 0.00001: return {}
	var segments: int = 24 if game.mobile_rendering else 36
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var spine: PackedVector2Array = PackedVector2Array()
	var spine_colors: PackedColorArray = PackedColorArray()
	var _points_size: int = points.resize((segments + 1) * RIBBON_COLUMNS)
	var _colors_size: int = colors.resize(points.size())
	var _spine_size: int = spine.resize(segments + 1)
	var _spine_colors_size: int = spine_colors.resize(segments + 1)
	var curved: bool = note.kind == "slide"
	var collected: bool = curved and note.state == 1 and is_instance_valid(sustain_effects) and sustain_effects._is_collected(note)
	var color_phase: float = game.visual_age * 0.24 + StrictData.number(note.id) * 0.11
	for row: int in segments + 1:
		var t: float = lerpf(begin, finish, float(row) / segments)
		var point: Vector2 = project(RhythmChart.lane_at(note, t), t - now)
		var progress: float = clampf((point.y - TOP_Y) / (HIT_Y - TOP_Y), 0.0, 1.0)
		var half_width: float = (lerpf(24.0, 128.0, progress) if curved else lerpf(9.0, 45.0, progress)) * ROAD_SCALE
		var feather: float = 2.5 * ROAD_SCALE
		var base: int = row * RIBBON_COLUMNS
		points[base] = point + Vector2(-half_width - feather, 0)
		points[base + 1] = point + Vector2(-half_width, 0)
		points[base + 2] = point
		points[base + 3] = point + Vector2(half_width, 0)
		points[base + 4] = point + Vector2(half_width + feather, 0)
		spine[row] = point
		var phase: float = color_phase + clampf((t - note_time) / maxf(0.001, duration), 0.0, 1.0) * 0.5
		var center: Color = _phase_color(phase, tint) if curved else tint
		var left: Color = _phase_color(phase - 0.08, tint) if curved else tint
		var right: Color = _phase_color(phase + 0.08, tint) if curved else tint
		var pulse: float = 0.88 + 0.12 * sin(game.visual_age * TAU * 1.6 - (t - note_time) * 3.0) if curved else 1.0
		if collected: center = center.lerp(Color("d1ffef"), 0.32); left = left.lightened(0.2); right = right.lightened(0.2)
		var opacity: float = lerpf(0.18, 0.95 if collected else 0.80 if note.state == 1 else 0.66, progress) * pulse if curved else lerpf(0.07, 0.5 if note.state == 1 else 0.3, progress)
		colors[base] = Color(left, 0.0)
		colors[base + 1] = Color(left, opacity * 0.86)
		colors[base + 2] = Color(center, opacity)
		colors[base + 3] = Color(right, opacity * 0.86)
		colors[base + 4] = Color(right, 0.0)
		spine_colors[row] = Color(center.lerp(Color("eee9ff"), 0.3), 0.70 * pulse)
	if spine[0].distance_squared_to(spine[-1]) < 0.0001: return {}
	if not _ribbon_indices.has(segments):
		var indices: PackedInt32Array = PackedInt32Array()
		var _indices_size: int = indices.resize(segments * (RIBBON_COLUMNS - 1) * 6)
		var cursor: int = 0
		for row: int in segments:
			for column: int in RIBBON_COLUMNS - 1:
				var vertex: int = row * RIBBON_COLUMNS + column
				var next: int = vertex + RIBBON_COLUMNS
				indices[cursor] = vertex; indices[cursor + 1] = vertex + 1; indices[cursor + 2] = next
				indices[cursor + 3] = vertex + 1; indices[cursor + 4] = next + 1; indices[cursor + 5] = next
				cursor += 6
		_ribbon_indices[segments] = indices
	return {"points":points,"colors":colors,"indices":_ribbon_indices[segments],"spine":spine,"spine_colors":spine_colors,"begin":begin,"finish":finish}


func _phase_color(phase: float, fallback: Color) -> Color:
	var scaled: float = fposmod(phase, 1.0) * RIBBON_PALETTE.size()
	var index: int = floori(scaled)
	return RIBBON_PALETTE[index].lerp(RIBBON_PALETTE[(index + 1) % RIBBON_PALETTE.size()], smoothstep(0.0, 1.0, scaled - index)).lerp(fallback, 0.12)
