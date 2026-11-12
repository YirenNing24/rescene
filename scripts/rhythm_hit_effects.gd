class_name RhythmHitEffects
extends Node2D
## Additive firework sparks, ballistic trails and soft impact ripples.

const ANIMATION_SPEED: float = 2.4
const BURST_LIFE: float = 1.2 / ANIMATION_SPEED
const MAX_BURSTS: int = 14
var highway: RhythmHighway
var _glow: GradientTexture2D
var _ripple: GradientTexture2D

func _ready() -> void:
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	_glow = _radial(PackedFloat32Array([0.0, 0.12, 0.38, 0.7, 1.0]),
		PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.23), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0)]))
	_ripple = _radial(PackedFloat32Array([0.0, 0.72, 0.79, 0.84, 0.91, 1.0]),
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0)]))

func _radial(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if highway == null or highway.game == null:
		return
	for effect: Dictionary in highway.effects:
		var elapsed: float = highway.game.visual_age - effect.born
		if elapsed < 0.0 or elapsed >= BURST_LIFE: continue
		var age: float = elapsed * ANIMATION_SPEED
		var origin: Vector2 = highway.project(StrictData.number(effect.lane), 0.0)
		var tint: Color = effect.color
		var power: float = effect.power
		var flash: float = pow(maxf(0.0, 1.0 - age / 0.2), 2.0) * power
		_sprite(_glow, origin, Vector2(260, 95) * highway.ROAD_SCALE, Color(tint, flash * 0.75))
		_sprite(_glow, origin, Vector2(100, 34) * highway.ROAD_SCALE, Color(tint.lerp(Color.WHITE, 0.6), flash * 0.8))
		var ripple_fade: float = pow(maxf(0.0, 1.0 - age / 0.52), 1.5) * power
		var ripple_size: Vector2 = Vector2(185.0 + age * 480.0, 58.0 + age * 145.0) * highway.ROAD_SCALE
		_sprite(_ripple, origin, ripple_size, Color(tint, ripple_fade * 0.65))
		for particle: Dictionary in effect.particles:
			var t: float = age - particle.delay
			var life: float = particle.life
			if t <= 0.0 or t >= life: continue
			var fade: float = pow(1.0 - t / life, 1.3)
			var spark_tint: Color = particle.tint
			var radius: float = particle.size
			var point: Vector2 = origin + _travel(particle, t)
			var trail: PackedVector2Array = PackedVector2Array()
			var trail_colors: PackedColorArray = PackedColorArray()
			for segment: int in 6:
				var fraction: float = StrictData.number(segment) / 5.0
				var sample: float = maxf(0.0, t - 0.13 * (1.0 - fraction))
				var _bool_1: bool = trail.append(origin + _travel(particle, sample))
				var _bool_2: bool = trail_colors.append(Color(spark_tint, fade * fraction * fraction * 0.65))
			if t > 0.015:
				if particle.star:
					draw_polyline(trail, Color(spark_tint, fade * 0.07), radius * 4.0, true)
				draw_polyline_colors(trail, trail_colors, radius * 0.7, true)
			var twinkle: float = 0.75 + 0.25 * sin(t * 24.0 + StrictData.number(particle.phase))
			_sprite(_glow, point, Vector2.ONE * radius * 9.0, Color(spark_tint, fade * 0.27))
			_sprite(_glow, point, Vector2.ONE * radius * 3.3, Color(spark_tint.lerp(Color.WHITE, 0.65), fade * twinkle))
			if particle.star:
				var arm: float = radius * (2.0 + twinkle) * fade
				draw_line(point - Vector2(arm, 0), point + Vector2(arm, 0), Color(spark_tint, fade * 0.7), 1.0, true)
				draw_line(point - Vector2(0, arm), point + Vector2(0, arm), Color(spark_tint, fade * 0.7), 1.0, true)

func _travel(particle: Dictionary, time: float) -> Vector2:
	var drag: float = particle.drag
	return particle.velocity * ((1.0 - exp(-drag * time)) / drag) + Vector2(0,StrictData.number(particle.gravity * time * time * 0.5))

func _sprite(texture: Texture2D, center: Vector2, size: Vector2, tint: Color) -> void:
	if tint.a <= 0.001: return
	draw_texture_rect(texture, Rect2(center - size * 0.5, size), false, tint)
