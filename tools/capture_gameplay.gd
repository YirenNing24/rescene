extends SceneTree
## Run with a display; saves the real native gameplay canvas for visual review.


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
	for item: Dictionary in SongCatalog.SONGS:
		if item.title == "LOVE ATTACK": song = item
	menu._request_song_start(song, "Hard")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true
	stage.set_process(false)
	stage.audio.stop()
	stage.phase = "playing"
	stage._count_label.hide()
	var until: float = 6.0
	for note: Dictionary in stage.judge.notes:
		if note.kind == "slide":
			until = note.time + note.duration * 0.27
			break
	var next: int = 0
	var t: float = 0.0
	while t <= until:
		stage.song_time = t
		stage.visual_age = t
		while next < StrictData.array(stage.judge.notes).size() and stage.judge.notes[next].time <= t:
			var note: Dictionary = stage.judge.notes[next]
			var _bool_1: bool = stage.judge.press(next,StrictData.number(note.lane),StrictData.number(note.time))
			if note.kind == "tap": stage.judge.release(next)
			next += 1
		for note: Dictionary in stage.judge.notes:
			if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, t))
		stage.judge.step(t, 0.01)
		t += 0.01
	stage._process(0.0)
	stage.highway.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var suffix: String = "-mobile-720p" if menu.force_mobile_gameplay_rendering else "-20-9"
	var _error_2: Error = root.get_texture().get_image().save_png("res://previews/gameplay%s.png" % suffix)
	stage.pause_stage()
	await process_frame
	await RenderingServer.frame_post_draw
	var _error_3: Error = root.get_texture().get_image().save_png("res://previews/gameplay-pause%s.png" % suffix)
	stage.retry_stage()
	stage.phase = "playing"
	stage._count_label.hide()
	next = 0
	t = 0.0
	while t <= stage.chart.duration + 0.03:
		stage.song_time = t
		stage.visual_age = t
		while next < StrictData.array(stage.judge.notes).size() and stage.judge.notes[next].time <= t:
			var note: Dictionary = stage.judge.notes[next]
			var _bool_4: bool = stage.judge.press(next,StrictData.number(note.lane),StrictData.number(note.time))
			if note.kind == "tap": stage.judge.release(next)
			next += 1
		for note: Dictionary in stage.judge.notes:
			if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, t))
		stage.judge.step(t, 0.02)
		t += 0.02
	stage.finish_stage(false)
	await create_timer(0.8).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var _error_5: Error = root.get_texture().get_image().save_png("res://previews/gameplay-results%s.png" % suffix)
	menu.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit()
