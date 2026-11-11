extends SceneTree
## Render a real failed attempt and a full clear without saving review scores.


func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
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
	play(stage, 10.0)
	stage.finish_stage(true)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var _error_1: Error = root.get_texture().get_image().save_png("res://previews/game-over-20-9.png")
	stage.retry_stage()
	play(stage,StrictData.number(stage.chart.duration))
	stage.finish_stage(false)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var _error_2: Error = root.get_texture().get_image().save_png("res://previews/stage-clear-20-9.png")
	menu.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit()

func play(stage: RhythmStage, input_until: float) -> void:
	stage.phase = "playing"
	stage._count_label.hide()
	var next: int = 0
	var t: float = 0.0
	while t <= stage.chart.duration + 0.02:
		stage.song_time = t
		stage.visual_age = t
		if t <= input_until:
			while next < StrictData.array(stage.judge.notes).size() and stage.judge.notes[next].time <= t:
				var note: Dictionary = stage.judge.notes[next]
				var _bool_3: bool = stage.judge.press(next,StrictData.number(note.lane),StrictData.number(note.time))
				if note.kind == "tap": stage.judge.release(next)
				next += 1
			for note: Dictionary in stage.judge.notes:
				if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, t))
		else:
			stage.judge.pointers.clear()
		stage.judge.step(t, 0.01)
		if stage.judge.life <= 0.0: break
		t += 0.01
