extends SceneTree
## Disposable backend + mock Engine. The driver never creates real test wallets.
var failures: int = 0
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var session: ResceneAuthSession = root.get_node("AuthSession")
	if OS.get_environment("RESCENE_AUTH_FILE").is_empty():
		push_error("Wallet test needs an isolated RESCENE_AUTH_FILE")
		quit(1)
		return
	var username: String = "wallet_" + str(Time.get_ticks_usec())
	var response: Dictionary = await session.authenticate(username,"test password!",true, true)
	check(StrictData.boolean(response.ok),"Registered user gets account session")
	if not response.ok:quit(1);return
	check(session.user.get("wallet") is Dictionary,"Registration exposes wallet setup status")
	var _error_1: Error = change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.3).timeout
	var menu: ResceneMainMenu = current_scene
	(menu._canvas.get_node("PlayerProfileButton") as Button).pressed.emit()
	check(menu._profile_mode and menu._profile_view.name == "PlayerProfile", "Avatar opens a full profile destination")
	check(not is_instance_valid(menu._dialog), "Player profile is not a modal")
	for step: int in 100:
		if str(StrictData.dictionary(session.user.get("wallet",{})).get("status",""))=="ready":break
		await session.fetch_wallet()
		await create_timer(0.1).timeout
	check(StrictData.boolean(session.user.wallet.status=="ready"),"Wallet becomes ready through our backend")
	var profile: PlayerProfile = menu._profile_view
	check(StrictData.boolean(profile._wallet_address.text==session.user.wallet.address),"Profile displays only the signed-in player's wallet")
	check(not profile._wallet_copy.disabled,"Ready address can be copied")
	check(profile.find_children("*", "Timer", true, false).is_empty(), "Profile has no wallet polling timer")
	check(StrictData.boolean((profile.body.find_child("ProfileUsername", true, false) as Label).text==username),"Profile shows the actual account name")
	profile._wallet_copy.pressed.emit()
	if DisplayServer.get_name()!="headless":
		check(StrictData.boolean(DisplayServer.clipboard_get()==session.user.wallet.address),"Copy action copies the full wallet address")
	check(profile._message.contains("copied"),"Copy action gives feedback")
	await screenshot("player-profile-20-9.png")
	(profile.body.get_node("Tab_wallet") as Button).pressed.emit()
	check(StrictData.boolean(profile.tab=="wallet" and profile._wallet_address.text==session.user.wallet.address),"Wallet navigation opens account wallet")
	await screenshot("player-wallet-20-9.png")
	profile.set_tab("records")
	check(is_instance_valid(profile.body.get_node_or_null("ExploreSongs")),"New player's records show an actionable empty state")

	RhythmRecords.save(SongCatalog.SONGS[0], "Hard", {"score":987650,"accuracy":98.765,"rank":"S","max_combo":123})
	profile.set_tab("records")
	var record_labels: Array[Node] = profile._scroll.find_children("*", "Label", true, false)
	var found_score: bool = false
	for label: Node in record_labels:
		if (label as Label).text=="0987650": found_score=true
	check(found_score,"Records page displays the signed-in player's saved personal best")
	await screenshot("player-records-20-9.png")
	profile.set_tab("unlocks")
	check(is_instance_valid(profile._scroll),"Unlocks page lists account cosmetics")
	var locked: Button = profile.body.find_child("Equip_frost",true,false)
	check(is_instance_valid(locked) and locked.disabled,"Locked cosmetics cannot be equipped")
	await screenshot("player-unlocks-20-9.png")
	menu.size=Vector2(1920,1080)
	await process_frame
	await process_frame
	profile=menu._profile_view
	check(profile.tab=="unlocks","Resize preserves the profile tab")
	check(StrictData.boolean((profile.body.get_node("MemberShowcase") as Control).get_rect().end.x<=profile.size.x),"Showcase remains in the resized canvas")
	menu.size=Vector2(2400,1080)
	await process_frame
	await process_frame
	profile=menu._profile_view
	profile.set_tab("info")
	var original: String = session.user.wallet.id
	response=await session.fetch_wallet(true)
	check(StrictData.boolean(response.ok and session.user.wallet.id==original),"Refresh keeps the same wallet")
	# Opening the profile from the library must restore the focused song and search.
	(profile.body.get_node("BackToMenu") as Button).pressed.emit()
	check(not menu._profile_mode and is_instance_valid(menu._canvas.get_node_or_null("PlayerProfileButton")),"Back restores the lobby")
	menu._open_songs()
	menu._song_view.select_song(SongCatalog.SONGS[3])
	menu._song_view._select_difficulty("Ultra Hard")
	(menu._song_view.get_node("Search") as LineEdit).text=SongCatalog.SONGS[3].title
	(menu._song_view.get_node("Search") as LineEdit).text_changed.emit(SongCatalog.SONGS[3].title)
	menu._open_profile()
	var escape: InputEventAction = InputEventAction.new()
	escape.action="ui_cancel"
	escape.pressed=true
	menu._unhandled_input(escape)
	check(menu._song_mode and not menu._profile_mode,"Escape returns to the originating library")
	check(StrictData.boolean(menu._song_view.selected.id==SongCatalog.SONGS[3].id and menu._song_view.difficulty=="Ultra Hard" and menu._song_view.query==SongCatalog.SONGS[3].title),"Profile preserves song, difficulty, and search")
	await process_frame
	await process_frame
	check(StrictData.boolean(menu._song_view.selected.id==SongCatalog.SONGS[3].id),"Deferred list focus preserves the restored selection")
	var _error_2: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(RhythmRecords.storage_path()))
	menu._open_profile()
	var saved_wallet: Dictionary=StrictData.dictionary(session.user.wallet).duplicate(true)
	session.user.wallet={}
	menu._profile_view.set_tab("wallet")
	check(menu._profile_view._wallet_address.text.is_empty() and menu._profile_view._wallet_copy.disabled,"Missing addresses never display or copy a stale wallet")
	session.user.wallet=saved_wallet
	menu._profile_view.set_tab("wallet")
	(menu._profile_view.body.get_node("LogOut") as Button).pressed.emit()
	await create_timer(0.3).timeout
	check(not session.is_authenticated(),"Logout clears wallet account state")
	response=await session.authenticate(username,"test password!")
	check(StrictData.boolean(response.ok),"Existing user can log in again")
	response=await session.fetch_wallet()
	check(StrictData.boolean(response.ok and session.user.wallet.id==original),"Login retains the same server wallet")
	session.logout()
	print("Wallet profile flow: ","PASS" if failures==0 else str(failures)+" FAILURES")
	if is_instance_valid(current_scene):current_scene.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func screenshot(filename: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var _error_3: Error = root.get_texture().get_image().save_png("res://previews/"+filename)

func check(condition: bool,message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
