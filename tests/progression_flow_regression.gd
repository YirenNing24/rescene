extends SceneTree
## Disposable API graph + external fixture driver; never touches a real account.
var failures: int = 0
var session: ResceneAuthSession
var progress: ProgressionService

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	session = root.get_node("AuthSession")
	progress = root.get_node("Progression")
	var auth_file: String = OS.get_environment("RESCENE_AUTH_FILE")
	var marker: String = OS.get_environment("RESCENE_PROGRESS_MARKER")
	if auth_file.is_empty() or marker.is_empty():
		push_error("Run with isolated RESCENE_AUTH_FILE and RESCENE_PROGRESS_MARKER fixtures.")
		quit(1)
		return
	var login: Dictionary = await session.authenticate("journey_" + str(Time.get_ticks_usec()), "test password!", true, true)
	check(StrictData.boolean(login.ok), "Register test account")
	if not login.ok: quit(1); return
	var _error_1: Error = change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.2).timeout
	await progress.refresh()
	for step: int in 150:
		if not progress.loading and not progress.state.is_empty(): break
		await create_timer(0.1).timeout
	var menu: ResceneMainMenu = current_scene
	check(StrictData.integer(progress.state.get("level",0)) == 1, "New account starts at level one")
	check(menu._energy_label.text == "15/15", "New accounts show the authoritative full energy balance")
	menu._open_destination("MISSIONS")
	check(menu._dialog.name == "ProgressionView", "Missions opens the actual journey screen")
	await process_frame
	check(StrictData.boolean(((menu._dialog as ProgressionView).body.get_node("ProgressionHint") as Label).get_line_count()>1), "Progression rules wrap inside the summary card")
	await screenshot("missions-new-20-9.png")
	menu._close_dialog()
	menu._open_songs()
	menu._request_song_start(SongCatalog.SONGS[0], "Easy")
	var stage: RhythmStage = menu._stage
	for step: int in 150:
		if stage.phase == "countdown" and not stage._progression_run.is_empty(): break
		await create_timer(0.1).timeout
	stage.set_process(false)
	check(not stage._progression_run.is_empty(), "Free Play acquires server run ticket")
	check(StrictData.integer(StrictData.dictionary(progress.state.energy).current) == 14, "Starting a song spends exactly one server energy")
	var run_id: String = stage._progression_run
	var file: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
	var _bool_2: bool = file.store_string(JSON.stringify({"user_id":session.user.id, "run_id":run_id}))
	file.close()
	# Driver ages only this disposable graph's ticket, avoiding a 100-second wait.
	for step: int in 150:
		if FileAccess.file_exists(marker + ".ready"): break
		await create_timer(0.1).timeout
	check(FileAccess.file_exists(marker + ".ready"), "External fixture advanced server clock")
	preload("res://tests/replay_fixture.gd").autoplay(stage.judge,stage.chart)
	stage.phase = "playing"
	stage.song_time = stage.chart.duration
	stage.finish_stage(false)
	for step: int in 150:
		if StrictData.integer(progress.state.get("clears",0)) == 1: break
		await create_timer(0.1).timeout
	check(StrictData.integer(progress.state.get("xp",0)) == 140, "A full clear awards actual server XP")
	check(StrictData.integer(progress.state.get("starlight",0)) == 60, "Clear Starlight appears in account")
	check(StrictData.boolean((stage._overlay as ResultsScreen)._reward_label.text.contains("140 PLAYER XP")), "Results display reward receipt")
	await screenshot("progression-results-20-9.png")
	# Duplicate completion must preserve the same account totals.
	await progress.finish_run(run_id,{"score":1000000,"max_combo":stage.judge.total_units,"counts":stage.judge.counts})
	check(StrictData.integer(progress.state.xp) == 140, "Duplicate receipt cannot award XP twice")
	stage.retry_stage()
	for step: int in 150:
		if stage.phase == "countdown" and not stage._progression_run.is_empty(): break
		await create_timer(0.1).timeout
	check(stage._progression_run != run_id, "Retry gets a new attempt ID")
	check(StrictData.integer(StrictData.dictionary(progress.state.energy).current) == 13, "Retry spends one energy for its new attempt")
	stage.finish_stage(true)
	check(StrictData.integer(progress.state.xp) == 140, "Failed attempt does not award XP")
	menu._return_from_stage()
	menu._open_progression()
	for mission: Dictionary in progress.state.missions:
		if mission.id == "first_clear": await (menu._dialog as ProgressionView)._claim(mission)
	for step: int in 150:
		if not (menu._dialog as ProgressionView)._busy: break
		await create_timer(0.1).timeout
	check(StrictData.boolean(StrictData.integer(progress.state.level)==2 and (menu._dialog as ProgressionView)._message.text.contains("CLAIMED")), "Mission UI claims real rewards and reaches level two")
	menu._close_dialog()
	var response: Dictionary = await progress.equip("rising_star")
	check(StrictData.boolean(response.ok and menu._level_label.text.contains("RISING STAR")), "Equipped title appears in lobby")
	for mission_id: String in ["daily_one","accuracy","full_combo"]:
		response = await progress.claim(mission_id,str(progress.state.day))
		check(StrictData.boolean(response.ok), "Claim earned mission: " + mission_id)
	check(StrictData.integer(progress.state.level)==3, "Mission XP unlocks level three frame")
	menu._open_profile()
	check(StrictData.integer(progress.state.get("best_accuracy",0))==10000 and StrictData.integer(progress.state.get("full_combos",0))==1,"Profile receives persisted accuracy and full-combo statistics")
	await screenshot("player-profile-progressed-20-9.png")
	menu._profile_view.set_tab("unlocks")
	var equip: Button = menu._profile_view.body.find_child("Equip_rose_mist",true,false)
	check(not equip.disabled,"Earned cosmetics are available in the profile")
	equip.pressed.emit()
	for step: int in 150:
		if not menu._profile_view._busy: break
		await create_timer(0.1).timeout
	check(progress.frame_color().is_equal_approx(Color("e3b5ce")), "Profile equips an unlocked frame through the server")
	menu._close_profile()
	check(menu._starlight_label.text == str(StrictData.integer(progress.state.starlight)), "HUD uses server Starlight balance")
	await (root.get_node("CloudScores") as CloudScoresService).refresh()
	check(StrictData.boolean(RECORDS_cloud_best(SongCatalog.SONGS[0].id).get("source", "")=="cloud"), "Validated clear restores from cloud records")
	menu._song_view.select_song(SongCatalog.SONGS[0])
	menu._song_view._select_difficulty("Easy")
	(menu._song_view._detail.get_node("Rankings") as Button).pressed.emit()
	var board: LeaderboardView = menu._dialog
	for step: int in 150:
		if not board.loading: break
		await create_timer(0.1).timeout
	check(StrictData.boolean(board.board.get("total",0)==1 and StrictData.dictionary(board.board.get("me",{})).get("position",0)==1),"Leaderboard displays the signed-in player's real rank")
	await screenshot("leaderboard-20-9.png")
	(board.body.get_node("NearMe") as Button).pressed.emit()
	check(board.view=="nearby","Near me opens adjacent ranks")
	board.difficulty="Hard"
	board.refresh.call_deferred()
	await process_frame
	for step: int in 150:
		if not board.loading: break
		await create_timer(0.1).timeout
	check(StrictData.boolean(board.board.get("total",-1)==0 and board.board.get("me")==null),"An unplayed difficulty has its own empty ranking")
	await screenshot("leaderboard-empty-20-9.png")
	board.difficulty="Normal"
	board.refresh.call_deferred()
	await process_frame
	board.difficulty="Easy"
	board.refresh.call_deferred()
	await process_frame
	for step: int in 150:
		if not board.loading: break
		await create_timer(0.1).timeout
	check(StrictData.boolean(board.board.get("total",0)==1),"A stale difficulty response cannot replace the latest ranking")
	await board.open_player(str(session.user.id))
	for step: int in 150:
		if not board._opening_player: break
		await create_timer(0.1).timeout
	check(is_instance_valid(board._public_view),"A ranked player opens a full public profile")
	check(board._public_view.body.get_node_or_null("Tab_wallet")==null and board._public_view.body.get_node_or_null("LogOut")==null,"Public profiles hide private account controls")
	board._public_view.set_tab("records")
	await screenshot("ranked-player-profile-20-9.png")
	board.go_back()
	check(not is_instance_valid(board._public_view),"Back restores rankings from a public profile")
	board.go_back()
	menu._back_from_songs()
	menu._open_progression()
	await screenshot("missions-20-9.png")
	(menu._dialog as ProgressionView).tab = "unlocks"
	(menu._dialog as ProgressionView)._render()
	await screenshot("unlocks-20-9.png")
	menu._close_dialog()
	check(menu._energy_label.text == "13/15", "The lobby retains the server energy balance after results")
	menu._open_energy()
	check(menu._energy_detail_balance.text == "13/15" and menu._energy_detail_hint.text.begins_with("+1 IN"), "Energy details show balance and server-synced recovery countdown")
	await screenshot("energy-20-9.png")
	menu._close_dialog()
	menu._back_from_songs()
	await process_frame
	menu._daily_button.pressed.emit()
	for step: int in 150:
		if not progress.loading: break
		await create_timer(0.1).timeout
	check(menu._dialog.name=="DailyLoginView", "Daily Gifts opens the full calendar screen")
	check(StrictData.boolean(((menu._dialog as DailyLoginView).body.get_node("DailyGiftHint") as Label).get_line_count()>1), "Calendar explanation wraps inside its summary card")
	check(StrictData.boolean(StrictData.integer(progress.state.daily_login.next_day)==1 and not progress.state.daily_login.claimed_today), "Existing account starts with an available Day 1 gift")
	await screenshot("daily-gifts-20-9.png")
	var daily_date: String = str(progress.state.daily_login.date)
	var stars_before: int = StrictData.integer(progress.state.starlight)
	var gift_button: Button = ((menu._dialog as DailyLoginView).body.get_node("ClaimDailyGiftButton") as Button)
	check(not gift_button.disabled, "Today's gift can be claimed")
	gift_button.pressed.emit()
	for step: int in 150:
		if not (menu._dialog as DailyLoginView)._busy: break
		await create_timer(0.1).timeout
	check(StrictData.integer(progress.state.xp)==665 and StrictData.integer(progress.state.starlight)==stars_before+30, "Calendar button awards server XP and Starlight")
	check(StrictData.boolean(((menu._dialog as DailyLoginView).body.get_node("ClaimDailyGiftButton") as Button).disabled), "Claimed calendar disables another claim")
	check(StrictData.boolean(((menu._dialog as DailyLoginView).body.get_node("DailyGiftMessage") as Label).text.contains("COLLECTED")), "Calendar confirms the reward")
	check(menu._starlight_label.text==str(StrictData.integer(progress.state.starlight)), "Claim updates the lobby HUD immediately")
	response = await progress.claim_daily_login(daily_date,1)
	check(StrictData.boolean(response.ok and response.data.reward.already_claimed and StrictData.integer(progress.state.xp)==665), "A repeated claim recovers the receipt without awarding again")
	await screenshot("daily-gifts-claimed-20-9.png")
	# Day 7 appearance fixture only; the Go tests exercise real seven-day transitions.
	var actual: Dictionary = StrictData.dictionary(progress.state.daily_login).duplicate(true)
	progress.state.daily_login.completed = 6
	progress.state.daily_login.next_day = 7
	progress.state.daily_login.claimed_today = false
	(menu._dialog as DailyLoginView)._render()
	await screenshot("daily-gifts-day-seven-20-9.png")
	progress.state.daily_login = actual
	menu._close_dialog()
	menu._open_daily_login()
	for step: int in 150:
		if not progress.loading: break
		await create_timer(0.1).timeout
	check(StrictData.boolean(progress.state.daily_login.claimed_today and ((menu._dialog as DailyLoginView).body.get_node("ClaimDailyGiftButton") as Button).disabled), "Closing and reopening preserves today's claimed gift")
	menu._close_dialog()

	var _error_3: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(RhythmRecords.storage_path()))
	# Save non-secret expected values for a fresh-process restore assertion.
	file = FileAccess.open(marker + ".expected",FileAccess.WRITE)
	var _bool_4: bool = file.store_string(JSON.stringify({"xp":progress.state.xp,"title":progress.state.title,"frame":progress.state.frame}))
	file.close()
	print("Progression flow: ", "PASS" if failures==0 else str(failures) + " FAILURES")
	current_scene.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func RECORDS_cloud_best(song_id: String) -> Dictionary:
	return RhythmRecords.best(song_id,"Easy")

func screenshot(filename: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var _error_5: Error = root.get_texture().get_image().save_png("res://previews/"+filename)

func check(condition: bool,message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
