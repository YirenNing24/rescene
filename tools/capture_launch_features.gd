extends SceneTree
func _initialize() -> void:
	capture.call_deferred()
func capture() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate(); menu.require_auth = false; root.add_child(menu)
	await create_timer(0.6).timeout
	menu._offer_tutorial()
	await snap("tutorial-welcome")
	menu._start_tutorial()
	var stage: RhythmStage = menu._stage; stage.set_process(false); stage.audio.stop(); stage.phase = "playing"; stage._count_label.hide()
	stage.song_time = 25.2; stage.visual_age = 25.2
	stage.judge.step(25.2, 0.01); stage._tutorial_caption(); stage.highway.queue_redraw()
	await snap("tutorial-curves")
	menu._return_from_stage(); await process_frame
	menu._open_challenges({"id":"fixture", "username":"RE:MINE"})
	await snap("friend-challenges")
	menu._close_dialog()
	var report: ReportView = ReportView.new(); report.host = menu; report.player_id = "fixture"; menu._canvas.add_child(report)
	await snap("player-report")
	menu.queue_free(); await process_frame
	quit()
func snap(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://previews/" + file_name + ".png")
	if error != OK: push_error("Could not save screenshot.")
