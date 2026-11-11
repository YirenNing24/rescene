class_name ProfileMediaService
extends Node
## Server-owned photo references. Textures live only in the current account cache.
signal changed
signal texture_ready(path: String)
var media: Dictionary = {"avatar":null,"gallery":[],"gallery_limit":5}
var busy: bool = false
var uploading: bool = false
var message: String = ""
var _owner: String = ""
var _generation: int = 0
var _textures: Dictionary[String, Texture2D] = {}
var _fetching: Dictionary[String, bool] = {}
var _cache_pixels: int = 0

func _ready() -> void:
	var _connection: int = GameServices.session().session_ended.connect(func(_notice: String) -> void: clear())

func clear() -> void:
	_generation += 1; _owner = ""; busy = false; uploading = false; message = ""; _cache_pixels = 0
	media = {"avatar":null,"gallery":[],"gallery_limit":5}
	_textures.clear(); _fetching.clear(); changed.emit()

func _bind() -> void:
	var account_owner: String = GameServices.session().api_url() + "/" + str(GameServices.session().user.get("id", ""))
	if account_owner != _owner:
		clear(); _owner = account_owner

func refresh() -> void:
	if not GameServices.session().is_authenticated(): return
	_bind()
	if busy: return
	busy = true
	var generation: int = _generation
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/profile/media")
	if generation != _generation: return
	busy = false
	if response.ok: media = StrictData.dictionary(StrictData.dictionary(response.data).get("media", {}))
	else: message = str(response.get("message", "Photos could not be loaded."))
	changed.emit()

func texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if _textures.has(path): return _textures[path]
	if not _fetching.has(path):
		_fetching[path] = true
		_download.call_deferred(path, _generation)
	return null

func _download(path: String, generation: int) -> void:
	# Server-generated relative paths only; never send credentials to another host.
	if not path.begins_with("/api/v1/players/") or not path.contains("/media/"):
		var _invalid_removed: bool = _fetching.erase(path)
		return
	var response: Dictionary = await GameServices.session()._send(path, HTTPClient.METHOD_GET, {}, PackedByteArray(), "", true)
	if generation != _generation: return
	var _fetch_removed: bool = _fetching.erase(path)
	if not response.ok: return
	var image: Image = Image.new()
	var bytes: PackedByteArray = response.bytes
	if image.load_jpg_from_buffer(bytes) != OK: return
	_textures[path] = ImageTexture.create_from_image(image)
	_cache_pixels += image.get_width() * image.get_height()
	# Bound decoded image memory to about 64 MiB, plus images still displayed.
	while _textures.size() > 16 or _cache_pixels > 16777216:
		var keys: Array[String] = _textures.keys()
		var oldest: Texture2D = _textures[keys[0]]
		_cache_pixels -= oldest.get_width() * oldest.get_height()
		var _old_removed: bool = _textures.erase(keys[0])
	texture_ready.emit(path)

func upload(kind: String, path: String, replace_id: String = "") -> void:
	if busy: return
	_bind(); message = ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: message = "This photo could not be opened."; changed.emit(); return
	if file.get_length() > 8388608: file.close(); message = "Choose a JPG or PNG smaller than 8 MB."; changed.emit(); return
	var bytes: PackedByteArray = file.get_buffer(file.get_length()); file.close()
	if bytes.is_empty(): message = "Choose a valid JPG or PNG photo."; changed.emit(); return
	busy = true; uploading = true; changed.emit()
	var generation: int = _generation
	var route: String = "/api/v1/profile/media/" + kind + ("/" + replace_id if not replace_id.is_empty() else "")
	var response: Dictionary = await GameServices.session()._send(route, HTTPClient.METHOD_POST if replace_id.is_empty() else HTTPClient.METHOD_PUT, {}, bytes, "application/octet-stream")
	if generation != _generation: return
	busy = false; uploading = false
	if response.ok:
		media = StrictData.dictionary(StrictData.dictionary(response.data).get("media", {})); message = "Profile photo updated." if kind == "avatar" else "Gallery updated."
	else:
		message = str(response.get("message", "Photo upload failed."))
		# A lost response may follow a saved upload. Read server state once.
		await refresh()
	changed.emit()

func remove(kind: String, id: String) -> void:
	if busy or id.is_empty(): return
	_bind(); busy = true; changed.emit()
	var generation: int = _generation
	var response: Dictionary = await GameServices.session()._send("/api/v1/profile/media/%s/%s" % [kind, id.uri_encode()], HTTPClient.METHOD_DELETE)
	if generation != _generation: return
	busy = false
	if response.ok:
		media = StrictData.dictionary(StrictData.dictionary(response.data).get("media", {})); message = "Photo removed."
	else: message = str(response.get("message", "Photo could not be removed.")); await refresh()
	changed.emit()
