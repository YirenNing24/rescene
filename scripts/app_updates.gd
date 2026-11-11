class_name AppUpdateService
extends Node
## Public releases only. No player credentials are sent with update requests.
signal changed

const ORIGIN: String = "https://api.remineph.online"
const CERTIFICATE: String = "732a79726c4e08da0a2ccf7a26e56326288df5ccb53629a0eec315598371c299"
const DIRECTORY: String = "user://updates"
const MAX_BYTES: int = 1073741824

var phase: String = "idle"
var message: String = ""
var release: Dictionary = {}
var downloaded: int = 0
var dismissed_code: int = 0
var test_origin: String = "" # Accepted only in desktop debug regression runs.
var _client: HTTPClient
var _file: FileAccess
var _paused: bool = false
var _hash_thread: Thread

func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.1.6"))

func current_code() -> int:
	return StrictData.integer(ProjectSettings.get_setting("rescene/app/version_code", 7))

func _apk_name() -> String:
	return "RESCENE-Rhythm-emulator.apk" if OS.has_feature("android") and OS.has_feature("x86_64") else "RESCENE-Rhythm.apk"

func origin() -> String:
	if OS.is_debug_build() and not OS.has_feature("android") and test_origin.begins_with("http://127.0.0.1:"):
		return test_origin.trim_suffix("/")
	return ORIGIN

func available() -> bool:
	return StrictData.integer(release.get("version_code", 0)) > current_code()

func active() -> bool:
	return phase in ["checking", "downloading", "verifying"]

func _state(next: String, detail: String) -> void:
	phase = next
	message = detail
	changed.emit()

func validate_manifest(value: Variant) -> Dictionary:
	var data: Dictionary = StrictData.dictionary(value)
	var version: String = str(data.get("version", ""))
	var pattern: RegEx = RegEx.create_from_string("^[0-9]{1,6}\\.[0-9]{1,6}\\.[0-9]{1,6}$")
	var checksum: String = str(data.get("sha256", ""))
	var code: int = StrictData.integer(data.get("version_code", 0))
	var bytes: int = StrictData.integer(data.get("bytes", 0))
	var url: String = origin() + "/updates/android/" + version + "/" + _apk_name()
	if pattern.search(version) == null or checksum.length() != 64 or not checksum.is_valid_hex_number(false): return {}
	if code <= 0 or code > 1000000000 or bytes <= 0 or bytes > MAX_BYTES: return {}
	if StrictData.number(data.get("version_code", 0)) != float(code) or StrictData.number(data.get("bytes", 0)) != float(bytes): return {}
	if str(data.get("signing_certificate_sha256", "")) != CERTIFICATE or str(data.get("download_url", "")) != url: return {}
	return {"version":version, "version_code":code, "bytes":bytes, "sha256":checksum.to_lower(), "download_url":url, "release_notes":str(data.get("release_notes", "")).left(2000)}

func check() -> void:
	if active(): return
	_state("checking", "Checking for updates…")
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 20.0
	request.max_redirects = 0
	request.body_size_limit = 65536
	add_child(request)
	var query: String = "?arch=x86_64" if _apk_name().contains("emulator") else ""
	var error: Error = request.request(origin() + "/updates/android.json" + query, PackedStringArray(["Accept: application/json", "Cache-Control: no-cache"]))
	if error != OK:
		request.queue_free()
		_state("error", "Could not check for updates. Please try again.")
		return
	var response: Array = await request.request_completed
	request.queue_free()
	if StrictData.integer(response[0]) != HTTPRequest.RESULT_SUCCESS or StrictData.integer(response[1]) != 200:
		_state("error", "Could not check for updates. Please try again.")
		return
	var body: PackedByteArray = response[3]
	var next_release: Dictionary = validate_manifest(JSON.parse_string(body.get_string_from_utf8()))
	if next_release.is_empty():
		_state("error", "The update information could not be verified. Please try again later.")
		return
	release = next_release
	if not available(): _cleanup_installed()
	downloaded = _partial_size()
	_state("available" if available() else "current", "Version %s is available." % str(release.version) if available() else "You’re up to date.")

func _stem() -> String:
	return "%s/update-%d-%s" % [_directory(), StrictData.integer(release.get("version_code", 0)), str(release.get("sha256", "")).left(16)]

func _directory() -> String:
	return "user://update-regression" if OS.is_debug_build() and not OS.has_feature("android") and not test_origin.is_empty() else DIRECTORY

func _cleanup_installed() -> void:
	var directory: String = _directory()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)): return
	for filename: String in DirAccess.get_files_at(directory):
		var code: String = filename.get_slice("-", 1)
		if filename.begins_with("update-") and code.is_valid_int() and code.to_int() <= current_code() and filename.get_extension() in ["apk", "part"]:
			var _removed_installed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(directory + "/" + filename))

func _partial_size() -> int:
	var path: String = _stem() + ".part"
	if not FileAccess.file_exists(path): return 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var length: int = file.get_length()
	file.close()
	return length

func _close_download() -> void:
	if _client != null: _client.close()
	_client = null
	if _file != null:
		_file.flush()
		_file.close()
	_file = null

func pause() -> void:
	if phase == "downloading":
		_paused = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED: pause()

func _exit_tree() -> void:
	_close_download()
	if _hash_thread != null and _hash_thread.is_started():
		var _result: Variant = _hash_thread.wait_to_finish()

func _interrupted(detail: String) -> void:
	_close_download()
	downloaded = _partial_size()
	_state("paused", detail)

func download() -> void:
	if active() or not available(): return
	var directory: String = _directory()
	var folder_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if folder_error != OK:
		_state("error", "Could not create the update folder. Check your free storage.")
		return
	# Only our own previous update files; never touch login or player data.
	for filename: String in DirAccess.get_files_at(directory):
		if filename.begins_with("update-") and filename.get_extension() in ["part", "apk"] and not (directory + "/" + filename).begins_with(_stem() + "."):
			var _removed_old: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(directory + "/" + filename))
	if FileAccess.file_exists(_stem() + ".apk"):
		if await _verify(_stem() + ".apk"): _state("ready", "Download verified. Ready to install.")
		else: _state("error", "The saved download failed verification. Tap Download to try again.")
		return
	downloaded = _partial_size()
	var total: int = StrictData.integer(release.bytes)
	if downloaded > total:
		var _removed_invalid: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_stem() + ".part"))
		downloaded = 0
	if downloaded == total:
		await _finish_download()
		return
	_paused = false
	_state("downloading", "Downloading update…")
	_client = HTTPClient.new()
	_client.read_chunk_size = 65536
	var base: String = origin()
	var address: PackedStringArray = base.trim_prefix("https://").trim_prefix("http://").split(":")
	var secure: bool = base.begins_with("https://")
	var port: int = 443 if secure else address[1].to_int()
	var tls: TLSOptions = TLSOptions.client() if secure else null
	var connect_error: Error = _client.connect_to_host(address[0], port, tls)
	if connect_error != OK:
		_interrupted("Could not connect. Tap Resume to try again.")
		return
	var requested: bool = false
	var headers_checked: bool = false
	var offset: int = downloaded
	var last_activity: int = Time.get_ticks_msec()
	while is_inside_tree() and phase == "downloading":
		if _paused:
			_interrupted("Download paused. Tap Resume to continue.")
			return
		var poll_error: Error = _client.poll()
		var status: HTTPClient.Status = _client.get_status()
		if poll_error != OK or status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
			_interrupted("Connection interrupted. Tap Resume to continue.")
			return
		if status == HTTPClient.STATUS_CONNECTED and not requested:
			var request_error: Error = _client.request(HTTPClient.METHOD_GET, "/updates/android/%s/%s" % [str(release.version), _apk_name()], PackedStringArray(["Range: bytes=%d-" % offset, "Accept-Encoding: identity"]))
			if request_error != OK:
				_interrupted("Could not start the download. Tap Resume to try again.")
				return
			requested = true
			last_activity = Time.get_ticks_msec()
		if _client.has_response() and not headers_checked:
			var content_range: String = ""
			for header: String in _client.get_response_headers():
				var parts: PackedStringArray = header.split(":", true, 1)
				if parts.size() == 2 and parts[0].to_lower() == "content-range": content_range = parts[1].strip_edges()
			if _client.get_response_code() != 206 or content_range != "bytes %d-%d/%d" % [offset, total - 1, total]:
				_interrupted("The download response could not be verified. Please retry.")
				return
			headers_checked = true
			_file = FileAccess.open(_stem() + ".part", FileAccess.READ_WRITE if FileAccess.file_exists(_stem() + ".part") else FileAccess.WRITE_READ)
			if _file == null:
				_interrupted("Could not save the update. Check your free storage.")
				return
			_file.seek_end()
		if headers_checked:
			var frame_bytes: int = 0
			while _client.get_status() == HTTPClient.STATUS_BODY and frame_bytes < 1048576:
				var chunk: PackedByteArray = _client.read_response_body_chunk()
				if chunk.is_empty(): break
				if downloaded + chunk.size() > total or not _file.store_buffer(chunk):
					_interrupted("Could not save the update safely. Check your free storage and retry.")
					return
				downloaded += chunk.size()
				frame_bytes += chunk.size()
				last_activity = Time.get_ticks_msec()
			changed.emit()
			if downloaded == total:
				_close_download()
				await _finish_download()
				return
			if _client.get_status() in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
				_interrupted("Connection interrupted. Tap Resume to continue.")
				return
		if Time.get_ticks_msec() - last_activity > 30000:
			_interrupted("The download timed out. Tap Resume to continue.")
			return
		await get_tree().process_frame
	_close_download()

func _hash_file(path: String) -> String:
	return FileAccess.get_sha256(path)

func _verify(path: String) -> bool:
	_state("verifying", "Verifying download…")
	_hash_thread = Thread.new()
	var error: Error = _hash_thread.start(_hash_file.bind(path))
	if error != OK: return false
	while _hash_thread.is_alive(): await get_tree().process_frame
	var digest: String = str(_hash_thread.wait_to_finish())
	_hash_thread = null
	var valid: bool = digest == str(release.sha256)
	if not valid:
		var _removed_corrupt: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		downloaded = 0
	return valid

func _finish_download() -> void:
	if not await _verify(_stem() + ".part"):
		_state("error", "Download verification failed. Tap Download to try again.")
		return
	var error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(_stem() + ".part"), ProjectSettings.globalize_path(_stem() + ".apk"))
	_state("ready" if error == OK else "error", "Download verified. Ready to install." if error == OK else "Could not prepare the update. Please retry.")

func install() -> void:
	if phase != "ready" or not OS.has_feature("android"): return
	if not await _verify(_stem() + ".apk"):
		_state("error", "The download failed verification. Download it again.")
		return
	var error: Error = OS.shell_open(ProjectSettings.globalize_path(_stem() + ".apk"))
	_state("ready", "Allow RESCÉNE Rhythm to install updates if Android asks, then confirm Update. If you returned from Settings, tap Install again." if error == OK else "Android could not open the installer. Please try again.")
