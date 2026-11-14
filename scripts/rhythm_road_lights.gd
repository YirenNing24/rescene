class_name RhythmRoadLights
extends Node2D
## Bounded, batched arcade light walls. No screen shader, particles or new viewport.

const ROWS: int = 12
const COLUMNS: int = 4
const RAIL_COLORS: Array[Color] = [Color("64efd6"), Color("72deff"), Color("be8cff"), Color("ffd275")]
const WALL_COLORS: Array[Color] = [Color("ac8bff"), Color("a0a1ff"), Color("ff8dbf"), Color("ff91ae")]
var highway: RhythmHighway
var _vertices: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _weights: PackedFloat32Array = PackedFloat32Array()
var _colors: PackedColorArray = PackedColorArray()
var _last_age: float = -1.0
var _surge_born: float = -10.0

static func rail_color(level: float) -> Color:
	var tier: float = clampf(level, 0.0, 3.0)
	var index: int = mini(2, floori(tier))
	return RAIL_COLORS[index].lerp(RAIL_COLORS[index + 1], tier - index)

static func wall_color(level: float) -> Color:
	var tier: float = clampf(level, 0.0, 3.0)
	var index: int = mini(2, floori(tier))
	return WALL_COLORS[index].lerp(WALL_COLORS[index + 1], tier - index)

func _ready() -> void:
	name = "ArcadeRoadLights"
	show_behind_parent = true
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	for side: float in [-1.0, 1.0]:
		var base: int = _vertices.size()
		for row: int in ROWS + 1:
			var depth: float = float(row) / ROWS
			for column: int in COLUMNS:
				var across: float = float(column) / (COLUMNS - 1)
				var _vertex: bool = _vertices.append(_point(side, depth, across))
				var edge: float = sin(across * PI)
				var fade: float = smoothstep(0.0, 0.12, depth) * (1.0 - smoothstep(0.82, 1.0, depth))
				var _weight: bool = _weights.append(edge * fade)
		for row: int in ROWS:
			for column: int in COLUMNS - 1:
				var a: int = base + row * COLUMNS + column
				_indices.append_array(PackedInt32Array([a, a + 1, a + COLUMNS, a + 1, a + COLUMNS + 1, a + COLUMNS]))
	var _resized: int = _colors.resize(_vertices.size())

func milestone() -> void:
	_surge_born = highway.game.visual_age

func reset() -> void:
	_surge_born = -10.0
	_last_age = -1.0
	queue_redraw()

func _process(_delta: float) -> void:
	if highway == null or highway.game == null: return
	if _last_age == highway.game.visual_age: return
	_last_age = highway.game.visual_age
	queue_redraw()

func _point(side: float, depth: float, across: float) -> Vector2:
	var y: float = lerpf(RhythmHighway.TOP_Y, RhythmHighway.HIT_Y + 120.0, depth)
	var inside: float = RhythmHighway.road_width_at_y(y) * 0.5 + 18.0
	var width: float = minf(600.0, maxf(0.0, 1165.0 - inside))
	return Vector2(RhythmHighway.CENTER_X + side * (inside + across * width), y)

func _draw() -> void:
	if highway == null or highway.game == null or _vertices.is_empty(): return
	var game: RhythmStage = highway.game
	var level: float = game.momentum_visual
	var primary: Color = rail_color(level)
	var secondary: Color = wall_color(level)
	var time: float = game.visual_age
	var beat: float = maxf(0.15, StrictData.number(game.chart.get("quarter", 0.5)))
	var beat_glow: float = pow(1.0 - fposmod(maxf(0.0, game.song_time), beat) / beat, 3.0)
	var surge: float = pow(clampf(1.0 - (time - _surge_born) / 0.58, 0.0, 1.0), 2.0)
	var energy: float = 0.72 + level * 0.13 + beat_glow * 0.08 + surge * 0.35
	for index: int in _colors.size():
		var across: float = float(index % COLUMNS) / (COLUMNS - 1)
		_colors[index] = Color(primary.lerp(secondary, across), _weights[index] * energy * (0.23 + level * 0.035))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _vertices, _colors)
	var lattice: PackedVector2Array = PackedVector2Array()
	var lattice_colors: PackedColorArray = PackedColorArray()
	var streams: PackedVector2Array = PackedVector2Array()
	var stream_colors: PackedColorArray = PackedColorArray()
	var haze_colors: PackedColorArray = PackedColorArray()
	for side: float in [-1.0, 1.0]:
		# Counterflow diagonal beams form a moving diamond lattice outside the road.
		for direction: float in [-1.0, 1.0]:
			for stripe: int in 7:
				var start: float = float(stripe - 3) * 0.36 + fposmod(time * 0.055, 0.36)
				var slope: float = direction * 1.4
				var begin: float = clampf(minf(-start / slope, (1.0 - start) / slope), 0.0, 1.0)
				var finish: float = clampf(maxf(-start / slope, (1.0 - start) / slope), 0.0, 1.0)
				if finish - begin < 0.001: continue
				for segment: int in 4:
					var a: float = lerpf(begin, finish, float(segment) / 4.0)
					var b: float = lerpf(begin, finish, float(segment + 1) / 4.0)
					var fade: float = sin((a + b) * 0.5 * PI)
					lattice.append_array(PackedVector2Array([_point(side, a, start + slope * a), _point(side, b, start + slope * b)]))
					var _color: bool = lattice_colors.append(Color(primary if direction > 0.0 else secondary, fade * energy * 0.34))
		# Light streaks accelerate toward the player, with a capped count on phones.
		for index: int in (16 if game.mobile_rendering else 22):
			var phase: float = fposmod(time * (0.24 + float(index % 4) * 0.035) + float(index) * 0.618034, 1.0)
			var depth: float = phase * phase
			var tail: float = maxf(0.0, phase - 0.045 - level * 0.006)
			var across: float = 0.08 + fposmod(float(index) * 0.381966, 0.85)
			streams.append_array(PackedVector2Array([_point(side, tail * tail, across), _point(side, depth, across)]))
			var fade: float = smoothstep(0.03, 0.2, phase) * (1.0 - smoothstep(0.84, 1.0, phase))
			var tint: Color = primary.lerp(secondary, across * 0.7).lightened(0.28)
			var _core: bool = stream_colors.append(Color(tint, fade * energy * 0.88))
			var _halo: bool = haze_colors.append(Color(tint, fade * energy * 0.10))
		# Two sweeping ribbons create the broad, curved arcade light-wall silhouette.
		for ribbon: int in 2:
			var points: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()
			for index: int in 25:
				var depth: float = float(index) / 24.0
				var across: float = 0.48 + 0.33 * sin(depth * 7.5 - time * 0.55 + ribbon * PI)
				var _point_added: bool = points.append(_point(side, depth, across))
				var _tint_added: bool = colors.append(Color(primary.lerp(secondary, float(ribbon)), sin(depth * PI) * energy * 0.50))
			draw_polyline_colors(points, colors, 3.3, true)
	if not lattice.is_empty(): draw_multiline_colors(lattice, lattice_colors, 1.4, true)
	if not streams.is_empty():
		draw_multiline_colors(streams, haze_colors, 9.0, true)
		draw_multiline_colors(streams, stream_colors, 2.2, true)
