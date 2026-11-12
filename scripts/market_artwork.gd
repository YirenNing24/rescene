class_name MarketArtwork
extends Control
## Reusable photo cards and lightweight vector product illustrations.

const PHOTO_SHADER: Shader = preload("res://shaders/market_photo.gdshader")
const PACK: Texture2D = preload("res://assets/ui/store-pack.svg")
const MATERIAL: Texture2D = preload("res://assets/ui/store-material.svg")
const DRINK: Texture2D = preload("res://assets/art/items/energy-drink.png")

var host: ResceneMainMenu
var item: Dictionary = {}
var previewable: bool = false
var _art: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _resized_connection: int = resized.connect(_render)
	_render()

func _render() -> void:
	if size.x < 1.0 or size.y < 1.0 or item.is_empty() or host == null: return
	if is_instance_valid(_art): _art.hide(); _art.queue_free()
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	if str(item.category) == "cards":
		var card: MemberCardArt = MemberCardArt.new(); card.host = host; card.item_id = str(item.id)
		card.previewable = previewable
		host._at(_art, card, Rect2(Vector2.ZERO, size))
		return
	var factor: float = minf(size.x / 300.0, size.y / 240.0)
	_art.scale = Vector2.ONE * factor
	_art.position = (size - Vector2(300, 240) * factor) * 0.5
	var accent: Color = Color(str(item.accent))
	match str(item.category):
		"packs":
			_card(_art, Rect2(165, 64, 101, 146), 2, accent, 0.13)
			_texture(PACK, Rect2(15, 0, 280, 240), accent.lightened(0.25))
		"upgrades":
			_texture(MATERIAL, Rect2(10, 0, 280, 240), accent)
		"energy":
			if item.id == "energy_trio":
				_texture(DRINK, Rect2(-36, 14, 280, 222), Color("c6bedb"))
				_texture(DRINK, Rect2(68, 14, 280, 222), Color("c6bedb"))
			_texture(DRINK, Rect2(10, 0, 280, 240), Color.WHITE)

func _texture(texture: Texture2D, rect: Rect2, tint: Color) -> void:
	var view: TextureRect = TextureRect.new()
	view.texture = texture
	view.modulate = tint
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	host._at(_art, view, rect)

func _card(parent: Control, rect: Rect2, member: int, accent: Color, angle: float) -> void:
	var card: MemberCardArt = MemberCardArt.new()
	card.host = host
	card.item_id = "scene_%02d" % (member + 1)
	card.rotation = angle
	card.pivot_offset = rect.size * 0.5
	card.modulate = Color.WHITE.lerp(accent, 0.06)
	host._at(parent, card, rect)
