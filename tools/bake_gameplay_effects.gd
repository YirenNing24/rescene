extends SceneTree
## Bake the reference procedural light effects once, instead of running their
## transcendental-heavy fragment loops on every phone pixel during a song.

const FRAMES: int = 32
const COLUMNS: int = 8

func _initialize() -> void:
	bake.call_deferred()

func bake() -> void:
	if DisplayServer.get_name() == "headless": push_error("Effect baking requires a GPU display"); quit(1); return
	var _created: Error = DirAccess.make_dir_recursive_absolute("res://assets/effects")
	var pillar: String = FileAccess.get_file_as_string("res://shaders/combo_pillar.gdshader")
	pillar = pillar.replace("blend_add", "blend_premul_alpha").replace("vec4(light / coverage, coverage)", "vec4(light, coverage)")
	await atlas(pillar, Vector2i(128,256), "pillar", [Color.WHITE], 0.52)
	var vortex: String = FileAccess.get_file_as_string("res://shaders/sustain_vortex.gdshader")
	vortex = vortex.replace("blend_add", "blend_premul_alpha").replace("age * 26.0 + seed", "age * 27.64601535 + seed")
	vortex = vortex.replace("COLOR = vec4(light * strength * bounds, 1.0);", "vec3 light_out = light * strength * bounds; float coverage = clamp(max(light_out.r, max(light_out.g, light_out.b)), 0.0, 1.0); COLOR = vec4(light_out, coverage);")
	await atlas(vortex, Vector2i(192,112), "vortex", RhythmHighway.NOTE_PALETTE, 1.0 / 4.4)
	print("Baked 32 pillar frames and seven 32-frame vortex palettes.")
	quit()

func atlas(source: String, tile: Vector2i, label: String, colors: Array[Color], duration: float) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = tile; viewport.transparent_bg = true; viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect: ColorRect = ColorRect.new(); rect.size = Vector2(tile)
	var shader: Shader = Shader.new(); shader.code = source
	var effect: ShaderMaterial = ShaderMaterial.new(); effect.shader = shader
	if label == "vortex": effect.set_shader_parameter("strength", 1.0)
	effect.set_shader_parameter("seed", 10.0 if label == "pillar" else 0.0)
	rect.material = effect; viewport.add_child(rect)
	var image: Image = Image.create(tile.x * COLUMNS, tile.y * ceili(float(FRAMES * colors.size()) / COLUMNS), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for palette: int in colors.size():
		if label == "vortex": effect.set_shader_parameter("tint", colors[palette])
		for frame: int in FRAMES:
			effect.set_shader_parameter("age", (float(frame) + 0.5) / FRAMES * duration)
			await process_frame; await RenderingServer.frame_post_draw
			var rendered: Image = viewport.get_texture().get_image()
			# Viewport pixels are premultiplied; imported PNG textures use straight alpha.
			for y: int in tile.y:
				for x: int in tile.x:
					var pixel: Color = rendered.get_pixel(x, y)
					if pixel.a > 0.0: rendered.set_pixel(x, y, Color(pixel.r / pixel.a, pixel.g / pixel.a, pixel.b / pixel.a, pixel.a))
			var index: int = palette * FRAMES + frame
			image.blit_rect(rendered, Rect2i(Vector2i.ZERO,tile), Vector2i(index % COLUMNS * tile.x, floori(float(index) / COLUMNS) * tile.y))
	var saved: Error = image.save_png("res://assets/effects/" + label + "-atlas.png")
	if saved != OK: push_error("Effect atlas could not be saved")
	viewport.queue_free(); await process_frame
