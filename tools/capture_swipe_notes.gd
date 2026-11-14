extends SceneTree
## Local preview through the same 720p render target used by Android.
func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; menu.force_mobile_gameplay_rendering = true
	root.add_child(menu); current_scene = menu
	menu._open_songs()
	await process_frame
	var song: Dictionary = SongCatalog.SONGS[0]
	for candidate: Dictionary in SongCatalog.SONGS:
		if str(candidate.title).to_upper() == "LOVE ATTACK": song = candidate
	menu._request_song_start(song, "Normal")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true; stage.set_process(false); stage.audio.stop()
	stage.phase = "playing"; stage._count_label.hide()
	var target: float = 0.0
	for note: Dictionary in stage.judge.notes:
		if note.kind == "swipe": target = StrictData.number(note.time); break
	for note: Dictionary in stage.judge.notes:
		if StrictData.number(note.time) < target: note.state = 2
	stage.song_time = target - 0.05
	stage.momentum_visual = 1.0
	for frame: int in 2:
		stage.visual_age = float(frame) * 0.2
		stage._process(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var result: Error = root.get_texture().get_image().save_png("res://previews/swipe-note-%d.png" % frame)
		if result != OK: push_error("Swipe preview capture failed")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()
