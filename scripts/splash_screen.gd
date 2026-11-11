class_name SplashScreen
extends Control
## The game's opening screen. Assign next_scene in the inspector when the menu exists.

signal start_requested

@export var next_scene: PackedScene
@export_range(0.0, 3.0) var fade_in_seconds: float = 0.8
@export_range(0.0, 600.0) var music_start_seconds: float = 49.0

@onready var start_button: Button = $StartButton
@onready var flash: ColorRect = $Flash
@onready var fade: ColorRect = $Fade
@onready var artwork: TextureRect = $Artwork
@onready var music: AudioStreamPlayer = $Music

var _ready_for_input: bool = false
var _starting: bool = false


func _ready() -> void:
	var _int_1: int = resized.connect(_layout_artwork)
	_layout_artwork()
	start_button.disabled = true
	var _int_2: int = start_button.pressed.connect(_request_start)
	# Keep looping local to this splash; every repeat returns to the chorus.
	var soundtrack: AudioStreamMP3 = music.stream.duplicate() as AudioStreamMP3
	soundtrack.loop = true
	soundtrack.loop_offset = music_start_seconds
	music.stream = soundtrack
	var music_volume: float = music.volume_linear
	music.volume_linear = 0.0
	music.play(music_start_seconds)
	var entrance: Tween = create_tween()
	var _propertytweener_3: PropertyTweener = entrance.tween_property(fade, "color:a", 0.0, fade_in_seconds)
	var _propertytweener_4: PropertyTweener = entrance.parallel().tween_property(music, "volume_linear", music_volume, 0.35)
	var _callbacktweener_5: CallbackTweener = entrance.tween_callback(func() -> void:
		_ready_for_input = true
		start_button.disabled = false
	)


func _exit_tree() -> void:
	if is_instance_valid(music):
		music.stop()


func _layout_artwork() -> void:
	# Fill phone screens between 16:9 and the artwork's wide aspect ratio.
	# On tablets, retain the central 16:9 composition instead of cutting faces.
	# Beyond the wide artwork, retain its full height instead of cropping the title.
	var texture_size: Vector2 = artwork.texture.get_size()
	var wide_aspect: float = texture_size.x / texture_size.y
	var frame: Vector2 = Vector2(minf(size.x, size.y * wide_aspect), minf(size.y, size.x * 9.0 / 16.0))
	artwork.size = frame
	artwork.position = (size - frame) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_request_start.call_deferred()


func _request_start() -> void:
	if not _ready_for_input or _starting:
		return
	_starting = true
	start_button.disabled = true
	flash.color.a = 0.16
	($Particles as SplashParticles).burst(artwork.position + artwork.size * Vector2(0.5, 0.9))
	var feedback: Tween = create_tween()
	var _propertytweener_6: PropertyTweener = feedback.tween_property(flash, "color:a", 0.0, 0.3)
	await feedback.finished
	start_requested.emit()
	if not is_inside_tree():
		return
	if next_scene != null:
		var exit_tween: Tween = create_tween()
		var _propertytweener_7: PropertyTweener = exit_tween.tween_property(fade, "color:a", 1.0, 0.4)
		var _propertytweener_8: PropertyTweener = exit_tween.parallel().tween_property(music, "volume_linear", 0.0, 0.4)
		await exit_tween.finished
		var _error_9: Error = get_tree().change_scene_to_packed(next_scene)
	else:
		# Keep the splash usable until a main menu is connected.
		_starting = false
		start_button.disabled = false
