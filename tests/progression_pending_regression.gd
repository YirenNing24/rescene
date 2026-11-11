extends SceneTree
## Driver disconnects the disposable API after it ages the run ticket.
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var session: ResceneAuthSession = root.get_node("AuthSession")
	var progress: ProgressionService = root.get_node("Progression")
	var marker: String = OS.get_environment("RESCENE_PROGRESS_MARKER")
	var response: Dictionary = await session.restore_session()
	if not response.ok: push_error("Could not restore pending-sync fixture account"); quit(1); return
	await progress.refresh()
	var prior: int = StrictData.integer(progress.state.xp)
	var run_id: String = await progress.begin_run(SongCatalog.SONGS[0].id,"Easy")
	var file: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
	var _bool_1: bool = file.store_string(JSON.stringify({"user_id":session.user.id,"run_id":run_id}))
	file.close()
	for step: int in 200:
		if FileAccess.file_exists(marker+".ready"): break
		await create_timer(0.1).timeout
	file = FileAccess.open(marker+".disconnect",FileAccess.WRITE)
	file.close()
	for step: int in 200:
		if FileAccess.file_exists(marker+".offline"): break
		await create_timer(0.1).timeout
	var chart: Dictionary = RhythmChart.load_chart(SongCatalog.SONGS[0].id,"Easy")
	var judge: RhythmJudge = RhythmJudge.new()
	judge.setup(chart)
	preload("res://tests/replay_fixture.gd").autoplay(judge,chart)
	await progress.finish_run(run_id,{"score":judge.score(),"max_combo":judge.max_combo,"counts":judge.counts,"trace":judge.trace,"replay":judge.replay_payload(run_id,str(chart.revision))})
	if not FileAccess.file_exists(progress._queue_path()) or progress._pending.size()!=1 or StrictData.integer(progress.state.xp)!=prior:
		push_error("Disconnected result was not retained for retry")
		quit(1)
		return
	file = FileAccess.open(marker+".expected",FileAccess.WRITE)
	var _bool_2: bool = file.store_string(JSON.stringify({"xp":prior+100,"title":progress.state.title,"frame":progress.state.frame,"login_completed":progress.state.daily_login.completed}))
	file.close()
	print("Disconnected completion queued for restart: PASS")
	quit()
