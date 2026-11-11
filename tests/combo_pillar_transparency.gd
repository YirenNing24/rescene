extends SceneTree
## Render the real shader through the transparent mobile compositor.
var failures: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This GPU regression requires a display."); quit(1); return
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.32, 0.28, 0.43, 1.0)
	background.size = Vector2(480, 360)
	root.add_child(background)
	var container: SubViewportContainer = SubViewportContainer.new()
	container.size = Vector2(480, 360)
	root.add_child(container)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(480, 360)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	container.add_child(viewport)
	var shade: ColorRect = ColorRect.new()
	shade.size = Vector2(480, 360)
	shade.color = Color(0.025, 0.03, 0.09, 0.6)
	viewport.add_child(shade)
	var pixel: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(pixel)
	sprite.centered = false
	sprite.position = Vector2(100, 10)
	sprite.scale = Vector2(220, 300)
	var effect: ShaderMaterial = ShaderMaterial.new()
	effect.shader = load("res://shaders/combo_pillar.gdshader") as Shader
	if OS.get_cmdline_user_args().has("--old-alpha"):
		var old_shader: Shader = Shader.new()
		old_shader.code = effect.shader.code.split("\tlight *= attack * fade * edge;")[0] + "\tCOLOR = vec4(light * attack * fade * edge, 1.0);\n}\n"
		effect.shader = old_shader
	effect.set_shader_parameter("seed", 10.0)
	sprite.material = effect
	sprite.hide()
	viewport.add_child(sprite)
	await frames()
	var baseline: Image = viewport.get_texture().get_image()
	var composite: Image = root.get_texture().get_image()
	for age: float in [0.0, 0.02, 0.08, 0.25, 0.48, 0.52]:
		effect.set_shader_parameter("age", age)
		sprite.show()
		await frames()
		var rendered: Image = viewport.get_texture().get_image()
		var final_image: Image = root.get_texture().get_image()
		for uv: Vector2 in [Vector2(0.01,0.05), Vector2(0.99,0.05), Vector2(0.01,0.5), Vector2(0.99,0.5), Vector2(0.01,0.9), Vector2(0.99,0.9)]:
			var point: Vector2i = Vector2i(sprite.position + sprite.scale * uv)
			var before: Color = baseline.get_pixelv(point)
			var after: Color = rendered.get_pixelv(point)
			check(absf(before.a - after.a) < 0.01, "Empty pillar space must preserve mobile viewport alpha at age %.2f" % age)
			var screen_point: Vector2i = Vector2i(root.get_final_transform() * Vector2(point))
			var original: Color = composite.get_pixelv(screen_point)
			var output: Color = final_image.get_pixelv(screen_point)
			check(absf(output.r-original.r) < 0.01 and absf(output.g-original.g) < 0.01 and absf(output.b-original.b) < 0.01, "Pillar boundaries must not darken or cover the background")
		if is_equal_approx(age, 0.08):
			var beam: Color = rendered.get_pixel(210, 220)
			check(beam.r > baseline.get_pixel(210,220).r + 0.1, "Visible beam must retain its light")
			var suffix: String = "-old" if OS.get_cmdline_user_args().has("--old-alpha") else "-fixed"
			var _saved: Error = final_image.save_png("res://builds/pillar-transparent-composite%s.png" % suffix)
	container.queue_free(); background.queue_free()
	await process_frame
	print("Pillar mobile alpha/compositing: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
