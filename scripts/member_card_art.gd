class_name MemberCardArt
extends Control
## One frame system for the shop, collection, profile and stage.
const PHOTOS: Array[Texture2D] = [
	preload("res://assets/art/cards/woni.jpg"), preload("res://assets/art/cards/liv.jpg"),
	preload("res://assets/art/cards/minami.jpg"), preload("res://assets/art/cards/may.jpg"),
	preload("res://assets/art/cards/zena.jpg"),
]
var host: ResceneMainMenu
var item_id: String = "scene_01"
var _frame: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _connection: int = resized.connect(_render)
	_render()

func _render() -> void:
	if host == null or size.x < 1.0 or size.y < 1.0: return
	if is_instance_valid(_frame): _frame.hide(); _frame.queue_free()
	var item: Dictionary = MarketCatalog.find_item(item_id)
	if item.is_empty() or str(item.get("category", "")) != "cards": return
	if not StrictData.boolean(item.get("legacy", false)):
		var path: String = CardReleases.artwork(item)
		if ResourceLoader.exists(path):
			_frame = Control.new(); _frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_frame)
			var artwork: TextureRect = TextureRect.new()
			artwork.texture = load(path) as Texture2D
			artwork.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			host._at(_frame, artwork, Rect2(Vector2.ZERO, size))
			return
	_frame = Control.new(); _frame.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_frame)
	var factor: float = minf(size.x / 320.0, size.y / 460.0)
	_frame.scale = Vector2.ONE * factor
	_frame.position = (size - Vector2(320, 460) * factor) * 0.5
	var accent: Color = Color(str(item.accent))
	var _shadow: Panel = host._panel(_frame, Rect2(6, 8, 308, 448), Color(0.01, 0.01, 0.04, 0.5), Color.TRANSPARENT, 20)
	var border: Panel = host._panel(_frame, Rect2(0, 0, 308, 448), Color("29253e"), accent, 19)
	var inner: Panel = host._panel(border, Rect2(7, 7, 294, 350), Color("181727"), Color(accent, 0.3), 13)
	inner.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var photo: TextureRect = TextureRect.new()
	var index: int = clampi(StrictData.integer(item.member), 0, 4)
	var crop: AtlasTexture = AtlasTexture.new()
	crop.atlas = PHOTOS[index]
	var regions: Array[Rect2] = [Rect2(750.0 / 3071.0, 0, 2100.0 / 3071.0, 3000.0 / 4096.0), Rect2(250.0 / 2057.0, 0, 1600.0 / 2057.0, 2476.0 / 2742.0), Rect2(0, 0, 1764.0 / 4096.0, 1), Rect2(400.0 / 3071.0, 200.0 / 4096.0, 1938.0 / 3071.0, 3000.0 / 4096.0), Rect2(550.0 / 3071.0, 0, 2100.0 / 3071.0, 3250.0 / 4096.0)]
	var dimensions: Vector2 = PHOTOS[index].get_size()
	crop.region = Rect2(regions[index].position * dimensions, regions[index].size * dimensions)
	photo.texture = crop
	photo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	host._at(inner, photo, Rect2(0, 0, 294, 350))
	var _badge: Panel = host._panel(border, Rect2(20, 20, 52, 32), Color("252039"), Color(accent, 0.7), 9)
	var _rarity: Label = host._label(border, "SR", Rect2(20, 24, 52, 26), 15, accent, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var _name: Label = host._label(border, str(item.get("member_name", "")).to_upper(), Rect2(21, 365, 266, 36), 28, host.WHITE, host.SERIF)
	var _series: Label = host._label(border, "FIRST SCENE  /  %02d" % (StrictData.integer(item.member) + 1), Rect2(22, 411, 266, 23), 11, accent, host.BOLD)
	host._line(border, Rect2(22, 405, 264, 1), Color(accent, 0.35))
