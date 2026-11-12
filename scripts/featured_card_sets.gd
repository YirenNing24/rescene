class_name FeaturedCardSets
extends Button
## A lightweight, release-by-release preview. Only the current fan is retained.
const INTERVAL: float = 4.8
const FADE_SECONDS: float = 0.3
var host: ResceneMainMenu
var release_index: int = 0
var _fan: Control
var _title: Label
var _counter: Label
var _indicators: Array[ColorRect] = []
var _timer: Timer
var _transition: Tween

func _ready() -> void:
	name = "FeaturedCardSets"
	clip_contents = true
	tooltip_text = "Explore Limited Edition cards"
	add_theme_stylebox_override("normal", host._style(Color("211e36"), Color(host.LILAC, 0.32), 18))
	add_theme_stylebox_override("hover", host._style(Color("2c2745"), host.LILAC, 18))
	add_theme_stylebox_override("pressed", host._style(Color("1b182d"), host.WHITE, 18))
	add_theme_stylebox_override("focus", host._style(Color.TRANSPARENT, host.WHITE, 18))
	var _heading: Label = host._label(self, "F E A T U R E D   S C E N E", Rect2(18, 13, 260, 20), 11, host.MUTED, host.BOLD)
	_counter = host._label(self, "", Rect2(272, 13, 42, 20), 11, host.LILAC, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_title = host._label(self, "", Rect2(18, 194, 255, 22), 17, host.WHITE, host.BOLD)
	var _arrow: TextureRect = host._icon(self, "arrow", Rect2(291, 196, 18, 18))
	for index: int in CardReleases.RELEASES.size():
		var indicator: ColorRect = ColorRect.new()
		host._at(self, indicator, Rect2(18 + index * 33, 222, 29, 2))
		_indicators.append(indicator)
	_show_release(false)
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	var _timeout: int = _timer.timeout.connect(advance)
	add_child(_timer)
	_timer.start()
	var _pressed: int = pressed.connect(_open_release)

func advance() -> void:
	if not is_visible_in_tree() or is_instance_valid(host._dialog): return
	release_index = (release_index + 1) % CardReleases.RELEASES.size()
	_show_release(true)

func _show_release(animate: bool) -> void:
	if is_instance_valid(_transition): _transition.kill()
	# Finish a previous fade before beginning another (e.g. a quick UI rebuild).
	for child: Node in get_children():
		if child is Control and child.name == "RetiringFan":
			remove_child(child)
			child.queue_free()
	var previous: Control = _fan
	var release: Dictionary = CardReleases.RELEASES[release_index]
	_title.text = str(release.name) + " · LE"
	_counter.text = "%02d / %02d" % [release_index + 1, CardReleases.RELEASES.size()]
	for index: int in _indicators.size():
		_indicators[index].color = host.LILAC if index == release_index else Color(host.LILAC, 0.18)
	_fan = Control.new()
	_fan.name = "CardFan"
	host._at(self, _fan, Rect2(0, 38, 332, 151))
	# Draw the center card last; all five portraits remain visible in the fan.
	var order: Array[int] = [0, 4, 1, 3, 2]
	for member: int in order:
		var distance: float = float(absi(member - 2))
		var card: TextureRect = TextureRect.new()
		card.texture = load(CardReleases.artwork({"set_id": str(release.set_id), "member_name": SongSets.MEMBERS[member]})) as Texture2D
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		host._at(_fan, card, Rect2(10 + member * 56, distance * 6, 88, 136))
		card.pivot_offset = Vector2(44, 125)
		card.rotation = float(member - 2) * 0.055
		card.modulate = Color.WHITE.darkened(distance * 0.045)
	if animate:
		_fan.modulate.a = 0.0
		_fan.position.x = 9
		_transition = create_tween().set_parallel(true)
		var _fade: PropertyTweener = _transition.tween_property(_fan, "modulate:a", 1.0, FADE_SECONDS)
		var _slide: PropertyTweener = _transition.tween_property(_fan, "position:x", 0.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if is_instance_valid(previous):
			previous.name = "RetiringFan"
			var _old_fade: PropertyTweener = _transition.tween_property(previous, "modulate:a", 0.0, FADE_SECONDS)
			var _cleanup: CallbackTweener = _transition.chain().tween_callback(previous.queue_free)
	elif is_instance_valid(previous): previous.queue_free()

func _open_release() -> void:
	host._open_marketplace({"category": "cards", "release_id": str(CardReleases.RELEASES[release_index].set_id)})
