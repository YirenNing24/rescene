extends SceneTree

var updates: AppUpdateService
var failures: int = 0
var _pause_once: bool = false

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	updates = root.get_node("AppUpdates") as AppUpdateService
	updates.test_origin = OS.get_environment("RESCENE_UPDATE_TEST_ORIGIN")
	if updates.test_origin.is_empty(): quit(2); return
	var _created: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://update-regression"))
	var completed: FileAccess = FileAccess.open("user://update-regression/update-%d-probe.apk" % updates.current_code(), FileAccess.WRITE)
	var _written: bool = completed.store_string("Installed update cache")
	completed.close()
	updates._cleanup_installed()
	check(not FileAccess.file_exists("user://update-regression/update-%d-probe.apk" % updates.current_code()), "Installed update caches must be cleaned up")
	for filename: String in DirAccess.get_files_at("user://update-regression"):
		var _old_removed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path("user://update-regression/" + filename))
	await set_mode("normal")
	await updates.check()
	check(updates.available() and updates.phase == "available", "A newer valid release must be available")
	var untrusted: Dictionary = updates.release.duplicate()
	untrusted["signing_certificate_sha256"] = AppUpdateService.CERTIFICATE
	untrusted["download_url"] = "https://evil.invalid/game.apk"
	check(updates.validate_manifest(untrusted).is_empty(), "Manifest must never redirect downloads to another server")
	var _connected: int = updates.changed.connect(_on_changed)
	_pause_once = true
	await updates.download()
	check(updates.phase == "paused" and updates.downloaded > 0 and updates.downloaded < StrictData.integer(updates.release.bytes), "Pause must retain a partial download")
	var retained: int = updates.downloaded
	await updates.download()
	check(updates.phase == "ready", "Resume must complete and verify the same release")
	check(updates.downloaded > retained and FileAccess.get_sha256(updates._stem() + ".apk") == str(updates.release.sha256), "Downloaded APK must match the full SHA-256")
	var stats: Dictionary = await request_json("/stats")
	check(StrictData.boolean(stats.get("resumed", false)), "Resume must send a non-zero byte range")
	await set_mode("corrupt")
	await updates.check()
	await updates.download()
	check(updates.phase == "error" and updates.downloaded == 0 and not FileAccess.file_exists(updates._stem() + ".part"), "A corrupt download must be removed and never offered for installation")
	for scenario: String in ["bad_range", "full_response"]:
		await set_mode(scenario)
		await updates.check()
		await updates.download()
		check(updates.phase == "paused" and updates.downloaded == 0, "Invalid response framing must never append bytes: " + scenario)
	await set_mode("disconnect")
	await updates.check()
	await updates.download()
	check(updates.phase == "paused" and updates.downloaded > 0, "A connection loss must preserve already downloaded bytes")
	await set_mode("normal")
	await updates.download()
	check(updates.phase == "ready", "A disconnected download must resume without starting over")
	for filename: String in DirAccess.get_files_at("user://update-regression"):
		var _removed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path("user://update-regression/" + filename))
	print("App updater: pause/resume, range validation, corruption, interrupted connection: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)

func _on_changed() -> void:
	if _pause_once and updates.phase == "downloading" and updates.downloaded >= 131072:
		_pause_once = false
		updates.pause()

func set_mode(mode: String) -> void:
	var _response: Dictionary = await request_json("/control/" + mode)

func request_json(path: String) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	root.add_child(request)
	var error: Error = request.request(updates.test_origin + path)
	if error != OK: request.queue_free(); return {}
	var response: Array = await request.request_completed
	request.queue_free()
	var body: PackedByteArray = response[3]
	return StrictData.dictionary(JSON.parse_string(body.get_string_from_utf8()))

func check(passed: bool, description: String) -> void:
	if not passed:
		failures += 1
		push_error(description)
