class_name RhythmSlideTouches
extends Node2D
## Ten reusable additive contact glows; one small shared texture, no blur pass.
const MAX_TOUCHES: int = 10
var highway: RhythmHighway
var _sprites: Array[Sprite2D] = []
var _texture: ImageTexture
var _generation: int = -1

func _ready() -> void:
	name = "SlideTouchGlows"
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in 64:
		for x: int in 64:
			var radius: float = (Vector2(float(x), float(y)) - Vector2(31.5, 31.5)).length() / 31.5
			var falloff: float = maxf(0.0, 1.0 - radius)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff * falloff * (3.0 - 2.0 * falloff)))
	_texture = ImageTexture.create_from_image(image)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in MAX_TOUCHES:
		var glow: Sprite2D = Sprite2D.new()
		glow.name = "SlideTouch%d" % index
		glow.texture = _texture
		glow.material = additive
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glow.hide()
		add_child(glow)
		_sprites.append(glow)

func reset() -> void:
	for glow: Sprite2D in _sprites: glow.hide()

func _process(_delta: float) -> void:
	if highway == null or highway.game == null or highway.game.judge == null: return
	var game: RhythmStage = highway.game
	if _generation != game.judge.generation:
		reset(); _generation = game.judge.generation
	if game.phase in ["paused", "resume"]: return
	reset()
	if game.phase not in ["playing", "countdown"]: return
	var slot: int = 0
	var time: float = game.song_time + game.timing_offset_ms / 1000.0
	for note: Dictionary in highway.visible_notes():
		if slot >= MAX_TOUCHES: break
		if note.kind != "slide" or note.state != 1 or note.time > time: continue
		var pointer_id: int = StrictData.integer(note.owner)
		if not game.judge.pointer_tracks(note, time, pointer_id): continue
		var pointer: Dictionary = game.judge.pointers[pointer_id]
		var point: Vector2 = highway.project(StrictData.number(pointer.lane), 0.0)
		var y: int = StrictData.integer(pointer.get("y", -1))
		if y >= 0: point.y = float(y) * 1080.0 / 10000.0
		var glow: Sprite2D = _sprites[slot]
		glow.position = point
		var pulse: float = 1.0 + sin(game.visual_age * 7.0) * 0.045
		glow.scale = Vector2(220.0, 160.0) / 64.0 * highway.ROAD_SCALE * pulse
		glow.modulate = Color(highway._ribbon_tint(note, time, highway.note_color(note)).lerp(Color("d5ffef"), 0.6), 0.88)
		glow.show()
		slot += 1
