extends SceneTree
var failures: int = 0
var fixture: Dictionary = {}
var menu: ResceneMainMenu

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var file: FileAccess = FileAccess.open(OS.get_environment("RESCENE_SOCIAL_FIXTURE"), FileAccess.READ)
	fixture = StrictData.dictionary(JSON.parse_string(file.get_as_text())); file.close()
	var session: ResceneAuthSession = GameServices.session()
	var service: SocialService = GameServices.social()
	var response: Dictionary
	if OS.get_environment("RESCENE_SOCIAL_PHASE") == "restore": response = await session.restore_session()
	else: response = await session.authenticate("ReMine", "social-fixture-password")
	check(StrictData.boolean(response.ok), "Login to isolated social account")
	await service.pulse(); await service.refresh()
	var luna: Dictionary = StrictData.dictionary(StrictData.array(fixture.friends)[0])
	var luna_id: String = str(luna.id)
	if OS.get_environment("RESCENE_SOCIAL_PHASE") == "restore":
		await service.poll_thread(luna_id)
		check(StrictData.array(service.messages.get(luna_id, [])).size() >= 6, "Chat history persists across API and game restart")
		session.logout()
		check(service.messages.is_empty() and service.people.is_empty() and service._pending.is_empty(), "Logout clears private social caches")
		print("Social chat history restart and account isolation: ", "PASS" if failures == 0 else "FAIL")
		quit(failures); return
	var online: Array = StrictData.array(service.summary.get("online_friends", []))
	check(online.size() == 5 and str(StrictData.dictionary(online[0]).get("id", "")) == luna_id, "Top five online friends prioritize a recent conversation")
	check(StrictData.integer(service.summary.get("unread", 0)) == 3, "Incoming messages have unread count")
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as ResceneMainMenu
	root.add_child(menu); current_scene = menu
	await create_timer(0.6).timeout; menu._music.stop()
	var rail: OnlineFriendsRail = menu._canvas.find_child("OnlineFriends", true, false) as OnlineFriendsRail
	check(rail != null and rail.find_child("OnlineFriend_4", true, false) != null and rail.find_child("OnlineFriend_5", true, false) == null, "Rail renders exactly five actual friends")
	check(menu._social_badge.visible, "Inbox has unread badge")
	await warm_photos(online)
	await capture("social-online-friends-20-9.png")
	(rail.find_child("OnlineFriend_0", true, false) as Button).pressed.emit()
	await settle()
	var view: SocialView = menu._dialog as SocialView
	check(view != null and str(view.selected.get("id", "")) == luna_id, "Friend avatar opens their conversation")
	await service.poll_thread(luna_id); await settle(); await service.refresh()
	check(StrictData.integer(service.summary.get("unread", 0)) == 0, "Viewing received messages marks them read")
	view._composer.text = "On my way! Let’s make it a full combo."
	view._sync_chat(); view._send.pressed.emit(); await settle()
	check(view._composer.text.is_empty() and service._pending.is_empty(), "Lost successful send response recovers without duplicating or losing draft")
	var count: int = 0
	for raw: Variant in service.messages.get(luna_id, []):
		if str(StrictData.dictionary(raw).get("text", "")) == "On my way! Let’s make it a full combo.": count += 1
	check(count == 1, "Message is present exactly once")
	response = await session._http("/api/v1/social/conversations/%s/messages" % str(fixture.owner), HTTPClient.METHOD_POST, {"request_id":Crypto.new().generate_random_bytes(16).hex_encode(),"text":"You got this! See you on the stage."}, str(luna.token))
	check(StrictData.boolean(response.ok), "Other friend sends a reply")
	await service.poll_thread(luna_id); await settle()
	check(StrictData.array(service.messages.get(luna_id, [])).size() == 6, "Reply arrives through live chat polling")
	await capture("social-chat-20-9.png")
	view._composer.text = "A draft worth keeping"; view._sync_chat()
	menu._rebuild(); await settle(); view = menu._dialog as SocialView
	check(view != null and view._composer.text == "A draft worth keeping" and service.active_peer == luna_id, "Resize preserves chat, draft and active polling")
	view.tab = "followers"; view._render(); await service.load_people("followers"); await settle()
	check(service.people.size() == 7, "Follower list includes one-way followers")
	await capture("social-followers-20-9.png")
	view.tab = "search"; view.query = "New"; view._render(); await service.load_people("search", "New"); await settle()
	check(service.people.size() == 1 and not StrictData.boolean(service.people[0].get("friend", true)), "Search finds a player outside friends")
	var new_peer: Dictionary = service.people[0]
	response = await service.player_action(str(new_peer.id), "follow", true)
	check(StrictData.boolean(response.ok) and StrictData.boolean(StrictData.dictionary(StrictData.dictionary(response.data).get("player", {})).get("friend", false)), "Following back creates a friendship")
	response = await service.player_action(str(new_peer.id), "follow", false)
	check(StrictData.boolean(response.ok) and not StrictData.boolean(StrictData.dictionary(StrictData.dictionary(response.data).get("player", {})).get("friend", true)), "Unfollow ends mutual friendship")
	view._select(StrictData.dictionary(service.peers.get(luna_id, {}))); await settle()
	response = await service.player_action(luna_id, "block", true)
	check(StrictData.boolean(response.ok), "Block player")
	response = await service.send_text(luna_id, "Blocked message")
	check(not StrictData.boolean(response.ok) and StrictData.integer(response.get("status", 0)) == 403, "Server rejects messages after block")
	await service.load_people("blocked")
	check(service.people.size() == 1, "Blocked list allows managing player")
	response = await service.player_action(luna_id, "block", false)
	check(StrictData.boolean(response.ok), "Unblock player")
	response = await service.player_action(luna_id, "follow", true)
	response = await session._http("/api/v1/social/players/%s/follow" % str(fixture.owner), HTTPClient.METHOD_POST, {"enabled":true}, str(luna.token))
	check(StrictData.boolean(response.ok), "Both players choose to restore friendship after unblock")
	menu.queue_free(); await create_timer(0.25).timeout
	print("Native followers/following, top five online friends, private messages, reply polling, retry, resize and block: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func settle() -> void:
	await create_timer(0.12).timeout
	var deadline: int = Time.get_ticks_msec() + 12000
	var service: SocialService = GameServices.social()
	while (GameServices.session().busy or service._thread_running or service._summary_running or service._sending or service.loading_people) and Time.get_ticks_msec() < deadline: await process_frame
	await create_timer(0.15).timeout

func warm_photos(players: Array) -> void:
	var photos: ProfileMediaService = GameServices.photos()
	for raw: Variant in players:
		var peer: Dictionary = StrictData.dictionary(raw)
		var _texture: Texture2D = photos.texture(str(StrictData.dictionary(peer.get("avatar", {})).get("url", "")))
	var deadline: int = Time.get_ticks_msec() + 10000
	while not photos._fetching.is_empty() and Time.get_ticks_msec() < deadline: await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/" + filename)

func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
