extends "res://tools/capture_sustain_vortex.gd"
## Real chart inputs at each momentum tier, without accounts or saved results.

func capture() -> void:
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
	for target: int in [0, 20, 40, 60]:
		while stage.judge.combo < target and time < StrictData.number(stage.chart.duration):
			advance()
			time += 0.005
		if stage.judge.combo < target: push_error("Momentum capture did not reach its target"); quit(1); return
		stage.momentum_visual = float(RhythmMomentum.tier(stage.judge.combo))
		var atmosphere: Color = RhythmMomentum.color(stage.momentum_visual)
		stage._shade.color = Color(0.025, 0.03, 0.09, 0.6).lerp(Color(atmosphere * 0.24, 0.49), stage.momentum_visual / 3.0)
		stage._update_momentum()
		stage._combo_label.text = str(stage.judge.combo)
		stage._score_label.text = "%07d" % stage.judge.score()
		stage.highway.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		var save_error: Error = screenshot.save_png("res://previews/momentum-%dx-20-9.png" % RhythmMomentum.multiplier(stage.judge.combo))
		if save_error != OK: quit(1); return
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()
