extends SceneTree
## Real chart autoplay: review a collected ribbon's moving vortex without saving scores.

var stage: RhythmStage
var next_note: int = 0
var time: float = 0.0

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute("/tmp/rescene-vortex-frames")
	if directory_error != OK: quit(1); return
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await create_timer(0.2).timeout
	var song: Dictionary = SongCatalog.SONGS[0]
	for candidate: Dictionary in SongCatalog.SONGS:
		if candidate.title == "LOVE ATTACK": song = candidate
	menu._request_song_start(song, "Hard")
	stage = menu._stage
	stage.test_mode = true
	stage.set_process(false)
	stage.audio.stop()
	stage.phase = "playing"
	stage._count_label.hide()
	var target: float = -1.0
	for note: Dictionary in stage.judge.notes:
		if note.kind == "slide" and note.duration >= 1.2:
			target = StrictData.number(note.time) + 0.2
			break
	if target < 0.0: push_error("No ribbon available for vortex capture"); quit(1); return
	for frame: int in 30:
		var until: float = target + float(frame) / 30.0
		while time <= until:
			advance()
			time += 0.005
		stage._combo_label.text = str(stage.judge.combo)
		stage._score_label.text = "%07d" % stage.judge.score()
		stage.highway.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		var frame_error: Error = screenshot.save_png("/tmp/rescene-vortex-frames/frame-%03d.png" % frame)
		if frame_error != OK: quit(1); return
		if frame == 8:
			var still_error: Error = screenshot.save_png("res://previews/sustain-vortex-20-9.png")
			if still_error != OK: quit(1); return
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()

func advance() -> void:
	stage.song_time = time
	stage.visual_age = time
	while next_note < stage.judge.notes.size() and StrictData.number(stage.judge.notes[next_note].time) <= time:
		var note: Dictionary = stage.judge.notes[next_note]
		var pressed: bool = stage.judge.press(next_note, StrictData.number(note.lane), StrictData.number(note.time))
		if pressed and note.kind == "tap": stage.judge.release(next_note, StrictData.number(note.time))
		next_note += 1
	for note: Dictionary in stage.judge.notes:
		if note.state == 1:
			stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, time), time)
	stage.judge.step(time, 0.005)
	stage.highway.sustain_effects._process(0.0)
