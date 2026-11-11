extends SceneTree
## Disposable account: real HUD, charged starts, empty-energy gate and local-clock tampering.

var failures: int = 0
var menu: ResceneMainMenu
var progress: ProgressionService

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	if OS.get_environment("RESCENE_AUTH_FILE").is_empty() or OS.get_environment("RESCENE_PROGRESS_MARKER").is_empty():
		push_error("Run with tools/test_progression.py and its disposable account graph.")
		quit(1)
		return
	var session: ResceneAuthSession = GameServices.session()
	session.logout()
	await create_timer(0.2).timeout
	var response: Dictionary = await session.authenticate("energy_" + str(Time.get_ticks_usec()), "test password!", true, true)
	check(StrictData.boolean(response.ok), "Register energy fixture account")
	if not response.ok: quit(1); return
	progress = GameServices.progression()
	var scene_error: Error = change_scene_to_file("res://scenes/main_menu.tscn")
	check(scene_error == OK, "Open the actual lobby")
	await create_timer(0.2).timeout
	menu = current_scene
	await progress.refresh()
	check(menu._energy_label.text == "15/15" and menu._energy_hint.text == "FULL", "The lobby must show full server energy")
	menu._open_songs()
	menu._request_song_start(SongCatalog.SONGS[0], "Easy")
	await await_start()
	check(menu._stage.phase == "countdown" and not menu._stage._progression_run.is_empty(), "A paid attempt must receive server approval")
	check(progress.energy_text() == "14/15", "The first song costs one energy")
	menu._return_from_stage()
	await process_frame
	# Simulate a reply lost after the server accepted a durably saved start intent.
	var chart: Dictionary = RhythmChart.load_chart(str(SongCatalog.SONGS[0].id), "Easy")
	var intent: Dictionary = {"request_id":Crypto.new().generate_random_bytes(16).hex_encode(), "song_id":str(SongCatalog.SONGS[0].id), "difficulty":"Easy", "revision":str(chart.revision), "replay_version":RhythmJudge.REPLAY_VERSION}
	progress._pending_start = intent.duplicate(true)
	check(progress._save_pending_start(), "Persist the start intent before a request")
	var accepted: String = await progress.begin_run(str(SongCatalog.SONGS[0].id), "Easy")
	check(not accepted.is_empty() and progress.energy_text() == "13/15", "The server must accept the saved start intent once")
	progress._pending_start = intent.duplicate(true)
	check(progress._save_pending_start(), "Keep the pending intent after a simulated lost response")
	progress._owner = "" # Rebind from disk, including JSON number conversion.
	var recovered: String = await progress.begin_run(str(SongCatalog.SONGS[0].id), "Easy")
	check(recovered == accepted and progress.energy_text() == "13/15", "Reloading a saved start intent must recover its ticket without another charge")
	for index: int in 13:
		var run_id: String = await progress.begin_run(str(SongCatalog.SONGS[0].id), "Easy")
		check(not run_id.is_empty(), "Remaining energy must fund attempt %d" % index)
	check(progress.energy_text() == "0/15", "Fifteen starts must exhaust energy")
	menu._request_song_start(SongCatalog.SONGS[0], "Easy")
	await await_start()
	check(menu._stage.phase == "error" and menu._stage._progression_run.is_empty(), "An empty balance must block the song")
	check(not menu._stage.audio.playing and menu._stage.judge.score() == 0, "Rejected starts must not play music or judge notes")
	await screenshot("energy-empty-20-9.png")
	var detail: Label = menu._stage._overlay.find_child("StageErrorMessage", true, false) as Label
	check(detail != null and detail.get_line_count() > 1 and detail.size.x <= 632.0, "Energy rejection text must wrap inside the panel")
	menu._stage.retry_stage()
	await await_start()
	check(menu._stage.phase == "error" and progress.energy_text() == "0/15", "Retry must not bypass the energy gate")
	menu._return_from_stage()
	await process_frame
	# Expiring the local display clock must request the server, never grant energy locally.
	progress._energy_ticks = Time.get_ticks_msec()
	progress._energy_refresh_after = 0
	progress._process(1.1)
	await create_timer(0.4).timeout
	check(progress.energy_text() == "0/15", "Changing the client countdown must not mint energy")
	menu._open_energy()
	check(menu._energy_detail_balance.text == "0/15", "Energy details must show the depleted balance")
	await screenshot("energy-empty-lobby-20-9.png")
	print("Energy UI and authoritative start gate: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func await_start() -> void:
	for step: int in 150:
		if menu._stage.phase != "connecting": return
		await create_timer(0.1).timeout
	check(false, "Song start must finish its server request")

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var save_error: Error = root.get_texture().get_image().save_png("res://previews/" + filename)
	check(save_error == OK, "Save native energy preview")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
