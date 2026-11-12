class_name ResceneMainMenu
extends Control
## Native Godot lobby. UI uses the project's fixed 2400 × 1080 composition.

const WHITE: Color = Color("f4f1ff")
const MUTED: Color = Color("b7b9d5")
const LILAC: Color = Color("c7bbff")
const INK: Color = Color("202039")
const FONT: FontFile = preload("res://assets/fonts/Montserrat-Medium.otf")
const BOLD: FontFile = preload("res://assets/fonts/Montserrat-SemiBold.otf")
const SERIF: FontFile = preload("res://assets/fonts/NimbusRoman-Regular.otf")
const ITALIC: FontFile = preload("res://assets/fonts/NimbusRoman-Italic.otf")
const ART: CompressedTexture2D = preload("res://assets/art/rescene-main-menu.png")
const MENU_TRACK: AudioStreamMP3 = preload("res://assets/audio/loveattack-instrumental.mp3")
const PROFILE_PATH: String = "user://lobby.cfg"

## Disabled only by isolated gameplay/UI regression harnesses.
@export var require_auth: bool = true
## Exercises the Android render/input path in desktop regression checks.
@export var force_mobile_gameplay_rendering: bool = false

var _canvas: Control
var _dialog: MenuDestination
var _music: AudioStreamPlayer
var _preview: AudioStreamPlayer
var _particles: SplashParticles
var _profile_name: String = "RE:PLAYER"
var _music_level: float = 0.7
var _effects_on: bool = true
var _haptics_on: bool = true
var _selected_member: int = 0
var _width: float = 2400.0
var _profile_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _profile_frame: Panel
var _avatar_photo: ProfilePhoto
var _starlight_label: Label
var _energy_label: Label
var _energy_hint: Label
var _energy_detail_balance: Label
var _energy_detail_hint: Label
var _daily_hint: Label
var _daily_button: Button
var _profile_mode: bool = false
var _profile_view: PlayerProfile
var _profile_tab: String = "info"
var _profile_song_state: Dictionary = {}
var _social_badge: Panel
var _social_badge_text: Label
var _song_mode: bool = false
var _song_view: SongSelection
var _preview_timer: Timer
var _preview_end_seconds: float = 0.0
var _stage: RhythmStage
var _stage_surface: MobileStageSurface


func _ready() -> void:
	if require_auth and not GameServices.session().is_authenticated():
		set_process(false)
		get_tree().change_scene_to_file.call_deferred("res://scenes/auth_screen.tscn")
		return
	_load_profile()
	if GameServices.session().is_authenticated():
		_profile_name = str(GameServices.session().user.username)
		var _int_1: int = GameServices.session().session_ended.connect(_on_session_ended)
		var _int_2: int = GameServices.progression().changed.connect(_update_progression_hud)
		var _photo_changed: int = GameServices.photos().changed.connect(_update_avatar)
		var _notification: int = GameServices.social().notification_received.connect(_social_notification)
		var _social_changed: int = GameServices.social().changed.connect(_update_social_badge)
		GameServices.progression().refresh.call_deferred()
		GameServices.scores().refresh.call_deferred()
		GameServices.commerce().refresh.call_deferred()
		GameServices.photos().refresh.call_deferred()
	# The menu has its own soundtrack, independent of the splash and song previews.
	_music = AudioStreamPlayer.new()
	_music.name = "MenuMusic"
	var track: AudioStreamMP3 = MENU_TRACK.duplicate() as AudioStreamMP3
	track.loop = true
	track.loop_offset = 0.0
	_music.stream = track
	_music.volume_linear = _music_level * 0.28
	add_child(_music)
	_music.play()
	_preview = AudioStreamPlayer.new()
	_preview.name = "SongPreview"
	_preview.volume_linear = _music.volume_linear
	add_child(_preview)
	var _int_3: int = _preview.finished.connect(_end_preview)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	var _int_4: int = _preview_timer.timeout.connect(_end_preview)
	add_child(_preview_timer)
	_particles = SplashParticles.new()
	_particles.sparkle_count = 52
	_particles.intensity = 0.5
	add_child(_particles)
	_particles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_particles.visible = _effects_on
	_canvas = Control.new()
	_canvas.name = "MenuUI"
	add_child(_canvas)
	var _int_5: int = resized.connect(_rebuild)
	_rebuild()
	_canvas.modulate.a = 0.0
	if require_auth and not FirstPlay.seen(): _offer_tutorial.call_deferred()
	var _propertytweener_6: PropertyTweener = create_tween().tween_property(_canvas, "modulate:a", 1.0, 0.5)
	if OS.has_feature("android") and require_auth: _check_app_update.call_deferred()

func _check_app_update() -> void:
	await get_tree().create_timer(3.0).timeout
	var updates: AppUpdateService = get_node("/root/AppUpdates") as AppUpdateService
	await updates.check()
	if updates.available() and updates.dismissed_code != StrictData.integer(updates.release.version_code) and not is_instance_valid(_stage) and not is_instance_valid(_dialog) and not _song_mode:
		var _view: AppUpdateView = AppUpdateView.open(self)


func _rebuild() -> void:
	if _canvas == null:
		return
	var market_state: Dictionary = (_dialog as MarketplaceView).snapshot() if is_instance_valid(_dialog) and _dialog is MarketplaceView else {}
	var collection_open: bool = is_instance_valid(_dialog) and _dialog is CollectionView
	var collection_archived: bool = (_dialog as CollectionView).archived if collection_open else false
	var collection_selected: String = (_dialog as CollectionView).selected_id if collection_open else ""
	var collection_state: Dictionary = (_dialog as CollectionView).state() if collection_open else {}
	if is_instance_valid(_dialog) and _dialog is AccountSecurityView and (_dialog as AccountSecurityView)._busy:
		var _retry_rebuild: int = get_tree().create_timer(0.2).timeout.connect(_rebuild, CONNECT_ONE_SHOT)
		return
	var security_snapshot: Dictionary = (_dialog as AccountSecurityView).snapshot() if is_instance_valid(_dialog) and _dialog is AccountSecurityView else {}
	var security_open: bool = is_instance_valid(_dialog) and _dialog is AccountSecurityView
	var challenge_open: bool = is_instance_valid(_dialog) and _dialog is ChallengesView
	var challenge_saved: Dictionary = (_dialog as ChallengesView).snapshot() if challenge_open else {}
	var challenge_peer: Dictionary = (_dialog as ChallengesView).peer if challenge_open else {}
	var events_open: bool = is_instance_valid(_dialog) and _dialog is EventsView
	var inventory_open: bool = is_instance_valid(_dialog) and _dialog is InventoryView
	var social_state: Dictionary = (_dialog as SocialView).snapshot() if is_instance_valid(_dialog) and _dialog is SocialView else {}
	for child: Node in _canvas.get_children():
		# Rebuilding can happen inside a button's pressed signal.
		# Defer deletion until that input event has finished dispatching.
		if child is CanvasItem:
			(child as CanvasItem).hide()
		child.queue_free()
	_dialog = null
	_song_view = null
	_profile_view = null
	var factor: float = minf(size.x / 2400.0, size.y / 1080.0)
	_width = size.x / factor
	_canvas.scale = Vector2.ONE * factor
	_canvas.size = Vector2(_width, 1080)
	_canvas.position = Vector2(0, (size.y - 1080 * factor) * 0.5)
	if _profile_mode:
		_profile_view = PlayerProfile.new()
		_profile_view.host = self
		_profile_view.tab = _profile_tab
		_profile_view.size = _canvas.size
		_canvas.add_child(_profile_view)
		if not social_state.is_empty(): _open_social({}, "friends", social_state)
		return
	_build_header()
	if _song_mode:
		_song_view = SongSelection.new()
		_song_view.set("host", self)
		var _int_7: int = _song_view.back_requested.connect(_back_from_songs)
		var _int_8: int = _song_view.preview_requested.connect(_play_song_preview)
		var _int_9: int = _song_view.preview_stopped.connect(_end_preview)
		var _int_10: int = _song_view.start_requested.connect(_request_song_start)
		_canvas.add_child(_song_view)
		_song_view.size = _canvas.size
	else:
		_build_left()
		_build_center()
		_build_social()
		_build_footer()
	if not market_state.is_empty(): _open_marketplace(market_state)
	elif security_open: _open_account_security(security_snapshot)
	elif challenge_open: _open_challenges(challenge_peer, challenge_saved)
	elif events_open: _open_event()
	elif inventory_open: _open_inventory()
	elif collection_open:
		_open_collection(collection_selected, collection_archived)
		(_dialog as CollectionView).restore(collection_state)
		(_dialog as CollectionView)._render()
	elif not social_state.is_empty(): _open_social({}, "friends", social_state)


func _exit_tree() -> void:
	if is_instance_valid(_music):
		_music.stop()
	if is_instance_valid(_preview):
		_preview.stop()


func _process(_delta: float) -> void:
	if is_instance_valid(_energy_hint): _energy_hint.text = GameServices.progression().energy_hint()
	if is_instance_valid(_energy_detail_hint): _energy_detail_hint.text = GameServices.progression().energy_hint()
	# Audio position is the final cutoff authority, independent of timer latency.
	if _preview.playing and _preview.get_playback_position() >= _preview_end_seconds:
		_end_preview()


func _build_header() -> void:
	_line(_canvas, Rect2(58, 139, _width - 116, 1), Color(0.8, 0.8, 1, 0.18))
	var profile: Button = _button(_canvas, "", Rect2(58, 42, 330, 80), _open_profile, false, false)
	profile.name = "PlayerProfileButton"
	_profile_frame = _panel(profile, Rect2(0, 0, 76, 76), Color(0.72, 0.66, 0.95, 0.14), GameServices.progression().frame_color(), 22)
	var _texturerect_11: TextureRect = _icon(profile, "person", Rect2(20, 18, 36, 36))
	_update_avatar()
	_profile_label = _label(profile, _profile_name, Rect2(96, 5, 226, 32), 25, WHITE, BOLD)
	_profile_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_level_label = _label(profile, "", Rect2(97, 42, 250, 24), 13, MUTED)
	_level_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("background", _style(Color(0.65,0.61,0.85,0.2), Color.TRANSPARENT, 2))
	_xp_bar.add_theme_stylebox_override("fill", _style(LILAC, Color.TRANSPARENT, 2))
	_at(profile, _xp_bar, Rect2(98,73,226,4))
	var _label_12: Label = _label(_canvas, "R E S C É N E   /   R H Y T H M", Rect2(_width * 0.5 - 215, 65, 430, 30), 17, Color(0.88, 0.86, 1, 0.8), FONT, HORIZONTAL_ALIGNMENT_CENTER)
	var right: float = _width - 690
	_energy_label = _currency(right, "heart", "ENERGY", "—/15")
	_energy_label.name = "EnergyBalance"
	_energy_hint = _label(_canvas, "", Rect2(right, 118, 155, 18), 10, MUTED, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_energy_hint.name = "EnergyRecovery"
	_starlight_label = _currency(right + 167, "star", "STARLIGHT", "0")
	var _label_14: Label = _currency(right + 334, "gem", "CRYSTALS", "0")
	var inbox: Button = _icon_button(_canvas, "mail", Rect2(_width - 176, 42, 72, 72), func() -> void: _open_social({}, "messages"))
	inbox.name = "MessagesButton"
	_social_badge = _panel(inbox, Rect2(45, 1, 27, 27), LILAC, Color.TRANSPARENT, 14)
	_social_badge_text = _label(_social_badge, "", Rect2(0, 3, 27, 22), 12, INK, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_update_social_badge()
	var _button_16: Button = _icon_button(_canvas, "settings", Rect2(_width - 100, 42, 72, 72), _open_settings)
	_update_progression_hud()


func _currency(x: float, icon_name: String, title: String, value: String) -> Label:
	var button: Button = _button(_canvas, "", Rect2(x, 48, 155, 68), func() -> void:
		if title == "STARLIGHT": _open_progression()
		elif title == "ENERGY": _open_energy()
		else: _open_section(title.capitalize(), "Your rhythm, your rewards.", "This resource is not used yet.", icon_name))
	var _texturerect_17: TextureRect = _icon(button, icon_name, Rect2(12, 22, 25, 25))
	var _label_18: Label = _label(button, title, Rect2(47, 11, 100, 18), 10, MUTED, BOLD)
	return _label(button, value, Rect2(47, 31, 88, 28), 23, WHITE, BOLD)


func _update_avatar() -> void:
	if _profile_mode: return
	if not is_instance_valid(_profile_frame) or not is_instance_valid(_profile_frame.get_parent()): return
	if is_instance_valid(_avatar_photo): _avatar_photo.hide(); _avatar_photo.queue_free()
	_avatar_photo = null
	var path: String = str(StrictData.dictionary(GameServices.photos().media.get("avatar", {})).get("url", ""))
	if path.is_empty(): return
	_avatar_photo = ProfilePhoto.new(); _avatar_photo.path = path; _avatar_photo.radius = 19
	_at(_profile_frame.get_parent(), _avatar_photo, Rect2(4, 4, 68, 68))


func _update_progression_hud() -> void:
	if is_instance_valid(_level_label):
		_level_label.text = "LV. %02d   /   %s" % [GameServices.progression().state.get("level",1), GameServices.progression().equipped_title().to_upper()]
	if is_instance_valid(_xp_bar):
		_xp_bar.max_value = maxf(1, StrictData.number(GameServices.progression().state.get("level_cost",200)))
		_xp_bar.value = StrictData.number(GameServices.progression().state.get("level_xp",0))
		_xp_bar.tooltip_text = "%d total XP" % StrictData.integer(GameServices.progression().state.get("xp",0))
	if is_instance_valid(_profile_frame):
		_profile_frame.add_theme_stylebox_override("panel", _style(Color(GameServices.progression().frame_color(),0.14), GameServices.progression().frame_color(),22))
	if is_instance_valid(_starlight_label):
		_starlight_label.text = GameServices.progression().starlight_text()
		_starlight_label.tooltip_text = GameServices.progression().starlight_hint()
	if is_instance_valid(_energy_label): _energy_label.text = GameServices.progression().energy_text()
	if is_instance_valid(_energy_detail_balance): _energy_detail_balance.text = GameServices.progression().energy_text()
	if is_instance_valid(_daily_hint):
		var login: Dictionary = GameServices.progression().state.get("daily_login", {})
		_daily_hint.text = "Claimed · See you tomorrow" if login.get("claimed_today", false) else "Your daily gift is waiting" if not login.is_empty() else "Seven days of little gifts"


func _open_energy() -> void:
	var progress: ProgressionService = GameServices.progression()
	var window: Panel = _modal("Energy", "YOUR NEXT SCENE")
	_energy_detail_balance = _label(window, progress.energy_text(), Rect2(44, 166, 670, 78), 60, WHITE, BOLD)
	var _rules: Label = _label(window, "1 energy per song attempt, including retries.\nRecover 1 every 30 minutes, up to 15.\nRecovery continues while you’re away.", Rect2(44, 260, 670, 110), 21, MUTED, FONT)
	_energy_detail_hint = _label(window, progress.energy_hint(), Rect2(44, 390, 670, 35), 23, LILAC, BOLD)
	if GameServices.session().is_authenticated(): progress.refresh.call_deferred()


func _open_progression(tab: String = "missions") -> void:
	_close_dialog()
	_dialog = ProgressionView.new()
	_dialog.host = self
	(_dialog as ProgressionView).tab = tab
	_canvas.add_child(_dialog)
	_dialog.size = _canvas.size
	if GameServices.progression().state.is_empty(): GameServices.progression().refresh.call_deferred()

func _open_daily_login() -> void:
	_close_dialog()
	_dialog = DailyLoginView.new()
	_dialog.host = self
	_dialog.size = _canvas.size
	_canvas.add_child(_dialog)
	GameServices.progression().refresh.call_deferred()


func _build_left() -> void:
	var _label_19: Label = _label(_canvas, "Y O U R   B A C K S T A G E", Rect2(62, 188, 330, 24), 13, MUTED)
	var items: Array = [["bag", "SHOP"], ["cards", "CARDS"], ["mission", "MISSIONS"]]
	for index: int in items.size():
		var entry: Array = items[index]
		var button: Button = _button(_canvas, "", Rect2(58 + index * 114, 230, 104, 104), func() -> void: _open_destination(str(entry[1])))
		var _texturerect_20: TextureRect = _icon(button,str(entry[0]), Rect2(34, 18, 34, 34))
		var _label_21: Label = _label(button,str(entry[1]), Rect2(0, 67, 104, 22), 12, WHITE, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var featured: FeaturedCardSets = FeaturedCardSets.new()
	featured.host = self
	_at(_canvas, featured, Rect2(58, 358, 332, 232))
	var daily: Button = _button(_canvas, "", Rect2(58, 608, 332, 82), _open_daily_login)
	_daily_button = daily
	daily.name = "DailyGiftsButton"
	var _texturerect_26: TextureRect = _icon(daily, "gift", Rect2(22, 24, 34, 34))
	var _label_27: Label = _label(daily, "DAILY GIFTS", Rect2(77, 16, 232, 26), 18, WHITE, BOLD)
	_daily_hint = _label(daily, "", Rect2(77, 46, 240, 24), 12, MUTED)
	_update_progression_hud()
	var welcome: Button = _button(_canvas, "", Rect2(58, 708, 332, 82), _start_tutorial)
	var _texturerect_28: TextureRect = _icon(welcome, "heart", Rect2(23, 25, 32, 32))
	var _label_29: Label = _label(welcome, "HOW TO PLAY", Rect2(77, 16, 232, 26), 18, WHITE, BOLD)
	var _label_30: Label = _label(welcome, "Tap, hold & follow the ribbon", Rect2(77, 46, 240, 24), 12, MUTED)


func _build_center() -> void:
	var center: float = _width * 0.5
	var _label_31: Label = _label(_canvas, "RESCÉNE", Rect2(center - 280, 174, 560, 100), 78, WHITE, SERIF, HORIZONTAL_ALIGNMENT_CENTER)
	var _label_32: Label = _label(_canvas, "Rhythm", Rect2(center - 150, 250, 300, 65), 44, Color("d6cdff"), ITALIC, HORIZONTAL_ALIGNMENT_CENTER)
	var _label_33: Label = _label(_canvas, "Y O U R   S T A G E .   Y O U R   S C E N E .", Rect2(center - 340, 329, 680, 24), 13, Color(0.9, 0.87, 1, 0.8), FONT, HORIZONTAL_ALIGNMENT_CENTER)
	var _label_34: Label = _label(_canvas, "0 1    /    T H E   F I R S T   S C E N E", Rect2(center - 260, 823, 520, 25), 13, WHITE, FONT, HORIZONTAL_ALIGNMENT_CENTER)
	_line(_canvas, Rect2(center - 33, 867, 39, 3), LILAC)
	_line(_canvas, Rect2(center + 16, 867, 8, 3), Color(0.8, 0.8, 1, 0.3))
	_line(_canvas, Rect2(center + 34, 867, 8, 3), Color(0.8, 0.8, 1, 0.3))


func _build_social() -> void:
	var rail: OnlineFriendsRail = OnlineFriendsRail.new()
	rail.host = self; rail.name = "OnlineFriends"
	_at(_canvas, rail, Rect2(_width - 170, 230, 112, 620))


func _update_social_badge() -> void:
	if not is_instance_valid(_social_badge): return
	var unread: int = StrictData.integer(GameServices.social().summary.get("unread", 0))
	_social_badge.visible = unread > 0
	_social_badge_text.text = str(mini(99, unread))


func _open_social(peer: Dictionary = {}, destination: String = "friends", saved: Dictionary = {}, challenge_seed: Dictionary = {}) -> void:
	_close_dialog()
	var social: SocialView = SocialView.new()
	social.host = self; social.size = _canvas.size; social.tab = destination; social.selected = peer; social.challenge_seed = challenge_seed
	if not saved.is_empty(): social.restore(saved)
	_dialog = social; _canvas.add_child(social)

func _open_account_security(saved: Dictionary = {}) -> void:
	_close_dialog()
	var security: AccountSecurityView = AccountSecurityView.new(); security.host = self; security.size = _canvas.size
	_dialog = security; _canvas.add_child(security)
	security.restore(saved)


func _build_footer() -> void:
	_line(_canvas, Rect2(58, 909, _width - 116, 1), Color(0.8, 0.8, 1, 0.2))
	var _label_38: Label = _label(_canvas, "HOME", Rect2(62, 872, 100, 24), 12, LILAC, BOLD)
	var tabs: Array = [["music", "SONGS"], ["cards", "COLLECTION"], ["bag", "INVENTORY"], ["star", "RECORDS"]]
	for index: int in tabs.size():
		var entry: Array = tabs[index]
		var button: Button = _button(_canvas, "", Rect2(58 + index * 161, 934, 145, 104), func() -> void: _open_destination(str(entry[1])), false, false)
		var _texturerect_39: TextureRect = _icon(button,str(entry[0]), Rect2(54, 5, 36, 36))
		var _label_40: Label = _label(button,str(entry[1]), Rect2(0, 61, 145, 26), 13, WHITE, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var energy_button: Button = _button(_canvas, "", Rect2(_width - 660, 945, 220, 83), _open_energy)
	var _texturerect_41: TextureRect = _icon(energy_button, "heart", Rect2(18, 25, 30, 30))
	var _label_42: Label = _label(energy_button, "SONG COST", Rect2(65, 13, 140, 20), 10, MUTED, BOLD)
	var _label_43: Label = _label(energy_button, "1 ENERGY", Rect2(65, 39, 145, 28), 18, WHITE, BOLD)
	var _label_44: Label = _label(_canvas, "THE SPOTLIGHT IS YOURS", Rect2(_width - 418, 904, 360, 26), 12, LILAC, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var play: Button = _button(_canvas, "", Rect2(_width - 418, 945, 360, 83), _open_songs, true)
	var _label_45: Label = _label(play, "PLAY", Rect2(30, 13, 240, 57), 38, INK, BOLD)
	var _texturerect_46: TextureRect = _icon(play, "play", Rect2(285, 22, 40, 40), Color("36304e"))
	var _label_47: Label = _label(_canvas, "RESCÉNE RHYTHM   /   YOUR STAGE AWAITS", Rect2(62, 1055, 600, 20), 10, Color(0.7, 0.7, 0.85, 0.6))
	var _label_48: Label = _label(_canvas, "LOVE ATTACK   ·   INSTRUMENTAL", Rect2(_width - 420, 1055, 362, 20), 10, MUTED, FONT, HORIZONTAL_ALIGNMENT_RIGHT)


func _open_destination(destination: String) -> void:
	match destination:
		"SONGS": _open_songs()
		"CARDS", "COLLECTION": _open_collection()
		"ALBUMS": _open_section("Albums", "Every era, a different feeling.", "Your album library will live here as more songs are added.", "album")
		"RECORDS": _open_records()
		"MISSIONS": _open_progression()
		"SHOP": _open_marketplace()
		"INVENTORY": _open_inventory()

func _open_collection(selected: String = "", archive: bool = false) -> void:
	if _profile_mode:
		_profile_mode = false
		_rebuild()
	_close_dialog()
	var collection: CollectionView = CollectionView.new()
	collection.host = self
	collection.selected_id = selected
	collection.archived = archive or selected.begins_with("legacy_")
	collection.size = _canvas.size
	_dialog = collection
	_canvas.add_child(collection)


func _open_inventory() -> void:
	_close_dialog()
	var inventory: InventoryView = InventoryView.new()
	inventory.host = self
	inventory.size = _canvas.size
	_dialog = inventory
	_canvas.add_child(inventory)


func _open_marketplace(saved: Dictionary = {}) -> void:
	_close_dialog()
	var market: MarketplaceView = MarketplaceView.new()
	market.host = self
	market.size = _canvas.size
	market.category = str(saved.get("category", "featured"))
	market.release_id = str(saved.get("release_id", ""))
	market.query = str(saved.get("query", ""))
	market.sort_index = StrictData.integer(saved.get("sort_index", 0))
	_dialog = market
	_canvas.add_child(market)
	if not saved.is_empty(): market.restore_detail(saved)


func _open_coop() -> void:
	_close_dialog()
	var view: CoopView = CoopView.new(); view.host = self; view.size = _canvas.size; _dialog = view; _canvas.add_child(view)

func _open_mastery(song: Dictionary) -> void:
	_close_dialog()
	var view: MasteryView = MasteryView.new()
	view.host = self; view.song = song; view.size = _canvas.size; _dialog = view; _canvas.add_child(view)

func _open_event() -> void:
	_close_dialog()
	_dialog = EventsView.new()
	_dialog.host = self
	_dialog.size = _canvas.size
	_canvas.add_child(_dialog)

func _open_event_song(song_id: String) -> void:
	_open_songs()
	for song: Dictionary in SongCatalog.SONGS:
		if str(song.id) == song_id:
			_song_view.select_song(song, true)
			break


func _open_records() -> void:
	_open_profile()
	_profile_view.set_tab("records")


func _open_leaderboard(song: Dictionary, difficulty: String) -> void:
	_close_dialog()
	_dialog = LeaderboardView.new()
	_dialog.host = self
	(_dialog as LeaderboardView).song = song
	(_dialog as LeaderboardView).difficulty = difficulty
	_dialog.size = _canvas.size
	_canvas.add_child(_dialog)


func _open_section(title: String, subtitle: String, body: String, icon_name: String) -> void:
	var window: Panel = _modal(title, subtitle)
	var _texturerect_50: TextureRect = _icon(window, icon_name, Rect2(43, 169, 46, 46))
	var description: Label = _label(window, body, Rect2(114, 165, 586, 152), 22, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var _button_51: Button = _button(window, "BACK TO HOME", Rect2(42, 370, 676, 64), _close_dialog)


func _open_songs() -> void:
	_close_dialog()
	_song_mode = true
	_music.stream_paused = true
	_rebuild()


func _back_from_songs() -> void:
	_song_mode = false
	_end_preview()
	_rebuild()


func _play_song_preview(song: Dictionary) -> void:
	if is_instance_valid(_stage) or _profile_mode:
		return
	var stream: AudioStreamMP3 = load(str(song.audio_path)) as AudioStreamMP3
	if stream == null:
		_end_preview()
		_toast("This audio file could not be opened.")
		return
	var audition: AudioStreamMP3 = stream.duplicate() as AudioStreamMP3
	audition.loop = false
	_preview.stop()
	_preview.stream = audition
	_music.stream_paused = true
	_preview_end_seconds = audition.get_length() * 0.5
	_preview.play(0.0)
	_preview_timer.start(_preview_end_seconds)


func _request_song_start(song: Dictionary, difficulty: String) -> void:
	if is_instance_valid(_stage):
		return
	_end_preview()
	_music.stream_paused = true
	_canvas.hide()
	_particles.hide()
	_stage = RhythmStage.new()
	_stage.host = self
	_stage.song = song
	_stage.difficulty = difficulty
	var _int_52: int = _stage.return_to_library.connect(_return_from_stage)
	_mount_stage()


func _mount_stage() -> void:
	if OS.has_feature("android") or force_mobile_gameplay_rendering:
		_stage_surface = MobileStageSurface.new()
		_stage_surface.name = "MobileGameplay"
		add_child(_stage_surface)
		_stage_surface.mount(_stage)
	else:
		add_child(_stage)


func _return_from_stage() -> void:
	if not is_instance_valid(_stage):
		return
	_stage.hide()
	_stage.set_process_input(false)
	_stage.set_process(false)
	if is_instance_valid(_stage.audio):
		_stage.audio.stop()
	_stage.queue_free()
	_stage = null
	if is_instance_valid(_stage_surface):
		_stage_surface.hide()
		_stage_surface.queue_free()
		_stage_surface = null
	_canvas.show()
	_particles.visible = _effects_on
	if is_instance_valid(_song_view):
		_song_view.refresh_records()
		_song_view.select_song(_song_view.selected, true)


func _open_profile() -> void:
	_close_dialog()
	if _profile_mode: return
	_profile_song_state = {}
	if is_instance_valid(_song_view):
		_profile_song_state = {"selected":_song_view.selected, "difficulty":_song_view.difficulty, "query":_song_view.query, "sort":_song_view.sort_index}
	_profile_mode = true
	_profile_tab = "info"
	_music.stream_paused = false
	_rebuild()
	# Read once on entry so a wallet completed after login can appear here.
	# No timer or automatic provisioning-status polling is started.
	if GameServices.session().is_authenticated(): GameServices.session().fetch_wallet.call_deferred()
	if GameServices.session().is_authenticated(): GameServices.scores().refresh.call_deferred()
	if GameServices.session().is_authenticated(): GameServices.photos().refresh.call_deferred()


func _close_profile() -> void:
	_close_dialog()
	_profile_mode = false
	_rebuild()
	if _song_mode and is_instance_valid(_song_view) and not _profile_song_state.is_empty():
		_song_view.query = _profile_song_state.query
		(_song_view.get_node("Search") as LineEdit).text = _profile_song_state.query
		_song_view.sort_index = _profile_song_state.sort
		(_song_view.get_node("Sort") as OptionButton).select(StrictData.integer(_profile_song_state.sort))
		_song_view.select_song(StrictData.dictionary(_profile_song_state.selected))
		_song_view._select_difficulty(str(_profile_song_state.difficulty))
		_song_view._filter_songs()
	_music.stream_paused = _song_mode


func _open_settings() -> void:
	var window: Panel = _modal("Set the mood", "SETTINGS")
	window.position.y = 260.0
	window.size.y = 560.0
	var _label_54: Label = _label(window, "MUSIC VOLUME", Rect2(42, 163, 500, 28), 16, WHITE, BOLD)
	var slider: HSlider = HSlider.new()
	slider.name = "MusicVolume"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = _music_level
	_at(window, slider, Rect2(42, 213, 676, 44))
	var _int_55: int = slider.value_changed.connect(func(value: float) -> void:
		_music_level = value
		_music.volume_linear = value * 0.28
		_preview.volume_linear = _music.volume_linear
		_save_profile()
	)
	var effects: CheckButton = CheckButton.new()
	effects.name = "ParticleEffects"
	effects.text = "PARTICLE EFFECTS"
	effects.button_pressed = _effects_on
	effects.add_theme_font_override("font", FONT)
	effects.add_theme_font_size_override("font_size", 19)
	_at(window, effects, Rect2(42, 283, 676, 62))
	var _int_56: int = effects.toggled.connect(func(value: bool) -> void:
		_effects_on = value
		_particles.visible = value
		GameServices.menu_touches().set_enabled(value)
		_save_profile()
	)
	var haptics: CheckButton = CheckButton.new()
	haptics.name = "MissVibration"
	haptics.text = "MISS VIBRATION"
	haptics.button_pressed = _haptics_on
	haptics.add_theme_font_override("font", FONT)
	haptics.add_theme_font_size_override("font_size", 19)
	_at(window, haptics, Rect2(42, 351, 676, 62))
	var _haptics_changed: int = haptics.toggled.connect(func(value: bool) -> void:
		_haptics_on = value
		_save_profile()
	)
	var _updates_button: Button = _button(window, "CHECK FOR UPDATES", Rect2(42, 448, 330, 64), func() -> void:
		var _view: AppUpdateView = AppUpdateView.open(self)
	, true)
	var _button_57: Button = _button(window, "DONE", Rect2(388, 448, 330, 64), _close_dialog, true)


func _modal(title: String, subtitle: String) -> Panel:
	_close_dialog()
	_dialog = MenuDestination.new()
	_dialog.name = "Dialog"
	_canvas.add_child(_dialog)
	_dialog.size = _canvas.size
	var scrim: Button = _button(_dialog, "", Rect2(Vector2.ZERO, _canvas.size), _close_dialog, false, false)
	scrim.add_theme_stylebox_override("normal", _style(Color(0.025, 0.03, 0.075, 0.82), Color.TRANSPARENT, 0))
	scrim.add_theme_stylebox_override("hover", scrim.get_theme_stylebox("normal"))
	scrim.add_theme_stylebox_override("pressed", scrim.get_theme_stylebox("normal"))
	var window: Panel = _panel(_dialog, Rect2(_width * 0.5 - 380, 294, 760, 474), Color("16182d"), Color(0.76, 0.71, 1, 0.65), 28)
	window.name = "Window"
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	var _label_58: Label = _label(window, title, Rect2(42, 32, 630, 58), 36, WHITE, SERIF)
	var _label_59: Label = _label(window, subtitle, Rect2(44, 101, 660, 27), 13, LILAC, BOLD)
	var _button_60: Button = _icon_button(window, "close", Rect2(668, 14, 72, 72), _close_dialog)
	return window


func _close_dialog() -> void:
	_end_preview()
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _end_preview() -> void:
	if is_instance_valid(_preview_timer):
		_preview_timer.stop()
	if is_instance_valid(_preview):
		_preview.stop()
	if is_instance_valid(_music):
		_music.stream_paused = _song_mode
	if is_instance_valid(_song_view):
		_song_view.preview_finished()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_stage):
		return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_dialog):
		_dialog.go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _profile_mode:
		_profile_view.go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _song_mode:
		_back_from_songs()
		get_viewport().set_input_as_handled()


func _toast(message: String) -> void:
	var label: Label = _label(_canvas, message, Rect2(_width * 0.5 - 280, 170, 560, 50), 20, WHITE, BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var tween: Tween = create_tween()
	var _intervaltweener_61: IntervalTweener = tween.tween_interval(1.8)
	var _propertytweener_62: PropertyTweener = tween.tween_property(label, "modulate:a", 0.0, 0.4)
	var _callbacktweener_63: CallbackTweener = tween.tween_callback(label.queue_free)


func _load_profile() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		_profile_name = config.get_value("player", "name", "RE:PLAYER")
		_music_level = clampf(StrictData.number(config.get_value("settings", "music", 0.7)), 0.0, 1.0)
		_effects_on = config.get_value("settings", "particles", true)
		_haptics_on = StrictData.boolean(config.get_value("settings", "haptics", true))
		_selected_member = clampi(StrictData.integer(config.get_value("settings", "member", 0)), 0, 4)


func _save_profile() -> void:
	var config: ConfigFile = ConfigFile.new()
	var _error_64: Error = config.load(PROFILE_PATH)
	if not GameServices.session().is_authenticated():
		config.set_value("player", "name", _profile_name)
	config.set_value("settings", "music", _music_level)
	config.set_value("settings", "particles", _effects_on)
	config.set_value("settings", "haptics", _haptics_on)
	config.set_value("settings", "member", _selected_member)
	var _error_65: Error = config.save(PROFILE_PATH)


func _on_session_ended(_message: String) -> void:
	# Remove gameplay/audio together when the account session ends.
	set_process(false)
	if is_instance_valid(_music): _music.stop()
	if is_instance_valid(_preview): _preview.stop()
	if is_instance_valid(_stage): _stage.set_process(false)
	get_tree().change_scene_to_file.call_deferred("res://scenes/auth_screen.tscn")


func _portrait(index: int) -> AtlasTexture:
	var texture: AtlasTexture = AtlasTexture.new()
	texture.atlas = ART
	var centers: Array[float] = [0.306, 0.393, 0.488, 0.578, 0.668]
	var dimensions: Vector2 = ART.get_size()
	texture.region = Rect2(StrictData.number((centers[index] - 0.038) * dimensions.x), 0.505 * dimensions.y, 0.076 * dimensions.x, 0.23 * dimensions.y)
	return texture


func _at(parent: Node, node: Control, rect: Rect2) -> void:
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	if not node is BaseButton and not node is Range and not node is LineEdit:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(parent: Node, text: String, rect: Rect2, font_size: int = 20, color: Color = WHITE, font: Font = FONT, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.025, 0.025, 0.07, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = alignment
	_at(parent, label, rect)
	return label


func _style(background: Color, border: Color, radius: int = 16) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	# The 2400-wide canvas is displayed at 2/3 scale in the desktop preview.
	# Keep borders above one display pixel and give curves a full pixel AA fringe.
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.corner_detail = 16
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.5
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style


func _panel(parent: Node, rect: Rect2, background: Color, border: Color, radius: int = 16) -> Panel:
	var panel: Panel = Panel.new()
	panel.add_theme_stylebox_override("panel", _style(background, border, radius))
	_at(parent, panel, rect)
	return panel


func _button(parent: Node, text: String, rect: Rect2, action: Callable, primary: bool = false, glass: bool = true) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", INK if primary else WHITE)
	var background: Color = Color(0.09, 0.10, 0.21, 0.66) if glass else Color.TRANSPARENT
	var border: Color = Color(0.78, 0.76, 1, 0.24) if glass else Color.TRANSPARENT
	if primary:
		background = Color("d8ceff")
		border = Color("f0eaff")
	button.add_theme_stylebox_override("normal", _style(background, border, 18))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.14), LILAC, 18))
	button.add_theme_stylebox_override("pressed", _style(background.darkened(0.12), WHITE, 18))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, WHITE, 18))
	_at(parent, button, rect)
	var _int_66: int = button.pressed.connect(action)
	return button


func _icon(parent: Node, icon_name: String, rect: Rect2, tint: Color = WHITE) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = load("res://assets/ui/" + icon_name + ".svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	_at(parent, icon, rect)
	return icon


func _icon_button(parent: Node, icon_name: String, rect: Rect2, action: Callable) -> Button:
	var button: Button = _button(parent, "", rect, action, false, false)
	var _texturerect_67: TextureRect = _icon(button, icon_name, Rect2((rect.size - Vector2(30, 30)) * 0.5, Vector2(30, 30)))
	button.tooltip_text = icon_name.capitalize()
	return button


func _line(parent: Node, rect: Rect2, color: Color) -> void:
	var line: ColorRect = ColorRect.new()
	line.color = color
	_at(parent, line, rect)

func _open_challenges(peer: Dictionary = {}, saved: Dictionary = {}) -> void:
	_close_dialog()
	var view: ChallengesView = ChallengesView.new(); view.host = self; view.peer = peer; view._saved = saved; view.size = _canvas.size; _dialog = view; _canvas.add_child(view)

func _social_notification(kind: String, _peer_id: String) -> void:
	if is_instance_valid(_stage): return
	var previous: Node = get_node_or_null("SocialNotification")
	if previous != null: previous.queue_free()
	var layer: CanvasLayer = CanvasLayer.new(); layer.name = "SocialNotification"; layer.layer = 20; add_child(layer)
	var notice: Button = Button.new(); notice.text = "New song challenge  →" if kind == "challenge" else "Weekly duet updated  →" if kind == "duet" else "New message  →"
	notice.position = Vector2(size.x - 360, 85); notice.size = Vector2(325, 58)
	notice.add_theme_stylebox_override("normal", _style(Color("302841"), LILAC, 14)); notice.add_theme_color_override("font_color", WHITE)
	layer.add_child(notice)
	var _clicked: int = notice.pressed.connect(func() -> void:
		layer.queue_free()
		if kind == "challenge": _open_challenges()
		elif kind == "duet": _open_coop()
		else: _open_social({}, "messages"))
	var _expire: int = get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if is_instance_valid(layer): layer.queue_free())

func _offer_tutorial() -> void:
	var window: Panel = _modal("Your first scene", "LEARN THE RHYTHM")
	var _hint: Label = _label(window, "Learn taps, holds, curves, momentum and cards.\nA guided minute to find your rhythm.", Rect2(42, 150, 636, 110), 24, LILAC)
	var _start: Button = _button(window, "START TUTORIAL", Rect2(42, 300, 636, 72), _start_tutorial, true)
	var _later: Button = _button(window, "SKIP FOR NOW", Rect2(42, 394, 636, 62), func() -> void: FirstPlay.mark_seen(); _close_dialog())

func _start_tutorial() -> void:
	if is_instance_valid(_stage): return
	_close_dialog(); _end_preview(); _music.stream_paused = true; _canvas.hide(); _particles.hide()
	_stage = RhythmStage.new(); _stage.host = self; _stage.song = SongCatalog.SONGS[0]
	for song: Dictionary in SongCatalog.SONGS:
		if str(song.title) == "With": _stage.song = song
	_stage.difficulty = "Tutorial"; _stage.tutorial_mode = true
	var _back: int = _stage.return_to_library.connect(_return_from_stage)
	_mount_stage()
