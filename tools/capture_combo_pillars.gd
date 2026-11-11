extends SceneTree
## Capture the real stage at its first 10-combo milestone; no account/network.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	menu.force_mobile_gameplay_rendering = OS.get_cmdline_user_args().has("--mobile-rendering")
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await process_frame
	var song: Dictionary = SongCatalog.SONGS[0]
	for candidate: Dictionary in SongCatalog.SONGS:
		if candidate.title == "LOVE ATTACK": song = candidate
	menu._request_song_start(song, "Hard")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true
	stage.set_process(false)
	stage.audio.stop()
	stage.phase = "playing"
	stage._count_label.hide()
	var next_note: int = 0
	var time: float = 0.0
	while stage.judge.combo < 10 and time < 30.0:
		stage.song_time = time
		stage.visual_age = time
		while next_note < stage.judge.notes.size() and StrictData.number(stage.judge.notes[next_note].time) <= time:
			var note: Dictionary = stage.judge.notes[next_note]
			var pressed: bool = stage.judge.press(next_note, StrictData.number(note.lane), StrictData.number(note.time))
			if pressed and note.kind == "tap": stage.judge.release(next_note, StrictData.number(note.time))
			next_note += 1
			if stage.judge.combo >= 10: break
		for note: Dictionary in stage.judge.notes:
			if note.state == 1:
				stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, time), time)
		stage.judge.step(time, 0.005)
		time += 0.005
	if stage.judge.combo < 10: push_error("Capture did not reach a combo milestone."); quit(1); return
	stage.song_time = time
	stage.visual_age = time + 0.08
	stage._combo_label.text = str(stage.judge.combo)
	stage._score_label.text = "%07d" % stage.judge.score()
	stage.highway.combo_effects._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var suffix: String = "-mobile-720p" if menu.force_mobile_gameplay_rendering else "-20-9"
	var error: Error = root.get_texture().get_image().save_png("res://previews/combo-pillar%s.png" % suffix)
	menu.queue_free()
	await create_timer(0.2).timeout
	quit(0 if error == OK else 1)
