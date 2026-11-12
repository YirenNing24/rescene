class_name RhythmSustainEffects
extends Node2D
## Reusable road-plane vortices driven by collected holds and curved ribbons.

const VORTEX_SHADER: Shader = preload("res://shaders/sustain_vortex.gdshader")
const MAX_VORTICES: int = 10 # Same bound as simultaneous judge pointers.
const VORTEX_SIZE: Vector2 = Vector2(302.0, 172.0)
const ORIGIN_UV: Vector2 = Vector2(0.5, 0.64)
const ATTACK: float = 0.06
const RELEASE: float = 0.12

var highway: RhythmHighway
var _sprites: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []
var _ids: Array[int] = []
var _born: Array[float] = []
var _released: Array[float] = []
var _active: Array[bool] = []

func _ready() -> void:
	name = "SustainVortices"
	var pixel: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(pixel)
	for index: int in MAX_VORTICES:
		var vortex: Sprite2D = Sprite2D.new()
		vortex.name = "Vortex%d" % index
		vortex.texture = texture
		vortex.centered = false
		vortex.scale = VORTEX_SIZE * highway.ROAD_SCALE
		vortex.hide()
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = VORTEX_SHADER
		vortex.material = shader_material
		add_child(vortex)
		_sprites.append(vortex)
		_materials.append(shader_material)
		_ids.append(-1)
		_born.append(0.0)
		_released.append(-1.0)
		_active.append(false)

func reset() -> void:
	_ids.fill(-1)
	_released.fill(-1.0)
	_active.fill(false)
	for vortex: Sprite2D in _sprites: vortex.hide()

func _process(_delta: float) -> void:
	if highway == null or highway.game == null or highway.game.judge == null: return
	var game: RhythmStage = highway.game
	if game.phase in ["paused", "resume"]: return
	var now: float = game.visual_age
	_active.fill(false)
	for note: Dictionary in game.judge.notes:
		if note.time > game.song_time + game.timing_offset_ms / 1000.0: break
		if note.state != 1 or not _is_collected(note): continue
		var id: int = StrictData.integer(note.id)
		var slot: int = _ids.find(id)
		if slot == -1:
			slot = _free_slot()
			if slot == -1: continue
			_ids[slot] = id
			_born[slot] = now
			_materials[slot].set_shader_parameter("tint", highway.note_color(note))
			_materials[slot].set_shader_parameter("seed", float(id) * 2.4)
		_active[slot] = true
		_released[slot] = -1.0
		var lane: float = RhythmChart.lane_at(note, game.song_time)
		_sprites[slot].position = highway.project(lane, 0.0) - VORTEX_SIZE * highway.ROAD_SCALE * ORIGIN_UV
		_sprites[slot].show()
	for slot: int in MAX_VORTICES:
		if _ids[slot] == -1: continue
		if not _active[slot] and _released[slot] < 0.0: _released[slot] = now
		var release_strength: float = 1.0 if _active[slot] else clampf(1.0 - (now - _released[slot]) / RELEASE, 0.0, 1.0)
		if release_strength <= 0.0:
			_ids[slot] = -1
			_sprites[slot].hide()
			continue
		var age: float = maxf(0.0, now - _born[slot])
		_materials[slot].set_shader_parameter("age", age)
		_materials[slot].set_shader_parameter("strength", smoothstep(0.0, ATTACK, age) * release_strength)

func _is_collected(note: Dictionary) -> bool:
	var judge: RhythmJudge = highway.game.judge
	var pointer_owner: int = StrictData.integer(note.owner)
	var time: float = highway.game.song_time + highway.game.timing_offset_ms / 1000.0
	var lane: float = RhythmChart.lane_at(note, time)
	if judge.pointers.has(pointer_owner) and absf(StrictData.number(judge.pointers[pointer_owner].lane) - lane) <= judge.TRACE_TOLERANCE:
		return true
	if pointer_owner <= -100:
		for pointer_id: int in judge.pointers:
			if pointer_id <= -100 and absf(StrictData.number(judge.pointers[pointer_id].lane) - lane) <= judge.TRACE_TOLERANCE:
				return true
	return false

func _free_slot() -> int:
	var free: int = _ids.find(-1)
	if free != -1: return free
	var oldest: float = INF
	for slot: int in MAX_VORTICES:
		if not _active[slot] and _released[slot] >= 0.0 and _released[slot] < oldest:
			oldest = _released[slot]
			free = slot
	return free
