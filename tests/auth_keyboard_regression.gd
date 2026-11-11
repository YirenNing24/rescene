extends SceneTree

var failures: int = 0
var screen: ResceneAuthScreen

func _initialize() -> void:
	OS.set_environment("RESCENE_AUTH_FILE", "user://__keyboard_regression.txt")
	verify.call_deferred()

func verify() -> void:
	var _scene: Error = change_scene_to_file("res://scenes/auth_screen.tscn")
	await create_timer(0.3).timeout
	screen = current_scene as ResceneAuthScreen
	if not is_instance_valid(screen): quit(1); return
	# Native-screen coordinates are converted before this layout helper. These
	# cover landscape keyboards occupying 50%, 59% (reported Redmi), and 70%.
	for visible_bottom: float in [540.0, 440.0, 324.0]:
		screen._set_mode(true)
		screen._fit_keyboard(visible_bottom, true)
		await settle()
		for field: LineEdit in [screen._username, screen._password, screen._confirm]:
			await focus_and_check(field, visible_bottom)
		screen._set_mode(false)
		screen._fit_keyboard(visible_bottom, true)
		await settle()
		for field: LineEdit in [screen._username, screen._password]:
			await focus_and_check(field, visible_bottom)
		screen._show_recovery(true)
		screen._fit_keyboard(visible_bottom, true)
		await settle()
		for field: LineEdit in [screen._recovery_username, screen._recovery_code, screen._recovery_password, screen._recovery_confirm]:
			await focus_and_check(field, visible_bottom)
		screen._show_recovery(false)
	screen._fit_keyboard(1080.0, false)
	await settle()
	check(screen._title.visible and screen._subtitle.visible, "Closing keyboard restores headings")
	check(screen._scroll.position.y == 363.0 and screen._scroll.size.y == 620.0, "Closing keyboard restores full form")
	check(screen._panel.position.y == 75.0 and screen._panel.size.y == 930.0, "Closing keyboard restores panel")
	print("Landscape auth keyboard visibility: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func focus_and_check(field: LineEdit, visible_bottom: float) -> void:
	field.grab_focus()
	await settle()
	var inverse: Transform2D = screen._canvas.get_global_transform().affine_inverse()
	var top: float = (inverse * field.get_global_rect().position).y
	var bottom: float = (inverse * field.get_global_rect().end).y
	check(top >= screen._scroll.position.y - 1.0, "Focused input is not clipped above scroll")
	check(bottom <= visible_bottom - 23.0, "Focused input stays above keyboard")
	check(bottom <= screen._scroll.position.y + screen._scroll.size.y + 1.0, "Focused input is fully inside scroll")
	field.text = "typing stays intact"
	await settle()
	check(field.text == "typing stays intact", "Scrolling preserves typed text")

func settle() -> void:
	for _frame: int in range(5): await process_frame

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
