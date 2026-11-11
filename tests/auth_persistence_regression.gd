extends SceneTree
## Each invocation is a fresh process. Supply a disposable RESCENE_AUTH_FILE.

var failures: int = 0

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var session: ResceneAuthSession = root.get_node("AuthSession")
	var mode: String = OS.get_environment("RESCENE_AUTH_TEST_MODE")
	check(not OS.get_environment("RESCENE_AUTH_FILE").is_empty(), "Test needs an isolated token file")
	if failures > 0: quit(failures); return
	match mode:
		"seed":
			var result: Dictionary = await session.authenticate("persist_" + str(Time.get_ticks_usec()), "test password!", true, true)
			check(StrictData.boolean(result.ok), "Registration succeeds")
			check(FileAccess.file_exists(session.session_file()), "Login saves token file")
			var saved: Dictionary = StrictData.dictionary(JSON.parse_string(FileAccess.get_file_as_string(session.session_file())))
			check(str(saved.get("access_token", "")) == session._token and str(saved.get("refresh_token", "")) == session._refresh_token, "Text file persists access and refresh tokens")
			check(session._refresh_expires_at - StrictData.integer(Time.get_unix_time_from_system()) >= 2591990, "Saved login lasts thirty days")
		"restore":
			check(not session.is_authenticated(), "Fresh process starts unauthenticated")
			var _error_1: Error = change_scene_to_file("res://scenes/auth_screen.tscn")
			for step: int in 150:
				if is_instance_valid(current_scene) and current_scene.name == "MainMenu": break
				await create_timer(0.1).timeout
			check(is_instance_valid(current_scene) and current_scene.name == "MainMenu", "Saved session skips login and enters lobby")
			check(session.is_authenticated() and str(session.user.username).begins_with("persist_"), "Server restores the correct account")
		"logout":
			var result: Dictionary = await session.restore_session()
			check(StrictData.boolean(result.ok), "Session restored before logout")
			session.logout()
			check(not FileAccess.file_exists(session.session_file()), "Logout deletes saved JWT")
			check(not session.is_authenticated(), "Logout clears memory")
		"invalid", "expired":
			var result: Dictionary = await session.restore_session()
			check(StrictData.boolean(not result.ok and not session.is_authenticated()), "Rejected token cannot authenticate")
			check(not FileAccess.file_exists(session.session_file()), "Invalid or expired JWT is removed")
		"offline":
			var result: Dictionary = await session.restore_session()
			check(StrictData.boolean(not result.ok and not session.is_authenticated()), "Offline restore cannot authenticate")
			check(FileAccess.file_exists(session.session_file()), "Network failure preserves saved JWT for retry")
		"empty":
			var result: Dictionary = await session.restore_session()
			check(StrictData.boolean(not result.ok and not session.is_authenticated()), "Logged-out process requires login")
		_:
			check(false, "Unknown persistence test mode")
	print("Persistent login (", mode, "): ", "PASS" if failures == 0 else "FAIL")
	if is_instance_valid(current_scene): current_scene.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
