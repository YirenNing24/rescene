extends SceneTree
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var session: ResceneAuthSession = root.get_node("AuthSession")
	var progress: ProgressionService = root.get_node("Progression")
	var response: Dictionary = await session.restore_session()
	if not response.ok: push_error("Persistent account did not restore"); quit(1); return
	await progress.refresh()
	var cloud: CloudScoresService = root.get_node("CloudScores")
	cloud._bind()
	var _error_1: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud._path()))
	cloud.records.clear()
	await cloud.refresh()

	if cloud.records.size()!=1 or RhythmRecords.all_scores().size()!=1 or RhythmRecords.all_scores()[0].get("source", "")!="cloud":
		push_error("Cloud bests did not restore in a fresh process without local personal bests")
		quit(1)
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("RESCENE_PROGRESS_MARKER")+".expected"))
	if StrictData.integer(progress.state.get("xp",0)) != StrictData.integer(expected.xp) or progress.state.get("title")!=expected.title or progress.state.get("frame")!=expected.frame:
		push_error("Account progression did not survive restart: actual XP %s, expected XP %s; %s" % [progress.state.get("xp",0),expected.xp,progress.error_message])
		quit(1)
		return
	if StrictData.integer(progress.state.daily_login.completed)!=StrictData.integer(expected.login_completed) or not progress.state.daily_login.claimed_today:
		push_error("Daily login claim did not survive API and game restart")
		quit(1)
		return
	session.logout()
	if not cloud.records.is_empty(): push_error("Logout retained cloud records from another account"); quit(1); return
	if not progress.state.is_empty(): push_error("Logout retained previous account progression"); quit(1); return
	print("Progression restart and account cleanup: PASS")
	quit()
