class_name RhythmDiscLayer
extends Node2D
## Analytic ellipse quads: no polygonal circle edges or flattened arc strokes.

const DISC_SHADER: Shader = preload("res://shaders/rhythm_disc.gdshader")
var highway: RhythmHighway
var catchers: bool = false
var _white: ImageTexture

func _ready() -> void:
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = DISC_SHADER
	shader_material.set_shader_parameter("catcher", catchers)
	shader_material.set_shader_parameter("inner_ratio", highway.CATCHER_INNER_RADIUS / highway.CATCHER_RADIUS)
	material = shader_material

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if highway == null or highway.game == null or highway.game.judge == null:
		return
	if catchers:
		for lane: int in 5:
			var tint: Color = RhythmRoadLights.rail_color(highway.game.momentum_visual).lerp(Color("e8e3ff"), 0.35)
			tint.a = 0.38 + highway.catcher_strength(lane) * 0.62
			_disc(highway.project(lane, 0.0), highway.CATCHER_RADIUS, tint)
		return
	var now: float = highway.game.song_time
	var notes: Array[Dictionary] = highway.visible_notes()
	for index: int in range(notes.size() - 1, -1, -1):
		var note: Dictionary = notes[index]
		var head_time: float = maxf(StrictData.number(note.time), now) if note.state == 1 else note.time
		var point: Vector2 = highway.project(RhythmChart.lane_at(note, head_time), head_time - now)
		var depth: float = clampf((point.y - highway.TOP_Y) / (highway.HIT_Y - highway.TOP_Y), 0.0, 1.1)
		var radius: float = highway.CATCHER_RADIUS * lerpf(highway.TOP_WIDTH, highway.HIT_WIDTH, depth) / highway.HIT_WIDTH
		_disc(point, radius * (1.22 if note.kind == "slide" else 1.0), highway.note_color(note))

func _disc(point: Vector2, radius: float, tint: Color) -> void:
	var size: Vector2 = Vector2(radius, radius * highway.CATCHER_FLATTEN) * 2.3
	draw_texture_rect(_white, Rect2(point - size * 0.5, size), false, tint)
