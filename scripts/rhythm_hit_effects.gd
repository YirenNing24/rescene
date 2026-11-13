class_name RhythmHitEffects
extends Node2D
## Pooled sparks, grouped by texture/primitive so chords stay batched on mobile.

const ANIMATION_SPEED: float = 2.4
const BURST_LIFE: float = 1.2 / ANIMATION_SPEED
const MAX_BURSTS: int = 14
var highway: RhythmHighway
var _glow: GradientTexture2D
var _ripple: GradientTexture2D
var _pool: Array[Dictionary] = []
var _cursor: int = 0
var _last_age: float = -1.0

func _ready() -> void:
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	_glow = _radial(PackedFloat32Array([0.0, 0.12, 0.38, 0.7, 1.0]),
		PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.23), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0)]))
	_ripple = _radial(PackedFloat32Array([0.0, 0.72, 0.79, 0.84, 0.91, 1.0]),
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0)]))
	var count: int = 24 if highway.game.mobile_rendering else 48
	for _burst: int in (8 if highway.game.mobile_rendering else MAX_BURSTS):
		var particles: Array[Dictionary] = []
		for index: int in count:
			var angle: float = -PI + PI * (float(index) + highway._fx_rng.randf_range(0.05, 0.95)) / count
			if index % 5 == 0: angle = highway._fx_rng.randf_range(0.0, TAU)
			var velocity: Vector2 = Vector2(cos(angle), sin(angle) * 1.05) * highway._fx_rng.randf_range(210.0, 620.0) * highway.ROAD_SCALE
			if velocity.y > 0.0: velocity.y *= 0.3
			var drag: float = highway._fx_rng.randf_range(1.1, 2.4)
			var trail_factors: PackedFloat32Array = PackedFloat32Array()
			for segment: int in 6:
				var _factor: bool = trail_factors.append(exp(drag * 0.13 * (1.0 - float(segment) / 5.0)))
			particles.append({"velocity":velocity,"drag":drag,"inverse_drag":1.0/drag,"trail_factors":trail_factors,
				"gravity":highway._fx_rng.randf_range(210.0,340.0)*highway.ROAD_SCALE,"life":highway._fx_rng.randf_range(0.5,1.1),
				"delay":highway._fx_rng.randf_range(0.0,0.045),"size":highway._fx_rng.randf_range(1.8,3.8)*highway.ROAD_SCALE,
				"star":index%6==0,"mix":highway._fx_rng.randf_range(0.05,0.45),"phase":highway._fx_rng.randf_range(0.0,TAU)})
		_pool.append({"lane":0.0,"born":-10.0,"color":Color.WHITE,"power":1.0,"velocity_scale":1.0,"count":count,"particles":particles})
	set_process(false)

func emit_burst(lane: float, tint: Color, sustain: bool, value: float = 1.0) -> void:
	if highway.effects.size() >= _pool.size():
		var _oldest: Variant = highway.effects.pop_front()
	var effect: Dictionary = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	effect.lane = lane; effect.color = tint; effect.born = highway.game.visual_age
	effect.power = 0.38 if sustain else 1.0
	effect.velocity_scale = 0.5 if sustain else 1.0
	effect.count = (6 if sustain else (24 if value >= 0.8 else 16)) if highway.game.mobile_rendering else (12 if sustain else (48 if value >= 0.8 else 32))
	highway.effects.append(effect)
	set_process(true)
	queue_redraw()

func _radial(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new(); gradient.offsets = offsets; gradient.colors = colors
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 128; texture.height = 128; texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL; texture.fill_from = Vector2(0.5,0.5); texture.fill_to = Vector2(1.0,0.5)
	return texture

func _process(_delta: float) -> void:
	if highway.effects.is_empty(): queue_redraw(); set_process(false); return
	if _last_age == highway.game.visual_age: return
	_last_age = highway.game.visual_age
	queue_redraw()

func _draw() -> void:
	if highway == null or highway.game == null: return
	var trail_points: PackedVector2Array = PackedVector2Array()
	var trail_colors: PackedColorArray = PackedColorArray()
	var haze_points: PackedVector2Array = PackedVector2Array()
	var haze_colors: PackedColorArray = PackedColorArray()
	var star_points: PackedVector2Array = PackedVector2Array()
	var star_colors: PackedColorArray = PackedColorArray()
	# Keep every glow adjacent. Mixing texture rects with a polyline per particle
	# previously broke the canvas batch hundreds of times on a dense chord.
	for effect: Dictionary in highway.effects:
		var elapsed: float = highway.game.visual_age - effect.born
		if elapsed < 0.0 or elapsed >= BURST_LIFE: continue
		var age: float = elapsed * ANIMATION_SPEED
		var origin: Vector2 = highway.project(StrictData.number(effect.lane),0.0)
		var tint: Color = effect.color
		var flash: float = pow(maxf(0.0,1.0-age/0.2),2.0)*StrictData.number(effect.power)
		_sprite(_glow,origin,Vector2(260,95)*highway.ROAD_SCALE,Color(tint,flash*0.75))
		_sprite(_glow,origin,Vector2(100,34)*highway.ROAD_SCALE,Color(tint.lerp(Color.WHITE,0.6),flash*0.8))
		var particles: Array = StrictData.array(effect.particles)
		var count: int = StrictData.integer(effect.count)
		for index: int in count:
			var particle: Dictionary = particles[floori(float(index)*particles.size()/count)]
			var t: float = age - StrictData.number(particle.delay)
			var life: float = particle.life
			if t <= 0.0 or t >= life: continue
			var fade: float = pow(1.0-t/life,1.3)
			var spark_tint: Color = tint.lerp(Color("f6eaff"),StrictData.number(particle.mix))
			var radius: float = particle.size
			var damping: float = exp(-StrictData.number(particle.drag)*t)
			var velocity: Vector2 = particle.velocity
			velocity *= StrictData.number(effect.velocity_scale)
			var gravity: float = particle.gravity
			var point: Vector2 = origin + velocity * ((1.0-damping)*StrictData.number(particle.inverse_drag)) + Vector2(0,gravity*t*t*0.5)
			if t > 0.015:
				var factors: PackedFloat32Array = particle.trail_factors
				var previous: Vector2
				for segment: int in 6:
					var fraction: float = float(segment)/5.0
					var sample: float = maxf(0.0,t-0.13*(1.0-fraction))
					var tail: Vector2 = origin + velocity*((1.0-minf(1.0,damping*factors[segment]))*StrictData.number(particle.inverse_drag)) + Vector2(0,gravity*sample*sample*0.5)
					if segment > 0:
						var _a: bool = trail_points.append(previous); var _b: bool = trail_points.append(tail)
						# draw_multiline_colors takes one color per two-point segment.
						var midpoint: float = (float(segment) - 0.5) / 5.0
						var _c: bool = trail_colors.append(Color(spark_tint,fade*midpoint*midpoint*0.65))
						if particle.star:
							var _e: bool = haze_points.append(previous); var _f: bool = haze_points.append(tail)
							var _g: bool = haze_colors.append(Color(spark_tint,fade*0.07))
					previous = tail
			var twinkle: float = 0.75+0.25*sin(t*24.0+StrictData.number(particle.phase))
			_sprite(_glow,point,Vector2.ONE*radius*9.0,Color(spark_tint,fade*0.27))
			_sprite(_glow,point,Vector2.ONE*radius*3.3,Color(spark_tint.lerp(Color.WHITE,0.65),fade*twinkle))
			if particle.star:
				var arm: float = radius*(2.0+twinkle)*fade
				for axis: Vector2 in [Vector2.RIGHT,Vector2.DOWN]:
					var _i: bool = star_points.append(point-axis*arm); var _j: bool = star_points.append(point+axis*arm)
					var _k: bool = star_colors.append(Color(spark_tint,fade*0.7))
	for effect: Dictionary in highway.effects:
		var age: float = (highway.game.visual_age-StrictData.number(effect.born))*ANIMATION_SPEED
		if age < 0.0 or age >= 0.52: continue
		var tint: Color = effect.color
		_sprite(_ripple,highway.project(StrictData.number(effect.lane),0.0),Vector2(185.0+age*480.0,58.0+age*145.0)*highway.ROAD_SCALE,Color(tint,pow(maxf(0.0,1.0-age/0.52),1.5)*StrictData.number(effect.power)*0.65))
	if not haze_points.is_empty(): draw_multiline_colors(haze_points,haze_colors,11.2*highway.ROAD_SCALE,true)
	if not trail_points.is_empty(): draw_multiline_colors(trail_points,trail_colors,2.0*highway.ROAD_SCALE,true)
	if not star_points.is_empty(): draw_multiline_colors(star_points,star_colors,1.0,true)

func _sprite(texture: Texture2D, center: Vector2, size: Vector2, tint: Color) -> void:
	if tint.a <= 0.001: return
	draw_texture_rect(texture,Rect2(center-size*0.5,size),false,tint)
