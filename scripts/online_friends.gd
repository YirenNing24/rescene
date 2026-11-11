class_name OnlineFriendsRail
extends Control
var host: ResceneMainMenu
var _body: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _changed: int = GameServices.social().changed.connect(_render)
	_render()

func _render() -> void:
	if is_instance_valid(_body): _body.hide(); _body.queue_free()
	_body = Control.new(); _body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_body)
	var _frame: Panel = host._panel(_body, Rect2(0, 0, 112, 620), Color(0.08, 0.09, 0.19, 0.72), Color(host.LILAC, 0.28), 22)
	var friends: Array = StrictData.array(GameServices.social().summary.get("online_friends", []))
	var heading: Button = host._button(_body, "FRIENDS", Rect2(4, 10, 104, 31), func() -> void: host._open_social(), false, false)
	heading.add_theme_font_size_override("font_size", 12)
	var _online: Label = host._label(_body, "%d ONLINE" % friends.size(), Rect2(0, 44, 112, 22), 10, Color("b5e2d8"), host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var unread: Dictionary[String, int] = {}
	for raw: Variant in StrictData.array(GameServices.social().summary.get("conversations", [])):
		var thread: Dictionary = StrictData.dictionary(raw)
		unread[str(StrictData.dictionary(thread.get("peer", {})).get("id", ""))] = StrictData.integer(thread.get("unread", 0))
	for index: int in mini(5, friends.size()):
		var peer: Dictionary = StrictData.dictionary(friends[index])
		var button: Button = host._button(_body, "", Rect2(14, 81 + index * 94, 84, 85), func() -> void: host._open_social(peer))
		button.name = "OnlineFriend_%d" % index; button.tooltip_text = str(peer.get("username", "Player")) + " · Online · Chat"
		var _person: TextureRect = host._icon(button, "person", Rect2(21, 12, 42, 43), host.LILAC)
		var avatar: Dictionary = StrictData.dictionary(peer.get("avatar", {}))
		if not avatar.is_empty():
			var photo: ProfilePhoto = ProfilePhoto.new(); photo.path = str(avatar.get("url", "")); photo.radius = 12
			host._at(button, photo, Rect2(4, 4, 76, 60))
		var label: Label = host._label(button, str(peer.get("username", "Player")), Rect2(4, 64, 76, 18), 10, host.WHITE, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; label.clip_text = true
		var _dot: Panel = host._panel(button, Rect2(65, 48, 13, 13), Color("a5dfcc"), Color("202039"), 7)
		var count: int = unread.get(str(peer.get("id", "")), 0)
		if count > 0:
			var badge: Panel = host._panel(button, Rect2(63, -7, 27, 27), host.LILAC, Color.TRANSPARENT, 14)
			var _badge_text: Label = host._label(badge, str(mini(count, 99)), Rect2(0, 4, 27, 20), 12, host.INK, host.BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	if friends.is_empty():
		var _empty: Label = host._label(_body, "Your people,\nyour rhythm.\n\nNo friends\nonline yet.", Rect2(8, 199, 96, 160), 12, host.MUTED, host.FONT, HORIZONTAL_ALIGNMENT_CENTER)
	var add: Button = host._button(_body, "+", Rect2(14, 565, 84, 42), func() -> void: host._open_social({}, "search"))
	add.name = "FindFriends"; add.tooltip_text = "Find players and follow each other to become friends"
