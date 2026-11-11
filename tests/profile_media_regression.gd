extends SceneTree
## Real HTTP uploads against a disposable Fiber/FalkorDB fixture.
var failures: int = 0
var menu: ResceneMainMenu
var account_id: String = ""
var image_path: String = ""

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var session: ResceneAuthSession = GameServices.session()
	var photos: ProfileMediaService = GameServices.photos()
	var response: Dictionary
	var fixture_path: String = OS.get_environment("RESCENE_MEDIA_TEST_DIR")
	image_path = fixture_path.path_join("photo.jpg")
	var texture: Texture2D = load("res://assets/art/rescene-main-menu.png") as Texture2D
	var image: Image = texture.get_image()
	image.resize(1400, 630, Image.INTERPOLATE_LANCZOS)
	var save_error: Error = image.save_jpg(image_path, 0.9)
	check(save_error == OK, "Fixture photo saved")
	if OS.get_environment("RESCENE_MEDIA_TEST_PHASE") == "restore":
		response = await session.restore_session()
		check(StrictData.boolean(response.ok), "Saved login restores after API/game restart")
	else:
		response = await session.authenticate("gallery_player", "gallery-test-password", true, true)
		check(StrictData.boolean(response.ok), "Create isolated photo account")
	account_id = str(session.user.get("id", ""))
	await photos.refresh()
	if OS.get_environment("RESCENE_MEDIA_TEST_PHASE") == "restore":
		check(StrictData.array(photos.media.get("gallery", [])).size() == 5, "Gallery persists across restart")
		check(not StrictData.dictionary(photos.media.get("avatar", {})).is_empty(), "Avatar persists across restart")
		await build_and_capture(true)
		session.logout()
		check(photos.media.get("avatar") == null and photos._textures.is_empty(), "Logout clears avatar and downloaded photos")
		print("Native photo restore, public gallery and logout isolation: ", "PASS" if failures == 0 else "FAIL")
		quit(failures); return
	await photos.upload("avatar", image_path)
	check(not StrictData.dictionary(photos.media.get("avatar", {})).is_empty(), "Avatar upload saved")
	var avatar: String = str(StrictData.dictionary(photos.media.get("avatar", {})).get("url", ""))
	for index: int in 5:
		# Existing artwork is only test content; no player uploads are modified.
		var member: AtlasTexture = AtlasTexture.new(); member.atlas = texture
		member.region = Rect2((0.306 + index * 0.09 - 0.08) * texture.get_width(), texture.get_height() * 0.35, texture.get_width() * 0.16, texture.get_height() * 0.65)
		var portrait: Image = member.get_image()
		portrait.resize(600, 900, Image.INTERPOLATE_LANCZOS)
		var photo_path: String = fixture_path.path_join("photo_%d.png" % index)
		var _saved: Error = portrait.save_png(photo_path)
		await photos.upload("gallery", photo_path)
	check(StrictData.array(photos.media.gallery).size() == 5, "Five uploaded gallery photos")
	await photos.upload("gallery", image_path)
	check(StrictData.array(photos.media.gallery).size() == 5 and photos.message.contains("five"), "Server rejects a sixth photo")
	var old: Dictionary = StrictData.dictionary(StrictData.array(photos.media.gallery)[0])
	await photos.upload("gallery", fixture_path.path_join("photo_0.png"), str(old.id))
	check(str(StrictData.dictionary(StrictData.array(photos.media.gallery)[0]).id) != str(old.id), "Replace a full gallery slot")
	var download: Dictionary = await session._send(avatar, HTTPClient.METHOD_GET, {}, PackedByteArray(), "", true)
	check(StrictData.boolean(download.ok), "Authenticated photo download")
	session._expires_at_ms = Time.get_ticks_msec() - 1
	await photos.upload("avatar", fixture_path.path_join("photo_0.png"))
	check(session.is_authenticated(), "Binary upload renews expired access token")
	var first: Dictionary = StrictData.dictionary(StrictData.array(photos.media.gallery)[0])
	await photos.remove("gallery", str(first.id))
	check(StrictData.array(photos.media.gallery).size() == 4, "Delete frees a gallery slot")
	await photos.upload("gallery", fixture_path.path_join("photo_0.png"))
	var broken: String = fixture_path.path_join("broken.png")
	var file: FileAccess = FileAccess.open(broken, FileAccess.WRITE)
	var _wrote: bool = file.store_string("not a png"); file.close()
	await photos.upload("gallery", broken)
	check(photos.message.contains("valid JPG or PNG") and StrictData.array(photos.media.gallery).size() == 5, "Malformed upload preserves gallery")
	photos.message = ""
	await build_and_capture(false)
	print("Native avatar, five-photo gallery, full gallery replacement, deletion and binary auth refresh: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func build_and_capture(public_view: bool) -> void:
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as ResceneMainMenu
	root.add_child(menu); current_scene = menu
	await create_timer(0.7).timeout
	menu._music.stop()
	menu._open_profile()
	await create_timer(0.4).timeout
	var view: PlayerProfile = menu._profile_view
	await warm_photos()
	await capture("player-profile-avatar-20-9.png" if not public_view else "player-profile-restored-20-9.png")
	view.set_tab("gallery")
	check((view.body.find_child("AddGalleryPhoto", true, false) as Button).disabled, "Add button disabled at five photos")
	for index: int in 5:
		check(view.body.find_child("ReplaceGalleryPhoto_%d" % index, true, false) != null, "Owned gallery has replace controls")
	await capture("player-gallery-20-9.png")
	view._view_photo(1)
	check(is_instance_valid(view._photo_viewer), "Full-size photo viewer opens")
	await capture("player-gallery-viewer-20-9.png")
	view.go_back(); check(not is_instance_valid(view._photo_viewer) and menu._profile_mode, "Back closes viewer before profile")
	if public_view:
		var response: Dictionary = await GameServices.scores().player(account_id)
		view.public_data = StrictData.dictionary(StrictData.dictionary(response.data).get("profile", {}))
		view.set_tab("gallery")
		check(view.body.find_child("AddGalleryPhoto", true, false) == null and view.body.find_child("RemoveGalleryPhoto_0", true, false) == null, "Public gallery has no edit controls")
		await capture("player-gallery-public-20-9.png")
	menu.queue_free()
	await create_timer(0.2).timeout

func warm_photos() -> void:
	var service: ProfileMediaService = GameServices.photos()
	var avatar: Dictionary = StrictData.dictionary(service.media.get("avatar", {}))
	var _avatar_texture: Texture2D = service.texture(str(avatar.get("url", "")))
	for item: Variant in StrictData.array(service.media.get("gallery", [])):
		var _texture: Texture2D = service.texture(str(StrictData.dictionary(item).get("url", "")))
	var deadline: int = Time.get_ticks_msec() + 12000
	while not service._fetching.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	while (service.busy or GameServices.session().busy) and Time.get_ticks_msec() < deadline: await process_frame
	check(service._textures.size() >= 6, "Avatar and all gallery textures decoded")

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/" + filename)

func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
