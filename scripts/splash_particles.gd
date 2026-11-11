class_name SplashParticles
extends Control
## Lightweight additive particles, with the photograph's faces kept clear.

@export_range(0, 160) var sparkle_count: int = 72
@export_range(0.0, 1.0) var intensity: float = 0.8
@export_range(0.5, 3.0, 0.05) var size_multiplier: float = 1.6

@onready var artwork: TextureRect = get_node("../Artwork")

var _time: float = 0.0
var _particles: Array[Dictionary] = []
var _burst_age: float = 2.0
var _burst_origin: Vector2
var _glow: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.9), Color(0.8, 0.85, 1, 0.42),
		Color(0.6, 0.65, 1, 0.09), Color(0.6, 0.65, 1, 0)
	])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 64
	_glow.height = 64
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.randomize()
	for index: int in sparkle_count:
		_particles.append({
			"origin": Vector2(random.randf(), random.randf()),
			"speed": random.randf_range(0.006, 0.020),
			"phase": random.randf_range(0.0, TAU),
			"radius": random.randf_range(1.8, 4.0),
			"tint": Color(0.73, 0.83, 1).lerp(Color(0.94, 0.73, 1), random.randf()),
			"star": index % 7 == 0,
			"bokeh": index % 6 == 0,
		})


func _process(delta: float) -> void:
	_time += delta
	_burst_age += delta
	queue_redraw()


func burst(origin: Vector2) -> void:
	_burst_origin = origin
	_burst_age = 0.0


func _draw() -> void:
	if not is_instance_valid(artwork) or _glow == null:
		return
	var unit: float = minf(size.x / 1920.0, size.y / 1080.0)
	for particle: Dictionary in _particles:
		var phase: float = particle.phase
		var origin: Vector2 = particle.origin
		var position_uv: Vector2 = Vector2(
			fposmod(origin.x + sin(_time * 0.22 + phase) * 0.018, 1.0),
			fposmod(StrictData.number(origin.y - _time * particle.speed), 1.0)
		)
		var point: Vector2 = position_uv * size
		var life_fade: float = smoothstep(0.0, 0.09, position_uv.y) * (1.0 - smoothstep(0.91, 1.0, position_uv.y))
		var twinkle: float = pow(0.5 + 0.5 * sin(_time * 1.5 + phase), 2.0)
		var alpha: float = (0.18 + twinkle * 0.55) * life_fade * _subject_visibility(point) * intensity
		var tint: Color = particle.tint
		var radius: float = particle.radius * unit
		if particle.bokeh:
			_draw_glow(point, radius * 8.0, Color(tint, alpha * 0.17))
		else:
			_draw_glow(point, radius * 3.8, Color(tint, alpha * 0.65))
			draw_circle(point, radius * 0.4 * size_multiplier, Color(tint, alpha))
			if particle.star:
				_draw_star(point, radius * (1.8 + twinkle), Color(tint, alpha * twinkle))
	# An occasional quiet meteor near the upper corners, away from the title.
	var comet_age: float = fposmod(_time + 2.0, 11.0)
	if comet_age < 1.5:
		var progress: float = comet_age / 1.5
		var head: Vector2 = Vector2(0.02 + progress * 0.22, 0.02 + progress * 0.16) * size
		var strength: float = sin(progress * PI) * intensity * 0.55
		var direction: Vector2 = Vector2(0.22 * size.x, 0.16 * size.y).normalized()
		for segment: int in 12:
			var point: Vector2 = head - direction * StrictData.number(segment) * 6.0 * unit
			_draw_glow(point, (5.0 - segment * 0.25) * unit,
				Color(0.72, 0.82, 1, strength * (1.0 - segment / 12.0) * _subject_visibility(point)))
		_draw_star(head, 7.0 * unit, Color(0.8, 0.9, 1, strength))
	if _burst_age < 0.8:
		for index: int in 18:
			var angle: float = TAU * index / 18.0
			var travel: float = (16.0 + 140.0 * ease(_burst_age / 0.8, 0.5)) * unit
			var point: Vector2 = _burst_origin + Vector2.from_angle(angle) * travel * Vector2(1.0, 0.55)
			var alpha: float = (1.0 - _burst_age / 0.8) * intensity
			_draw_glow(point, 10.0 * unit, Color(0.8, 0.75, 1, alpha * 0.6))
			_draw_star(point, 4.0 * unit, Color(0.85, 0.9, 1, alpha))


func _subject_visibility(point: Vector2) -> float:
	# Map through the TextureRect's centered cover crop at every aspect ratio.
	var texture_size: Vector2 = artwork.texture.get_size()
	var scale_factor: float = maxf(artwork.size.x / texture_size.x, artwork.size.y / texture_size.y)
	var image_size: Vector2 = texture_size * scale_factor
	var image_origin: Vector2 = artwork.position + (artwork.size - image_size) * 0.5
	var uv: Vector2 = (point - image_origin) / image_size
	var faces: float = _rectangle_mask(uv, Vector2(0.255, 0.49), Vector2(0.735, 0.84))
	var title: float = _rectangle_mask(uv, Vector2(0.30, 0.045), Vector2(0.71, 0.38))
	var prompt: float = _rectangle_mask(uv, Vector2(0.40, 0.88), Vector2(0.61, 0.93))
	return (1.0 - faces * 0.97) * (1.0 - title * 0.8) * (1.0 - prompt * 0.9)


func _rectangle_mask(uv: Vector2, minimum: Vector2, maximum: Vector2) -> float:
	return smoothstep(minimum.x - 0.025, minimum.x, uv.x) \
		* (1.0 - smoothstep(maximum.x, maximum.x + 0.025, uv.x)) \
		* smoothstep(minimum.y - 0.025, minimum.y, uv.y) \
		* (1.0 - smoothstep(maximum.y, maximum.y + 0.025, uv.y))


func _draw_glow(point: Vector2, radius: float, tint: Color) -> void:
	radius *= size_multiplier
	draw_texture_rect(_glow, Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, tint)


func _draw_star(point: Vector2, radius: float, tint: Color) -> void:
	radius *= size_multiplier
	var width: float = maxf(1.0, size_multiplier * 0.8)
	draw_line(point - Vector2(radius, 0), point + Vector2(radius, 0), tint, width, true)
	draw_line(point - Vector2(0, radius * 1.35), point + Vector2(0, radius * 1.35), tint, width, true)
