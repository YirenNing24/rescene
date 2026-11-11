extends SceneTree
## Runs against a disposable backend graph. No credentials are printed or saved.

var failures: int = 0
var session: ResceneAuthSession

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	session = root.get_node("AuthSession")
	OS.set_environment("RESCENE_AUTH_FILE", "user://__auth_flow_%s.txt" % Time.get_ticks_usec())
	check(not session.is_authenticated(), "Startup has no stored session")
	var _error_1: Error = change_scene_to_file("res://scenes/splash_screen.tscn")
	await create_timer(1.0).timeout
	(current_scene as SplashScreen)._request_start.call_deferred()
	await wait_for_scene("AuthScreen")
	check(current_scene.name == "AuthScreen", "Splash tap opens login")
	var _error_2: Error = change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.3).timeout
	check(current_scene.name == "AuthScreen", "Unauthenticated lobby redirects to login")
	var form: ResceneAuthScreen = current_scene
	form._username.text = "ab"
	form._password.text = "password123"
	await form._submit_form()
	check(not session.busy and not form._status.text.is_empty(), "Invalid username stays local")
	form._set_mode(true)
	var username: String = "ui_" + str(Time.get_unix_time_from_system()).replace(".", "_")
	username = username.left(24)
	form._username.text = username
	form._password.text = "test password!"
	form._confirm.text = "different password"
	await form._submit_form()
	check(not session.busy and form._status.text.contains("match"), "Registration confirms password")
	form._confirm.text = "test password!"
	form._agreement.button_pressed = true
	form._submit.pressed.emit()
	check(form._submit.disabled and session.busy, "Pending request disables duplicate submission")
	await wait_for_scene("MainMenu")
	if current_scene.name != "MainMenu":
		push_error("Registration did not enter menu: " + str((current_scene as ResceneAuthScreen)._status.text))
		quit(1)
		return
	check(session.is_authenticated(), "Registration creates authenticated session")
	check(StrictData.boolean((current_scene as ResceneMainMenu)._profile_name == username), "Lobby displays real account username")
	var profile: Dictionary = await session.fetch_profile()
	check(StrictData.boolean(profile.ok and profile.data.user.username == username), "Protected profile receives bearer JWT")

	check(RhythmRecords.storage_path() != RhythmRecords.PATH, "Scores use an account-specific local file")
	(current_scene as ResceneMainMenu)._open_profile()
	session.logout()
	await wait_for_scene("AuthScreen")
	check(not session.is_authenticated() and session._token.is_empty(), "Logout clears bearer token")
	form = current_scene
	form._username.text = username
	form._password.text = "wrong password!"
	await form._submit_form()
	await wait_for_request()
	check(current_scene == form and form._status.text.contains("Incorrect"), "Wrong password shows server error")
	check(form._password.text == "wrong password!" and not form._submit.disabled, "Password retained and form unlocked so the server error remains meaningful")
	form._password.text = "test password!"
	await form._submit_form()
	await wait_for_scene("MainMenu")
	check(session.is_authenticated(), "Existing user can log in")
	var previous_refresh: String = session._refresh_token
	session._expires_at_ms = Time.get_ticks_msec() - 1
	profile = await session.fetch_profile()
	check(StrictData.boolean(profile.ok and session.is_authenticated()), "Expired access token refreshes without logging out")
	check(session._refresh_token != previous_refresh and current_scene.name == "MainMenu", "Refresh rotates the token and keeps the lobby open")
	# A revoked/invalid refresh is the point at which a password is required.
	session._refresh_token = "invalid-refresh-token"
	session._expires_at_ms = Time.get_ticks_msec() - 1
	profile = await session.fetch_profile()
	await wait_for_scene("AuthScreen")
	check(StrictData.boolean(not profile.ok and (current_scene as ResceneAuthScreen)._status.text.contains("expired")), "Rejected refresh returns to login with explanation")
	var original_url: String = OS.get_environment("RESCENE_API_URL")
	OS.set_environment("RESCENE_API_URL", "http://127.0.0.1:59999")
	var unavailable: Dictionary = await session.authenticate(username, "test password!")
	check(StrictData.boolean(not unavailable.ok and not session.busy), "Connection failure recovers without locking form")
	OS.set_environment("RESCENE_API_URL", original_url)
	print("Account flow: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	current_scene.queue_free()
	await create_timer(0.2).timeout
	quit(failures)

func wait_for_request() -> void:
	for step: int in 200:
		if not session.busy: break
		await create_timer(0.1).timeout
	await create_timer(0.15).timeout

func wait_for_scene(scene_name: String) -> void:
	for step: int in 200:
		if is_instance_valid(current_scene) and current_scene.name == scene_name: break
		await create_timer(0.1).timeout
	await create_timer(0.2).timeout

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
