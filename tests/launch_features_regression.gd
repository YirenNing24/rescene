extends SceneTree
var failures: int = 0
func _initialize() -> void:
	verify.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition: failures += 1; push_error(message)
func verify() -> void:
	var before: Dictionary = GameServices.progression().state.duplicate(true)
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate(); menu.require_auth = false; root.add_child(menu)
	menu._start_tutorial()
	var stage: RhythmStage = menu._stage; stage.set_process(false); stage.audio.stop()
	check(stage.tutorial_mode and stage._progression_run.is_empty(), "Tutorial must never request a server ticket")
	check(StrictData.number(stage.chart.duration) == 47.0, "Teaching timeline must remain short")
	stage.phase = "playing"
	var next: int = 0; var time: float = 0.0
	while time <= 47.02:
		stage.song_time = time
		while next < stage.judge.notes.size() and stage.judge.notes[next].time <= time:
			var note: Dictionary = stage.judge.notes[next]
			var _hit: bool = stage.judge.press(next, StrictData.number(note.lane), StrictData.number(note.time))
			if note.kind == "swipe":
				stage.judge.move_pointer(next, StrictData.number(note.lane), StrictData.number(note.time), 910.0)
				stage.song_time = StrictData.number(note.time) + 0.04
				stage.judge.move_pointer(next, StrictData.number(note.lane), stage.song_time, 840.0)
				stage.judge.release(next)
			elif note.kind == "tap": stage.judge.release(next)
			next += 1
		for note: Dictionary in stage.judge.notes:
			if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, time))
		stage.judge.step(time, 0.01); time += 0.01
	check(stage._learned.has("tap") and stage._learned.has("hold") and stage._learned.has("slide") and stage._learned.has("swipe"), "Tutorial requires catching actual taps and completing hold/curve tails")
	stage.finish_stage(false)
	check(stage.phase == "results" and not stage._overlay is ResultsScreen, "Tutorial must have its own completion screen")
	check(GameServices.progression().state == before, "Tutorial must never award player progression")
	menu._return_from_stage(); await process_frame
	menu._open_challenges(); await process_frame
	check(menu._dialog is ChallengesView, "Challenges opens a real destination")
	menu._close_dialog()
	var report: ReportView = ReportView.new(); report.host = menu; report.player_id = "fixture"; menu._canvas.add_child(report)
	check(report._details.mouse_filter == Control.MOUSE_FILTER_STOP, "Report details must accept text selection")
	check(report._reason.item_count == 5, "Report form must have actionable moderation reasons")
	menu.queue_free(); await process_frame
	# Let the audio mixer release its current MP3 playback before exiting.
	await create_timer(0.3).timeout
	print("Tutorial isolation, mechanic teaching, challenges and report forms: ", "PASS" if failures == 0 else str(failures))
	quit(failures)
