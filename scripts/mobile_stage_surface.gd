class_name MobileStageSurface
extends Control
## A 720p render target with the original 2400 × 1080 gameplay/input space.

const DESIGN_SIZE: Vector2i = Vector2i(2400, 1080)
const RENDER_SIZE: Vector2i = Vector2i(1600, 720)

var viewport: SubViewport
var container: SubViewportContainer
var _previous_fps: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	container = SubViewportContainer.new()
	container.name = "GameplayDisplay"
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	container.size = Vector2(RENDER_SIZE)
	add_child(container)
	viewport = SubViewport.new()
	viewport.name = "Gameplay720p"
	viewport.size = RENDER_SIZE
	viewport.size_2d_override = DESIGN_SIZE
	viewport.size_2d_override_stretch = true
	viewport.transparent_bg = true
	viewport.disable_3d = true
	container.add_child(viewport)
	var _resized: int = resized.connect(_layout)
	_layout()
	_previous_fps = Engine.max_fps
	Engine.max_fps = 60


func mount(stage: RhythmStage) -> void:
	stage.mobile_rendering = true
	viewport.add_child(stage)


func _layout() -> void:
	if not is_instance_valid(container): return
	var factor: float = minf(size.x / float(RENDER_SIZE.x), size.y / float(RENDER_SIZE.y))
	container.scale = Vector2.ONE * factor
	container.position = (size - Vector2(RENDER_SIZE) * factor) * 0.5


func _exit_tree() -> void:
	Engine.max_fps = _previous_fps
