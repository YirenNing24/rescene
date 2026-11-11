extends SceneTree
var failures: int = 0
var screen: ResceneAuthScreen

func _initialize() -> void:
	OS.set_environment("RESCENE_AUTH_FILE", "user://__legal_registration_preview.txt")
	verify.call_deferred()

func verify() -> void:
	var _scene: Error = change_scene_to_file("res://scenes/auth_screen.tscn")
	await create_timer(0.3).timeout
	screen = current_scene as ResceneAuthScreen
	if not is_instance_valid(screen): quit(1); return
	screen._set_mode(true)
	check(not screen._agreement.button_pressed and screen._submit.disabled,"Registration starts unchecked and cannot submit")
	screen._username.text = "legal_test"
	screen._password.text = "password123"
	screen._confirm.text = "password123"
	await screen._submit_form()
	check(not screen._pending and screen._status.text.contains("agree"),"Keyboard/direct submission cannot bypass agreement")
	await process_frame
	for label_name: String in ["FanNotice","ScamNotice"]:
		var notice: Label = screen.find_child(label_name,true,false) as Label
		check(notice.size.x <= 1050.1,"Fan/scam notice must wrap within its column")
	await capture("legal-register.png")
	for kind: String in ["terms","privacy"]:
		screen._show_policy(kind)
		await create_timer(0.2).timeout
		var policy: LegalPolicyView = screen._legal_view
		check(is_instance_valid(policy) and not screen._agreement.button_pressed,"Opening a policy never accepts it")
		var scroll: ActionListScroll = policy.scroll
		check(scroll._maximum() > 100,"Long policy is scrollable")
		scroll._begin_pointer(Vector2(300,500))
		scroll._move_pointer(Vector2(300,150))
		scroll._end_pointer(Vector2(300,150))
		check(scroll._offset>100,"Policy supports drag scrolling")
		scroll.reset_motion();scroll._set_offset(0.0)
		await capture("legal-"+kind+".png")
		policy._dismiss()
		await process_frame
		check(not screen._agreement.button_pressed and screen._submit.disabled,"Closing a policy never accepts it")
	screen._agreement.button_pressed = true
	check(not screen._submit.disabled,"Explicit checkbox agreement enables registration")
	screen._set_pending(true)
	check(screen._agreement.disabled and screen._submit.disabled,"Pending registration freezes agreement and submission")
	screen._set_pending(false)
	screen._set_mode(false)
	check(not screen._agreement_group.visible and not screen._submit.disabled,"Existing players can log in without a registration checkbox")
	screen._set_mode(true)
	check(not screen._agreement.button_pressed and screen._submit.disabled,"Returning to registration never preserves an implicit acceptance")
	check(str(LegalPolicies.data().contact)=="winterape25@gmail.com","Updated support email is used")
	print("Registration agreement and policy modals: ","PASS" if failures==0 else "FAIL")
	quit(failures)

func capture(filename: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/"+filename)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
