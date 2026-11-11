extends SceneTree
var failures: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var session: ResceneAuthSession = GameServices.session()
	var password: String = "ordinary"
	var seeded: Dictionary = await session.authenticate("password_fixture",password,true,true)
	check(StrictData.boolean(seeded.get("ok",false)),"An ordinary eight-letter password is accepted by the server")
	if failures > 0: quit(failures); return
	session.logout()
	var _scene: Error = change_scene_to_file("res://scenes/auth_screen.tscn")
	await create_timer(0.3).timeout
	var form: ResceneAuthScreen = current_scene as ResceneAuthScreen
	form._set_mode(true)
	form._username.text = "password_fixture"
	form._password.text = password
	form._confirm.text = password
	form._agreement.button_pressed = true
	form._show_password.button_pressed = true
	form._set_mode(true)
	check(form._password.text == password and form._confirm.text == password,"Retapping the selected Register tab must not erase input")
	var serial: int = form._submission_serial
	form._queue_submit()
	await form._submit_form()
	await process_frame
	check(form._submission_serial == serial+1,"Keyboard and button submission must make one request")
	check(form._status.text.contains("already taken"),"The server's real registration error remains visible")
	check(form._password.text == password and form._confirm.text == password,"A failed request preserves password fields for correction")
	await form._submit_form()
	check(form._status.text.contains("already taken"),"Retry must not replace the server error with a false password-length error")
	form._password.clear()
	await form._submit_form()
	check(form._status.text=="Enter your password.","Empty and short password messages are distinguished")
	form._password.text = "plain"
	await form._submit_form()
	check(form._status.text.contains("entered 5"),"Short password message gives the actual character count")
	print("Ordinary password and form retry handling: ","PASS" if failures==0 else "FAIL")
	quit(failures)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
