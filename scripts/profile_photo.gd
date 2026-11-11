class_name ProfilePhoto
extends Control
## Rounded, antialiased photo crop, backed by the authenticated texture cache.
const MASK: Shader = preload("res://shaders/profile_photo.gdshader")
var path: String = ""
var radius: float = 18.0
var cover: bool = true
var _image: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new(); _image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image); _image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade: ShaderMaterial = ShaderMaterial.new(); shade.shader = MASK
	_image.material = shade
	var _resize: int = resized.connect(_update_mask)
	var _connection: int = GameServices.photos().texture_ready.connect(func(ready_path: String) -> void:
		if ready_path == path: _image.texture = GameServices.photos().texture(path))
	_image.texture = GameServices.photos().texture(path)
	_update_mask()

func _update_mask() -> void:
	if is_instance_valid(_image):
		var shade: ShaderMaterial = _image.material as ShaderMaterial
		shade.set_shader_parameter("dimensions", size)
		shade.set_shader_parameter("corner", radius)
