class_name SocialView
extends MenuDestination
var tab: String = "friends"
var query: String = ""
var selected: Dictionary = {}
var challenge_seed: Dictionary = {}
var _drafts: Dictionary[String, String] = {}
var _search: LineEdit
var _people_scroll: ScrollContainer
var _people_list: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_list: VBoxContainer
var _composer: LineEdit
var _send: Button
var _status: Label
var _chat_status: Label
var _counts: Label
var _public_view: PlayerProfile
var _sending: bool = false
var _action_busy: bool = false
var _rendered_messages: String = ""

func _ready() -> void:
	name = "SocialView"; mouse_filter = Control.MOUSE_FILTER_STOP
	var service: SocialService = GameServices.social()
	service.active_view = get_instance_id()
	var _changed: int = service.changed.connect(_summary_changed)
	var _people: int = service.people_changed.connect(_render_people)
	var _thread: int = service.conversation_changed.connect(func(peer_id: String, older: bool) -> void:
		if peer_id == str(selected.get("id", "")):
			selected = service.peers.get(peer_id, selected); _sync_chat(); _render_messages.call_deferred(older))
	var _sent: int = service.message_sent.connect(func(peer_id: String, text: String) -> void:
		if peer_id == str(selected.get("id", "")) and is_instance_valid(_composer) and _composer.text.strip_edges() == text:
			_composer.clear(); _drafts[peer_id] = "")
	var _typing: int = service.typing_changed.connect(func(peer_id: String) -> void:
		if peer_id == str(selected.get("id", "")): _sync_chat())
	_render()
	_load_tab()
	service.refresh.call_deferred()
	if not selected.is_empty(): _select(selected)

func _exit_tree() -> void:
	if GameServices.social().active_view == get_instance_id():
		GameServices.social().active_peer = ""; GameServices.social().active_view = 0

func snapshot() -> Dictionary:
	if is_instance_valid(_composer) and not selected.is_empty(): _drafts[str(selected.get("id", ""))] = _composer.text
	return {"tab":tab,"query":query,"selected":selected.duplicate(true),"drafts":_drafts.duplicate(),"challenge_seed":challenge_seed.duplicate()}

func restore(saved: Dictionary) -> void:
	challenge_seed = StrictData.dictionary(saved.get("challenge_seed",{}))
	tab = str(saved.get("tab", "friends")); query = str(saved.get("query", "")); selected = StrictData.dictionary(saved.get("selected", {}))
	for key: Variant in StrictData.dictionary(saved.get("drafts", {})): _drafts[str(key)] = str(StrictData.dictionary(saved.drafts)[key])

func _render() -> void:
	if is_instance_valid(body): body.hide(); body.queue_free()
	body = Control.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(body)
	var _frame: Panel = host._panel(body, Rect2(32, 158, host._width - 64, 889), Color(0.055, 0.05, 0.105, 0.97), Color(host.LILAC, 0.35), 24)
	var _back: Button = host._button(body, "‹", Rect2(55, 185, 65, 62), go_back)
	var _title: Label = host._label(body, "YOUR PEOPLE", Rect2(143, 188, 700, 45), 33, host.WHITE, host.BOLD)
	var _duet: Button = host._button(body,"WEEKLY DUET",Rect2(host._width - 635,197,270,62),host._open_coop)
	var _challenges: Button = host._button(body, "CHALLENGES", Rect2(host._width - 345, 197, 270, 62), func() -> void: host._open_challenges())
	_counts = host._label(body, "", Rect2(147, 247, 1200, 25), 14, host.LILAC, host.BOLD)
	var tabs: Array[String] = ["friends", "followers", "following", "messages", "search", "blocked"]
	for index: int in tabs.size():
		var destination: String = tabs[index]
		var button: Button = host._button(body, "FIND PLAYERS" if destination == "search" else destination.to_upper(), Rect2(62 + (index % 3) * 222, 295 + floori(float(index) / 3.0) * 61, 208, 50), func() -> void: tab = destination; _render(); _load_tab(), tab == destination, true, host.LILAC)
		button.name = "SocialTab_" + destination; button.add_theme_font_size_override("font_size", 15)
	_search = LineEdit.new(); _search.name = "PlayerSearch"; _search.placeholder_text = "Search username"; _search.text = query
	_search.add_theme_font_override("font", host.FONT); _search.add_theme_font_size_override("font_size", 19)
	_search.add_theme_stylebox_override("normal", host._style(Color("1c1a31"), Color(host.LILAC, 0.45), 14)); _search.add_theme_stylebox_override("focus", host._style(Color("1c1a31"), host.LILAC, 14))
	host._at(body, _search, Rect2(62, 424, 652, 53)); _search.visible = tab == "search"
	var _search_changed: int = _search.text_changed.connect(func(text: String) -> void: query = text)
	var _search_submit: int = _search.text_submitted.connect(func(_text: String) -> void: _load_tab())
	if tab == "search":
		_search.size.x = 488
		var _find: Button = host._button(body, "SEARCH", Rect2(565, 424, 149, 53), _load_tab)
	else:
		var _caption: Label = host._label(body, "MUTUAL FOLLOWS BECOME FRIENDS" if tab == "friends" else "YOUR CONVERSATIONS" if tab == "messages" else tab.to_upper(), Rect2(65, 438, 650, 26), 13, host.MUTED, host.BOLD)
	_people_scroll = ScrollContainer.new(); _people_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host._at(body, _people_scroll, Rect2(62, 493, 652, 523)); _people_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_people_list = VBoxContainer.new(); _people_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _people_list.add_theme_constant_override("separation", 12); _people_scroll.add_child(_people_list)
	host._line(body, Rect2(746, 295, 1, 721), Color(host.LILAC, 0.17))
	_render_people(); _render_chat(); _summary_changed()

func _summary_changed() -> void:
	if is_instance_valid(_counts):
		var counts: Dictionary = StrictData.dictionary(GameServices.social().summary.get("counts", {}))
		_counts.text = "%d FRIENDS   /   %d FOLLOWERS   /   %d FOLLOWING" % [StrictData.integer(counts.get("friends", 0)), StrictData.integer(counts.get("followers", 0)), StrictData.integer(counts.get("following", 0))]
	if tab == "messages": _render_people()

func _load_tab() -> void:
	if tab == "messages": _render_people(); return
	if tab == "search" and query.strip_edges().length() < 3:
		GameServices.social().people.clear(); GameServices.social().message = "Search at least three username characters."; _render_people(); return
	GameServices.social().load_people.call_deferred(tab, query)

func _render_people() -> void:
	if not is_instance_valid(_people_list): return
	var previous_scroll: int = _people_scroll.scroll_vertical
	for child: Node in _people_list.get_children():
		if child is Control: (child as Control).hide()
		child.queue_free()
	var service: SocialService = GameServices.social()
	var values: Array = service.people
	if tab == "messages": values = StrictData.array(service.summary.get("conversations", []))
	if values.is_empty():
		var label: Label = Label.new(); label.text = "Finding your people…" if service.loading_people else service.message if not service.message.is_empty() else "Your conversations will appear here." if tab == "messages" else "No players here yet. Find someone and follow them."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_override("font", host.FONT); label.add_theme_font_size_override("font_size", 21); label.add_theme_color_override("font_color", host.MUTED); _people_list.add_child(label)
	for raw: Variant in values:
		var data: Dictionary = StrictData.dictionary(raw)
		var peer: Dictionary = StrictData.dictionary(data.get("peer", {})) if tab == "messages" else data
		var row: Control = Control.new(); row.custom_minimum_size = Vector2(0, 118); _people_list.add_child(row)
		var _panel: Panel = host._panel(row, Rect2(0, 0, 636, 118), Color(0.22, 0.19, 0.33, 0.65), Color(host.LILAC, 0.24), 17)
		_avatar(row, peer, Rect2(14, 19, 78, 78))
		var profile: Button = host._button(row, str(peer.get("username", "Player")), Rect2(105, 13, 365, 39), func() -> void: _select(peer), false, false)
		profile.name = "SocialPlayer_" + str(peer.get("id", "")); profile.alignment = HORIZONTAL_ALIGNMENT_LEFT; profile.add_theme_font_size_override("font_size", 22); profile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var caption: String = str(data.get("last_text", "")) if tab == "messages" else "ONLINE" if StrictData.boolean(peer.get("online", false)) else "FRIENDS" if StrictData.boolean(peer.get("friend", false)) else "FOLLOWS YOU" if StrictData.boolean(peer.get("follows_you", false)) else "FOLLOWING" if StrictData.boolean(peer.get("following", false)) else "PLAYER"
		var detail: Label = host._label(row, caption, Rect2(119, 68, 343, 29), 15, Color("b5e2d8") if StrictData.boolean(peer.get("online", false)) else host.MUTED)
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; detail.clip_text = true
		var is_friend: bool = StrictData.boolean(peer.get("friend", false))
		var button: Button = host._button(row, "UNBLOCK" if tab == "blocked" else "CHAT" if is_friend or tab == "messages" else "FOLLOWING" if StrictData.boolean(peer.get("following", false)) else "FOLLOW", Rect2(479, 27, 144, 57), func() -> void:
			if tab == "blocked": _action.call_deferred(peer, "block", false)
			elif is_friend or tab == "messages": _select(peer)
			else: _action.call_deferred(peer, "follow", not StrictData.boolean(peer.get("following", false))), is_friend)
		button.add_theme_font_size_override("font_size", 14); button.disabled = _action_busy
		if tab == "messages" and StrictData.integer(data.get("unread", 0)) > 0:
			var _unread: Label = host._label(row, str(StrictData.integer(data.unread)), Rect2(603, -3, 28, 22), 14, host.LILAC, host.BOLD)
	if not service.next_cursor.is_empty() and tab != "messages":
		var more: Button = Button.new(); more.text = "LOAD MORE"; more.custom_minimum_size.y = 52; _people_list.add_child(more)
		var _more: int = more.pressed.connect(func() -> void: service.load_people.call_deferred(tab, query, true))
	_people_scroll.set_deferred("scroll_vertical", previous_scroll)

func _avatar(parent: Node, peer: Dictionary, rect: Rect2) -> void:
	var panel: Panel = host._panel(parent, rect, Color(host.LILAC, 0.12), Color(host.LILAC, 0.4), 17)
	var _person: TextureRect = host._icon(panel, "person", Rect2(rect.size * 0.25, rect.size * 0.5), host.LILAC)
	var avatar: Dictionary = StrictData.dictionary(peer.get("avatar", {}))
	if not avatar.is_empty():
		var photo: ProfilePhoto = ProfilePhoto.new(); photo.path = str(avatar.get("url", "")); photo.radius = 14
		host._at(panel, photo, Rect2(Vector2(3, 3), rect.size - Vector2(6, 6)))

func _select(peer: Dictionary) -> void:
	selected = peer; _render_chat(); GameServices.social().open_chat(peer)

func _render_chat() -> void:
	for child: Node in body.get_children():
		if child.name == "ConversationPane":
			(child as Control).hide(); body.remove_child(child); child.queue_free()
	_composer = null; _chat_list = null; _chat_scroll = null
	_rendered_messages = ""
	var pane: Control = Control.new(); pane.name = "ConversationPane"; pane.mouse_filter = Control.MOUSE_FILTER_IGNORE; body.add_child(pane)
	if selected.is_empty():
		var _title: Label = host._label(pane, "Your people.\nYour moments.", Rect2(859, 466, host._width - 960, 178), 64, host.WHITE, host.SERIF)
		var _hint: Label = host._label(pane, "Follow each other to become friends.\nPick a player to open your conversation.", Rect2(865, 678, host._width - 980, 100), 24, host.LILAC)
		return
	var peer_id: String = str(selected.get("id", ""))
	_avatar(pane, selected, Rect2(791, 294, 80, 80))
	var _username: Label = host._label(pane, str(selected.get("username", "Player")), Rect2(895, 299, host._width - 1460, 44), 32, host.WHITE, host.BOLD)
	_chat_status = host._label(pane, "", Rect2(898, 349, host._width - 1450, 25), 14, host.LILAC)
	var _profile: Button = host._button(pane, "PROFILE", Rect2(host._width - 578, 304, 154, 51), _open_profile)
	var _follow: Button = host._button(pane, "UNFOLLOW" if StrictData.boolean(selected.get("following", false)) else "FOLLOW", Rect2(host._width - 411, 304, 164, 51), func() -> void: _action.call_deferred(selected, "follow", not StrictData.boolean(selected.get("following", false))))
	var _block: Button = host._button(pane, "UNBLOCK" if StrictData.boolean(selected.get("blocked_by_me", false)) else "BLOCK", Rect2(host._width - 234, 304, 160, 51), func() -> void: _action.call_deferred(selected, "block", not StrictData.boolean(selected.get("blocked_by_me", false))))
	var _report: Button = host._button(pane, "REPORT", Rect2(host._width - 234, 361, 160, 32), func() -> void: _report_target("player", ""))
	var challenge: Button = host._button(pane, "CHALLENGE", Rect2(host._width - 411, 361, 164, 32), func() -> void: host._open_challenges(selected,challenge_seed))
	challenge.disabled = not StrictData.boolean(selected.get("friend", false))
	_chat_scroll = ScrollContainer.new(); _chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host._at(pane, _chat_scroll, Rect2(791, 402, host._width - 870, 476)); _chat_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat_list = VBoxContainer.new(); _chat_list.add_theme_constant_override("separation", 16); _chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _chat_scroll.add_child(_chat_list)
	var _composer_frame: Panel = host._panel(pane, Rect2(791, 903, host._width - 870, 111), Color("1d1930"), Color(host.LILAC, 0.32), 18)
	_composer = LineEdit.new(); _composer.name = "ChatMessage"; _composer.max_length = 500; _composer.text = _drafts.get(peer_id, "")
	_composer.add_theme_font_override("font", host.FONT); _composer.add_theme_font_size_override("font_size", 23)
	_composer.add_theme_stylebox_override("normal", host._style(Color.TRANSPARENT, Color.TRANSPARENT, 8)); _composer.add_theme_stylebox_override("focus", host._style(Color.TRANSPARENT, Color(host.LILAC, 0.5), 8))
	host._at(pane, _composer, Rect2(809, 919, host._width - 1088, 62))
	_send = host._button(pane, "SEND", Rect2(host._width - 237, 925, 142, 62), func() -> void: _send_text.call_deferred(), true); _send.name = "SendMessage"
	_send.add_theme_stylebox_override("disabled", host._style(Color("302841"), Color(host.LILAC, 0.18), 18))
	_send.add_theme_color_override("font_disabled_color", host.MUTED)
	_status = host._label(pane, "", Rect2(805, 1018, host._width - 900, 23), 13, host.MUTED)
	var _text: int = _composer.text_changed.connect(func(text: String) -> void: _drafts[peer_id] = text; _sync_chat(); GameServices.social().send_typing.call_deferred(peer_id))
	var _submit: int = _composer.text_submitted.connect(func(_submitted_value: String) -> void: _send_text.call_deferred())
	_sync_chat(); _render_messages.call_deferred(false)

func _sync_chat() -> void:
	if not is_instance_valid(_composer): return
	var can_chat: bool = StrictData.boolean(selected.get("can_chat", false))
	_composer.editable = can_chat and not _sending
	_composer.placeholder_text = "Message " + str(selected.get("username", "Player")) if can_chat else "Follow each other to chat"
	_send.disabled = not can_chat or _sending or _composer.text.strip_edges().is_empty()
	_chat_status.text = "ONLINE  ·  FRIEND" if StrictData.boolean(selected.get("online", false)) else "FRIEND  ·  OFFLINE" if can_chat else "FOLLOW EACH OTHER TO CHAT"
	if GameServices.social().typing_until.has(str(selected.get("id", ""))): _chat_status.text = "Typing…"
	_status.text = GameServices.social().message

func _render_messages(older: bool) -> void:
	if not is_instance_valid(_chat_list) or selected.is_empty(): return
	var peer_id: String = str(selected.get("id", ""))
	var service: SocialService = GameServices.social()
	var values: Array = service.messages.get(peer_id, [])
	var signature: String = "%s/%d/%d/%d/%s" % [peer_id, values.size(), StrictData.integer(StrictData.dictionary(values.front()).get("seq", 0)) if not values.is_empty() else 0, StrictData.integer(StrictData.dictionary(values.back()).get("seq", 0)) if not values.is_empty() else 0, str(selected.get("can_chat", false))]
	if signature == _rendered_messages: return
	_rendered_messages = signature
	var bar: VScrollBar = _chat_scroll.get_v_scroll_bar()
	var previous: int = _chat_scroll.scroll_vertical
	var old_height: float = bar.max_value
	var bottom: bool = float(previous) >= bar.max_value - bar.page - 65.0
	for child: Node in _chat_list.get_children():
		if child is Control: (child as Control).hide()
		child.queue_free()
	if service.has_older.get(peer_id, false):
		var earlier: Button = Button.new(); earlier.text = "LOAD EARLIER MESSAGES"; earlier.custom_minimum_size.y = 48; _chat_list.add_child(earlier)
		var _earlier: int = earlier.pressed.connect(func() -> void: service.poll_thread.call_deferred(peer_id, true))
	if values.is_empty():
		var empty: Label = Label.new(); empty.text = "Say hello. Your conversation starts here." if StrictData.boolean(selected.get("can_chat", false)) else "Follow each other to start a private conversation."; empty.add_theme_font_override("font", host.FONT); empty.add_theme_font_size_override("font_size", 22); empty.add_theme_color_override("font_color", host.MUTED); _chat_list.add_child(empty)
	for raw: Variant in values:
		var item: Dictionary = StrictData.dictionary(raw)
		var own: bool = str(item.get("sender_id", "")) == str(GameServices.session().user.get("id", ""))
		var row: HBoxContainer = HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _chat_list.add_child(row)
		var spacer: Control = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if own: row.add_child(spacer)
		var bubble: PanelContainer = PanelContainer.new()
		var bubble_width: float = minf((host._width - 930) * 0.77, maxf(280.0, float(str(item.get("text", "")).length()) * 12.0))
		bubble.custom_minimum_size.x = bubble_width
		var style: StyleBoxFlat = host._style(Color("c9bcf4") if own else Color("2c2542"), Color(host.LILAC, 0.26), 17)
		style.content_margin_top = 17; style.content_margin_bottom = 14; style.content_margin_left = 20; style.content_margin_right = 20
		bubble.add_theme_stylebox_override("panel", style); row.add_child(bubble)
		var stack: VBoxContainer = VBoxContainer.new(); stack.add_theme_constant_override("separation", 10); bubble.add_child(stack)
		var text: Label = Label.new(); text.text = str(item.get("text", "")); text.custom_minimum_size.x = bubble_width - 40
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; text.add_theme_font_override("font", host.FONT); text.add_theme_font_size_override("font_size", 23); text.add_theme_color_override("font_color", host.INK if own else host.WHITE); stack.add_child(text)
		var time_label: Label = Label.new()
		var local_seconds: int = floori(StrictData.number(item.get("sent_at", 0)) / 1000.0) + StrictData.integer(Time.get_time_zone_from_system().get("bias", 0)) * 60
		time_label.text = Time.get_datetime_string_from_unix_time(local_seconds, true).left(16); time_label.add_theme_font_size_override("font_size", 12); time_label.add_theme_color_override("font_color", Color("4f456c") if own else host.MUTED); stack.add_child(time_label)
		if not own:
			var report: Button = Button.new(); report.text = "Report"; report.flat = true; report.alignment = HORIZONTAL_ALIGNMENT_LEFT; report.add_theme_font_size_override("font_size", 12); stack.add_child(report)
			var message_id: String = str(item.get("id", ""))
			var _reported: int = report.pressed.connect(func() -> void: _report_target("message", message_id))
			row.add_child(spacer)
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(_chat_scroll) or peer_id != str(selected.get("id", "")): return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(_chat_scroll): return
	_chat_scroll.scroll_vertical = previous + roundi(_chat_scroll.get_v_scroll_bar().max_value - old_height) if older else roundi(_chat_scroll.get_v_scroll_bar().max_value) if bottom else previous

func _send_text() -> void:
	if _sending or not is_instance_valid(_composer) or _send.disabled: return
	_sending = true; _sync_chat()
	var peer_id: String = str(selected.get("id", ""))
	var response: Dictionary = await GameServices.social().send_text(peer_id, _composer.text)
	if not is_inside_tree(): return
	_sending = false
	if not response.ok and is_instance_valid(_status): _status.text = str(response.get("message", "Could not send. Retry with Send."))
	_sync_chat()

func _action(peer: Dictionary, action: String, enabled: bool) -> void:
	if _action_busy: return
	_action_busy = true
	var response: Dictionary = await GameServices.social().player_action(str(peer.get("id", "")), action, enabled)
	if not is_inside_tree(): return
	_action_busy = false
	if response.ok and str(peer.get("id", "")) == str(selected.get("id", "")):
		selected = StrictData.dictionary(StrictData.dictionary(response.data).get("player", {})); _render_chat()
	_load_tab()

func _open_profile() -> void:
	var response: Dictionary = await GameServices.scores().player(str(selected.get("id", "")))
	if not is_inside_tree() or not response.ok: return
	if is_instance_valid(_public_view): _public_view.queue_free()
	_public_view = PlayerProfile.new(); _public_view.host = host; _public_view.public_data = StrictData.dictionary(StrictData.dictionary(response.data).get("profile", {}))
	add_child(_public_view); _public_view.size = size
	var _back: int = _public_view.return_requested.connect(func() -> void: _public_view.hide(); _public_view.queue_free(); _public_view = null)

func go_back() -> void:
	if is_instance_valid(_public_view): _public_view.go_back(); return
	host._close_dialog()

func _report_target(kind: String, target: String) -> void:
	var view: ReportView = ReportView.new(); view.host = host; view.player_id = str(selected.get("id", "")); view.target_type = kind; view.target_id = target; add_child(view)
