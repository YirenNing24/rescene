class_name ResultsScreen
extends Control
## Full-screen stage results; shares the game's artwork, typography and palette.

const ART: CompressedTexture2D = preload("res://assets/art/rescene-main-menu.png")
const BACKDROP: Shader = preload("res://shaders/results_backdrop.gdshader")
const WHITE: Color = Color("f4f1ff")
const MUTED: Color = Color("a6a6bf")
const INK: Color = Color("202039")

var stage: RhythmStage
var data: Dictionary
var _accent: Color
var _score: Label
var _retry: Button
var _songs: Button
var _reward_label: Label
var _mastery_label: Label
var _completion_text: String = ""
var _run_id: String

func _ready() -> void:
	name = "ResultsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_accent = Color("d2b0c5") if data.failed else Color("c7bbff")
	_background()
	_header()
	_song_art()
	_scoreboard()
	_actions()
	_run_id = stage._progression_run
	var _int_1: int = GameServices.progression().run_rewarded.connect(_show_reward)
	var reward_text: String = "Clear a song to earn progression rewards." if data.failed else stage._reward_message
	if reward_text.is_empty(): reward_text = "Clear rewards require an account and an online run."
	_reward_label = stage.host._label(self, reward_text, Rect2(855, 896, 1437, 28), 17, _accent, stage.host.BOLD)
	modulate.a = 0.0
	var entrance: Tween = create_tween()
	var _propertytweener_2: PropertyTweener = entrance.tween_property(self, "modulate:a", 1.0, 0.32)
	var count_up: Tween = create_tween()
	var _methodtweener_3: MethodTweener = count_up.tween_method(_animate_score, 0.0, StrictData.number(data.score), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _background() -> void:
	var image: TextureRect = TextureRect.new()
	image.texture = ART
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = BACKDROP
	shader_material.set_shader_parameter("accent", _accent)
	image.material = shader_material
	stage.host._at(self, image, Rect2(0, 0, 2400, 1080))
	stage.host._line(self, Rect2(108, 274, 2184, 1), Color(_accent, 0.2))
	stage.host._line(self, Rect2(780, 321, 1, 532), Color(_accent, 0.15))

func _header() -> void:
	var host: ResceneMainMenu = stage.host
	var _label_4: Label = host._label(self, "R E S C É N E   /   S T A G E   R E S U L T S", Rect2(110, 54, 1250, 28), 17, _accent, host.BOLD)
	var _label_5: Label = host._label(self, host._profile_name, Rect2(1772, 54, 520, 28), 19, MUTED, host.FONT, HORIZONTAL_ALIGNMENT_RIGHT)
	var heading: String = "GAME OVER" if data.failed else "STAGE CLEAR"
	var _label_6: Label = host._label(self, heading, Rect2(102, 112, 1900, 112), 88, WHITE, host.BOLD)
	var message: String = "Take a breath. Your next scene is one tap away." if data.failed else "Every beat, a little closer to your scene."
	var _label_7: Label = host._label(self, message, Rect2(111, 231, 1730, 31), 20, MUTED, host.FONT)
	var status: String = "STAGE NOT CLEARED" if data.failed else "STAGE COMPLETE"
	_chip(status, Rect2(1955, 168, 337, 45), _accent)

func _song_art() -> void:
	var host: ResceneMainMenu = stage.host
	var _panel_8: Panel = host._panel(self, Rect2(107, 320, 506, 506), Color(0.7, 0.65, 0.9, 0.05), Color(_accent, 0.28), 3)
	var cover: TextureRect = TextureRect.new()
	cover.texture = load(str(stage.song.cover_path))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	host._at(self, cover, Rect2(120, 333, 480, 480))
	host._label(self, "RESCÉNE RHYTHM", Rect2(635, 328, 255, 26), 11, Color(_accent, 0.65), host.BOLD).rotation = PI * 0.5
	var title: Label = host._label(self,str(stage.song.title), Rect2(108, 851, 620, 57), 35, WHITE, host.BOLD)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size = Vector2(620, 57)
	var album: Label = host._label(self,str(stage.song.artist + "   /   " + stage.song.album), Rect2(111, 916, 605, 28), 18, MUTED, host.FONT)
	album.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	album.size = Vector2(605, 28)
	_chip(stage.difficulty.to_upper(), Rect2(110, 968, 211, 43), _accent)
	var _label_9: Label = host._label(self, "SHORT VERSION", Rect2(343, 977, 340, 27), 16, MUTED, host.BOLD)

func _scoreboard() -> void:
	var host: ResceneMainMenu = stage.host
	var _label_10: Label = host._label(self, "T O T A L   S C O R E", Rect2(852, 326, 720, 27), 18, _accent, host.BOLD)
	if data.new_best:
		_chip("FIRST CLEAR" if StrictData.dictionary(data.previous).is_empty() else "NEW PERSONAL BEST", Rect2(1650, 317, 340, 42), _accent)
	_score = host._label(self, "0000000", Rect2(842, 373, 1190, 134), 106, WHITE, host.BOLD)
	_score.name = "FinalScore"
	var best: String = "Complete this song to set a personal best."
	if not StrictData.dictionary(data.previous).is_empty(): best = "PERSONAL BEST   %07d" % StrictData.integer(data.previous.score)
	if data.new_best: best = "Your new personal best." if not StrictData.dictionary(data.previous).is_empty() else "Your first clear. Your first record."
	if not StrictData.dictionary(data.previous).is_empty() and not data.new_best:
		best = "%d POINTS TO YOUR BEST  ·  BEST %07d" % [maxi(0,StrictData.integer(data.previous.score)-StrictData.integer(data.score)),StrictData.integer(data.previous.score)]
	var last: Dictionary = StrictData.dictionary(data.get("last_attempt",{}))
	if not last.is_empty():
		var difference: int = StrictData.integer(data.score)-StrictData.integer(last.get("score",0))
		best += "   ·   %s%d VS LAST PLAY" % ["+" if difference >= 0 else "",difference]
	var _label_11: Label = host._label(self, best, Rect2(854, 514, 1235, 30), 18, MUTED, host.FONT)
	var card_line: String = "BASE  %07d   +   TEAM BONUS  %d" % [stage.judge.base_score(), stage.judge.score() - stage.judge.base_score()] if not stage.judge.card_loadout.is_empty() else ""
	var rival: Dictionary = StrictData.dictionary(data.get("rival",{}))
	if str(rival.get("kind","")) == "friend":
		var remaining: int = StrictData.integer(rival.score)-StrictData.integer(data.score)
		card_line += ("   ·   " if not card_line.is_empty() else "") + ("AHEAD OF " + str(rival.label).to_upper() if remaining < 0 else "TIED WITH " + str(rival.label).to_upper() if remaining == 0 else "%d TO %s" % [remaining,str(rival.label).to_upper()])
	var _card_line: Label = host._label(self,card_line,Rect2(854,548,1235,26),16,_accent,host.FONT)
	var seal: TextureRect = TextureRect.new()
	seal.texture = preload("res://assets/ui/result-medallion.svg")
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.modulate = _accent
	host._at(self, seal, Rect2(2061, 319, 234, 234))
	if data.failed:
		var retry_icon: TextureRect = host._icon(self, "retry", Rect2(2131, 378, 94, 94), _accent)
		retry_icon.name = "RetryEmblem"
		var _label_12: Label = host._label(self, "TRY AGAIN", Rect2(2080, 479, 198, 27), 16, _accent, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var _label_13: Label = host._label(self,str(data.rank), Rect2(2070, 361, 216, 127), 84, _accent, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		var _label_14: Label = host._label(self, "R A N K", Rect2(2080, 484, 198, 27), 16, MUTED, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	host._line(self, Rect2(854, 584, 1438, 1), Color(_accent, 0.2))
	_stat("ACCURACY", "%.2f%%" % data.accuracy, 854)
	_stat("MAX COMBO", str(data.max_combo), 1338)
	_stat("STAGE REACHED" if data.failed else "STAGE PLAYED", "%s / %s" % [RhythmStage._format_time(StrictData.number(data.played)), RhythmStage._format_time(StrictData.number(data.duration))], 1822, 35)
	_judgments()
	var progress_text: String = "%d%% OF THE STAGE" % roundi(StrictData.number(data.completion * 100.0))
	if not data.failed: progress_text = "ALL PERFECT" if data.counts.PERFECT == data.total_units else ("FULL COMBO" if data.counts.MISS == 0 else "THE STAGE IS YOURS")
	_completion_text = progress_text
	_mastery_label = host._label(self,progress_text+"   ·   NEXT: "+GameServices.progression().next_mastery(str(stage.song.id),stage.difficulty), Rect2(855, 864, 1130, 29), 18, _accent, host.BOLD)
	var _label_16: Label = host._label(self, "JUDGMENTS", Rect2(2058, 863, 234, 27), 14, MUTED, host.BOLD, HORIZONTAL_ALIGNMENT_RIGHT)

func _stat(caption: String, value: String, x: float, font_size: int = 49) -> void:
	var host: ResceneMainMenu = stage.host
	var _label_17: Label = host._label(self, caption, Rect2(x, 620, 430, 28), 18, MUTED, host.BOLD)
	var _label_18: Label = host._label(self, value, Rect2(x - 2, 662, 455, 68), font_size, WHITE, host.FONT)

func _judgments() -> void:
	var host: ResceneMainMenu = stage.host
	var colors: Array[Color] = [Color("a7c6d5"), Color("b4a2d8"), Color("cbb5c8"), Color("ca91aa")]
	var labels: Array[String] = ["PERFECT", "GREAT", "GOOD", "MISS"]
	var denominator: int = 0
	for count: int in StrictData.dictionary(data.counts).values(): denominator += StrictData.integer(count)
	var start: float = 855.0
	for index: int in 4:
		var label: String = labels[index]
		var width: float = 1437.0 * StrictData.integer(data.counts[label]) / maxi(1, denominator)
		if width > 0.0:
			host._line(self, Rect2(start, 754, width, 5), colors[index])
		start += width
		host._line(self, Rect2(855 + index * 364, 791, 3, 47), colors[index])
		var _label_19: Label = host._label(self, label, Rect2(873 + index * 364, 780, 200, 28), 17, MUTED, host.BOLD)
		var _label_20: Label = host._label(self, str(data.counts[label]), Rect2(872 + index * 364, 811, 275, 43), 29, colors[index], host.BOLD)

func _actions() -> void:
	var host: ResceneMainMenu = stage.host
	host._line(self, Rect2(854, 928, 1438, 1), Color(_accent, 0.2))
	_songs = host._button(self, "SONG SELECTION", Rect2(1326, 967, 440, 82), _to_songs)
	_songs.name = "Songs"
	_songs.add_theme_font_size_override("font_size", 21)
	_retry = host._button(self, "TRY AGAIN" if data.failed else "PLAY AGAIN", Rect2(1790, 967, 502, 82), _retry_stage, true)
	_retry.name = "Retry"
	_retry.add_theme_font_size_override("font_size", 25)
	_retry.add_theme_stylebox_override("normal", host._style(_accent, _accent.lightened(0.15), 18))
	_retry.add_theme_stylebox_override("hover", host._style(_accent.lightened(0.1), WHITE, 18))
	_retry.add_theme_stylebox_override("pressed", host._style(_accent.darkened(0.1), WHITE, 18))
	var _texturerect_21: TextureRect = host._icon(_retry, "retry", Rect2(416, 25, 32, 32), INK)
	var challenge: Button = host._button(self,"CHALLENGE A FRIEND",Rect2(855,967,440,82),_challenge_friend)
	challenge.disabled = data.failed or not GameServices.session().is_authenticated()
	_songs.focus_neighbor_right = _songs.get_path_to(_retry)
	_retry.focus_neighbor_left = _retry.get_path_to(_songs)

func _chip(text: String, rect: Rect2, tint: Color) -> void:
	var panel: Panel = stage.host._panel(self, rect, Color(tint, 0.07), Color(tint, 0.35), 10)
	var _label_23: Label = stage.host._label(panel, text, Rect2(8, 9, rect.size.x - 16, 27), 17, tint, stage.host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)

func _animate_score(value: float) -> void:
	_score.text = "%07d" % roundi(value)

func set_progression_message(message: String) -> void:
	_reward_label.text = message

func _show_reward(run_id: String, reward: Dictionary) -> void:
	if run_id != _run_id: return
	if reward.get("pending", false):
		set_progression_message("Rewards pending. They'll sync when you reconnect.")
		return
	if reward.has("error"):
		set_progression_message(str(reward.error))
		return
	var text: String = "+%d PLAYER XP  ·  +%d STARLIGHT" % [reward.xp,reward.starlight]
	if reward.first_clear: text += "  ·  FIRST CLEAR BONUS"
	if reward.level_after > reward.level_before: text += "  ·  LEVEL %d!" % StrictData.integer(reward.level_after)
	if not StrictData.array(reward.unlocks).is_empty(): text += "  ·  UNLOCKED: " + ", ".join(PackedStringArray(StrictData.array(reward.unlocks)))
	if reward.get("unranked_reason", "") == "paused": text += "  ·  UNRANKED: PAUSED RUN"
	set_progression_message(text)
	if is_instance_valid(_mastery_label): _mastery_label.text = _completion_text+"   ·   NEXT: "+GameServices.progression().next_mastery(str(stage.song.id),stage.difficulty)

func _retry_stage() -> void:
	stage.retry_stage()

func _to_songs() -> void:
	stage.return_to_library.emit()

func _challenge_friend() -> void:
	var menu: ResceneMainMenu = stage.host
	var challenge_setup: Dictionary = {"song":0,"difficulty":0}
	for index: int in SongCatalog.SONGS.size():
		if str(SongCatalog.SONGS[index].id) == str(stage.song.id): challenge_setup.song = index; break
	var difficulties: Array[String] = ["Easy","Normal","Hard","Ultra Hard"]
	challenge_setup.difficulty = maxi(0,difficulties.find(stage.difficulty))
	stage.return_to_library.emit()
	menu._open_social({},"friends",{},challenge_setup)
