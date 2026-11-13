class_name RhythmComboEffects
extends Node2D
## A small fixed pool of additive milestone columns, behind noteheads and HUD.

const ATLAS: Texture2D = preload("res://assets/effects/pillar-atlas.png")
const FRAME_SIZE: Vector2 = Vector2(128, 256)
const FRAMES: int = 32
const COLUMNS: int = 8
const LIFETIME: float = 0.52
const MAX_PILLARS: int = 3
const PILLAR_SIZE: Vector2 = Vector2(320.0, 620.0)
const BASE_UV: float = 0.86

var highway: RhythmHighway
var _sprites: Array[Sprite2D] = []
var _frames: Array[int] = []
var _born: Array[float] = []
var _last_combo: int = 0
var _cursor: int = 0
var _last_visual_age: float = -1.0

func _ready() -> void:
	name = "ComboPillars"
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in MAX_PILLARS:
		var pillar: Sprite2D = Sprite2D.new()
		pillar.name = "Pillar%d" % index
		pillar.texture = ATLAS
		pillar.region_enabled = true
		pillar.region_filter_clip_enabled = true
		pillar.region_rect = Rect2(Vector2.ZERO, FRAME_SIZE)
		pillar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pillar.centered = false
		pillar.scale = PILLAR_SIZE / FRAME_SIZE * highway.ROAD_SCALE
		pillar.visible = false
		pillar.material = additive
		add_child(pillar)
		_sprites.append(pillar)
		_frames.append(-1)
		_born.append(-100.0)

func on_judgment(combo: int, lane: float, value: float) -> void:
	var previous: int = _last_combo
	_last_combo = combo
	if value <= 0.0 or combo <= previous or combo == 0 or combo % 10 != 0: return
	var slot: int = _cursor
	_cursor = (_cursor + 1) % MAX_PILLARS
	var origin: Vector2 = highway.project(clampf(lane, 0.0, 4.0), 0.0)
	_sprites[slot].position = origin - Vector2(PILLAR_SIZE.x * 0.5, PILLAR_SIZE.y * BASE_UV) * highway.ROAD_SCALE
	_born[slot] = highway.game.visual_age
	_set_frame(slot, 0)
	_sprites[slot].show()

func reset() -> void:
	_last_combo = 0
	_cursor = 0
	_last_visual_age = -1.0
	for index: int in _sprites.size():
		_sprites[index].hide()
		_born[index] = -100.0

func _process(_delta: float) -> void:
	if highway == null or highway.game == null: return
	var now: float = highway.game.visual_age
	if now == _last_visual_age: return
	_last_visual_age = now
	for index: int in _sprites.size():
		if not _sprites[index].visible: continue
		var age: float = now - _born[index]
		if age < 0.0 or age >= LIFETIME:
			_sprites[index].hide()
		else:
			_set_frame(index, mini(FRAMES - 1, floori(age / LIFETIME * FRAMES)))

func _set_frame(slot: int, frame: int) -> void:
	if _frames[slot] == frame: return
	_frames[slot] = frame
	_sprites[slot].region_rect = Rect2(Vector2(float(frame % COLUMNS) * FRAME_SIZE.x, floorf(float(frame) / COLUMNS) * FRAME_SIZE.y), FRAME_SIZE)
