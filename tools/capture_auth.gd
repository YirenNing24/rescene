extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var _error_1: Error = change_scene_to_file("res://scenes/auth_screen.tscn")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var _error_2: Error = root.get_texture().get_image().save_png("res://previews/login-20-9.png")
	(current_scene as ResceneAuthScreen)._set_mode(true)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var _error_3: Error = root.get_texture().get_image().save_png("res://previews/register-20-9.png")
	print("Login and registration previews saved.")
	quit()
