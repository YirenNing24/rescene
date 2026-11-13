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
	var render_size: Vector2 = Vector2(220, 300)
	sprite.scale = render_size
	var effect: ShaderMaterial = ShaderMaterial.new()
	effect.shader = load("res://shaders/combo_pillar.gdshader") as Shader
	if OS.get_cmdline_user_args().has("--old-alpha"):
		var old_shader: Shader = Shader.new()
		old_shader.code = effect.shader.code.split("\tlight *= attack * fade * edge;")[0] + "\tCOLOR = vec4(light * attack * fade * edge, 1.0);\n}\n"
		effect.shader = old_shader
	effect.set_shader_parameter("seed", 10.0)
	var vortex: bool = OS.get_cmdline_user_args().has("--vortex")
	var atlas: bool = OS.get_cmdline_user_args().has("--atlas") or vortex
	var frame_size: Vector2 = RhythmSustainEffects.FRAME_SIZE if vortex else RhythmComboEffects.FRAME_SIZE
	if atlas:
		sprite.texture = preload("res://assets/effects/vortex-atlas.png") if vortex else preload("res://assets/effects/pillar-atlas.png")
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprite.scale = render_size / frame_size
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = additive
	else: sprite.material = effect
	sprite.hide()
	viewport.add_child(sprite)
	await frames()
	var baseline: Image = viewport.get_texture().get_image()
	var composite: Image = root.get_texture().get_image()
	for age: float in [0.0, 0.02, 0.08, 0.25, 0.48, 0.52]:
		effect.set_shader_parameter("age", age)
		if atlas:
			var frame: int = floori(fposmod(age, RhythmSustainEffects.CYCLE_SECONDS) / RhythmSustainEffects.CYCLE_SECONDS * 32.0) if vortex else mini(RhythmComboEffects.FRAMES - 1, floori(age / RhythmComboEffects.LIFETIME * RhythmComboEffects.FRAMES))
			sprite.region_rect = Rect2(Vector2(float(frame % 8) * frame_size.x, floorf(float(frame)/8.0) * frame_size.y), frame_size)
		sprite.show()
		await frames()
		var rendered: Image = viewport.get_texture().get_image()
		var final_image: Image = root.get_texture().get_image()
		for uv: Vector2 in [Vector2(0.01,0.05), Vector2(0.99,0.05), Vector2(0.01,0.5), Vector2(0.99,0.5), Vector2(0.01,0.9), Vector2(0.99,0.9)]:
			var point: Vector2i = Vector2i(sprite.position + render_size * uv)
			var before: Color = baseline.get_pixelv(point)
			var after: Color = rendered.get_pixelv(point)
			check(absf(before.a - after.a) < 0.01, "Empty pillar space must preserve mobile viewport alpha at age %.2f" % age)
			var screen_point: Vector2i = Vector2i(root.get_final_transform() * Vector2(point))
			var original: Color = composite.get_pixelv(screen_point)
			var output: Color = final_image.get_pixelv(screen_point)
			check(absf(output.r-original.r) < 0.01 and absf(output.g-original.g) < 0.01 and absf(output.b-original.b) < 0.01, "Pillar boundaries must not darken or cover the background")
		if is_equal_approx(age, 0.08):
			var sample_y: int = 202 if vortex else 220
			var beam: Color = rendered.get_pixel(210, sample_y)
			check(beam.r > baseline.get_pixel(210,sample_y).r + 0.1, "Visible effect must retain its light")
			var suffix: String = "-vortex" if vortex else "-atlas" if atlas else "-old" if OS.get_cmdline_user_args().has("--old-alpha") else "-fixed"
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
