extends SceneTree
## Native review frames of an actual two-note chord and its firework decay.


func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var _error_1: Error = DirAccess.make_dir_recursive_absolute("/tmp/rescene-hit-frames")
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
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
	var chord_time: float = 2.0
	for index: int in range(1, StrictData.array(stage.judge.notes).size()):
		if is_equal_approx(StrictData.number(stage.judge.notes[index].time),StrictData.number(stage.judge.notes[index - 1].time)):
			chord_time = stage.judge.notes[index].time
			break
	var next: int = 0
	var t: float = 0.0
	while t < chord_time - 0.001:
		stage.song_time = t
		stage.visual_age = t
		while next < StrictData.array(stage.judge.notes).size() and stage.judge.notes[next].time <= t:
			var note: Dictionary = stage.judge.notes[next]
			var _bool_2: bool = stage.judge.press(next,StrictData.number(note.lane),StrictData.number(note.time))
			if note.kind == "tap": stage.judge.release(next)
			next += 1
		for note: Dictionary in stage.judge.notes:
			if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, t))
		stage.judge.step(t, 0.005)
		t += 0.005
	stage.song_time = chord_time
	stage.visual_age = chord_time
	# Pause the chart's visual approach while reviewing this hit's animation.
	while next < StrictData.array(stage.judge.notes).size() and stage.judge.notes[next].time <= chord_time + 0.001:
		var note: Dictionary = stage.judge.notes[next]
		var _bool_3: bool = stage.judge.press(next,StrictData.number(note.lane),StrictData.number(note.time))
		stage.judge.release(next)
		next += 1
	stage._process(0.0)
	for frame: int in 30:
		stage.visual_age = chord_time + frame / 30.0
		stage.highway.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var _error_4: Error = image.save_png("/tmp/rescene-hit-frames/frame-%03d.png" % frame)
		if frame == 3: var _error_5: Error = image.save_png("res://previews/hit-fireworks-20-9.png")
	menu.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit()
