class_name ChallengesView
extends MenuDestination
var peer: Dictionary = {}
var _song: OptionButton
var _difficulty: OptionButton
var _list: VBoxContainer
var _status: Label
var _busy: bool = false
var _loading: bool = false
var _saved: Dictionary = {}
var _pending: Dictionary = {}

func _ready() -> void:
	name = "FriendChallenges"; mouse_filter = Control.MOUSE_FILTER_STOP
	body = Control.new(); add_child(body)
	var _frame: Panel = host._panel(body, Rect2(32, 158, host._width - 64, 889), Color("151324"), Color(host.LILAC, 0.35), 24)
	var _back: Button = host._button(body, "‹", Rect2(63, 190, 65, 62), go_back)
	var _title: Label = host._label(body, "FRIEND CHALLENGES", Rect2(154, 197, 1500, 49), 36, host.WHITE, host.BOLD)
	var hint: Label = host._label(body, "24 hours. Same chart. Best verified score wins; combo breaks ties. Each attempt costs 1 energy. Your equipped cards apply.", Rect2(72, 280, host._width - 150, 62), 20, host.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not peer.is_empty():
		var _to: Label = host._label(body, "CHALLENGE " + str(peer.get("username", "FRIEND")).to_upper(), Rect2(75, 370, 900, 32), 21, host.LILAC, host.BOLD)
		_song = OptionButton.new()
		for song: Dictionary in SongCatalog.SONGS: _song.add_item(str(song.title))
		host._at(body, _song, Rect2(72, 427, host._width - 900, 66))
		_difficulty = OptionButton.new()
		for difficulty: String in ["Easy", "Normal", "Hard", "Ultra Hard"]: _difficulty.add_item(difficulty)
		_difficulty.select(1); host._at(body, _difficulty, Rect2(host._width - 795, 427, 330, 66))
		var _create: Button = host._button(body, "SEND INVITE", Rect2(host._width - 442, 427, 365, 66), func() -> void: _create_challenge.call_deferred(), true)
	else:
		var _intro: Label = host._label(body, "Pick a mutual friend in Social to send a song challenge.", Rect2(75, 395, host._width - 150, 80), 30, host.LILAC, host.SERIF)
	_status = host._label(body, "", Rect2(75, 516, host._width - 150, 35), 19, host.LILAC)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host._at(body, scroll, Rect2(72, 576, host._width - 144, 422)); scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_list = VBoxContainer.new(); _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _list.add_theme_constant_override("separation", 15); scroll.add_child(_list)
	var _social_changed: int = GameServices.social().changed.connect(func() -> void: _refresh.call_deferred())
	if not _saved.is_empty():
		_pending = StrictData.dictionary(_saved.get("pending", {}))
		if is_instance_valid(_song): _song.select(StrictData.integer(_saved.get("song", 0))); _difficulty.select(StrictData.integer(_saved.get("difficulty", 1)))
	_refresh.call_deferred()

func _refresh() -> void:
	if _loading: return
	_loading = true
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/challenges")
	if not is_inside_tree(): return
	_loading = false
	if not response.ok: _status.text = str(response.get("message", "Could not load challenges.")); return
	for child: Node in _list.get_children(): _list.remove_child(child); child.queue_free()
	var values: Array = StrictData.array(StrictData.dictionary(response.data).get("challenges", []))
	if values.is_empty(): _status.text = "Your song challenges will appear here."
	for raw: Variant in values: _row(StrictData.dictionary(raw))

func _row(data: Dictionary) -> void:
	var row: Control = Control.new(); row.custom_minimum_size.y = 154; _list.add_child(row)
	var w: float = host._width - 168
	var _panel: Panel = host._panel(row, Rect2(0, 0, w, 154), Color("272139"), Color(host.LILAC, 0.24), 18)
	var outgoing: bool = str(data.get("sender", "")) == str(GameServices.session().user.get("id", ""))
	var opponent: String = str(data.get("recipient_name", "")) if outgoing else str(data.get("sender_name", ""))
	var _title: Label = host._label(row, str(data.get("title", "")) + "  /  " + str(data.get("difficulty", "")), Rect2(27, 17, w - 500, 39), 25, host.WHITE, host.BOLD)
	var status: String = str(data.get("status", "pending"))
	var scores: String = "%s  ·  %s  ·  %s : %s" % [opponent, status.to_upper(), _score(StrictData.integer(data.get("score_a", -1))), _score(StrictData.integer(data.get("score_b", -1)))]
	if status == "finished":
		var winner: String = str(data.get("winner", ""))
		scores += "  ·  " + ("DRAW" if winner == "tie" else "UNPLAYED" if winner == "unplayed" else "YOU WON" if winner == str(GameServices.session().user.get("id", "")) else "FRIEND WON")
	var _detail: Label = host._label(row, scores, Rect2(30, 77, w - 500, 30), 18, host.LILAC)
	if status in ["active", "pending"]:
		var left: int = maxi(0, ceili((StrictData.number(data.get("expires_at", 0)) / 1000.0 - Time.get_unix_time_from_system()) / 60.0))
		var _expires: Label = host._label(row, "%dh %dm remaining" % [floori(float(left) / 60.0), left % 60], Rect2(30, 119, w - 500, 24), 14, host.MUTED)
	if status == "pending":
		if not outgoing:
			var _accept: Button = host._button(row, "ACCEPT", Rect2(w - 430, 41, 190, 66), func() -> void: _action.call_deferred(str(data.id), "accept"), true)
		var _decline: Button = host._button(row, "CANCEL" if outgoing else "DECLINE", Rect2(w - 220, 41, 190, 66), func() -> void: _action.call_deferred(str(data.id), "cancel" if outgoing else "decline"))
	elif status == "active":
		var _play: Button = host._button(row, "PLAY SONG", Rect2(w - 320, 41, 290, 66), func() -> void: _play_song(data), true)

func _play_song(data: Dictionary) -> void:
	for song: Dictionary in SongCatalog.SONGS:
		if str(song.id) == str(data.song_id): host._request_song_start(song, str(data.difficulty)); return

func _score(value: int) -> String:
	return "—" if value < 0 else str(value)

func _create_challenge() -> void:
	if _busy: return
	if _pending.is_empty(): _pending = {"request_id":Crypto.new().generate_random_bytes(16).hex_encode(), "player_id":str(peer.get("id", "")), "song_id":str(SongCatalog.SONGS[_song.selected].id), "difficulty":_difficulty.get_item_text(_difficulty.selected)}
	_busy = true; _song.disabled = true; _difficulty.disabled = true
	var response: Dictionary = await GameServices.session()._send("/api/v1/challenges", HTTPClient.METHOD_POST, _pending)
	if not is_inside_tree(): return
	_busy = false
	if response.ok:
		_pending.clear(); _song.disabled = false; _difficulty.disabled = false; _status.text = "Invitation sent."; await _refresh()
	elif StrictData.integer(response.get("status", 0)) in [400,403,404,409,429]:
		_pending.clear(); _song.disabled = false; _difficulty.disabled = false; _status.text = str(response.get("message", "Could not send invitation."))
	else: _status.text = str(response.get("message", "Could not send invitation."))

func _action(id: String, action: String) -> void:
	if _busy: return
	_busy = true
	var response: Dictionary = await GameServices.session()._send("/api/v1/challenges/" + id.uri_encode(), HTTPClient.METHOD_POST, {"action":action})
	if not is_inside_tree(): return
	_busy = false
	if response.ok: await _refresh()
	else: _status.text = str(response.get("message", "Could not update challenge."))

func snapshot() -> Dictionary:
	return {"pending":_pending.duplicate(true), "song":_song.selected if is_instance_valid(_song) else 0, "difficulty":_difficulty.selected if is_instance_valid(_difficulty) else 1}
