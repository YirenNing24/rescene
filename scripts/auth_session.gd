class_name ResceneAuthSession
extends Node
## Short-lived access JWTs plus rotating, server-owned 30-day refresh sessions.

signal session_ended(message: String)
signal wallet_updated

const PUBLIC_PATHS: Array[String] = ["/api/v1/auth/login", "/api/v1/auth/register", "/api/v1/auth/refresh", "/api/v1/auth/logout", "/api/v1/auth/recover"]
const REFRESH_EARLY_MS: int = 60000
const RETRY_MS: int = 30000

var user: Dictionary = {}
var busy: bool = false
var notice: String = ""
var _token: String = ""
var _refresh_token: String = ""
var _refresh_request_id: String = ""
var _refresh_expires_at: int = 0
var _expires_at_ms: int = 0
var _restoring: bool = false
var _generation: int = 0
var _next_refresh_attempt_ms: int = 0
var _refresh_early_ms: int = REFRESH_EARLY_MS

func session_file() -> String:
	var override_path: String = OS.get_environment("RESCENE_AUTH_FILE")
	return override_path if OS.is_debug_build() and not override_path.is_empty() else "user://auth_token_%s.txt" % api_url().sha256_text().left(16)

func _save_session() -> bool:
	var path: String = session_file()
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	if OS.has_feature("linux") or OS.has_feature("android"):
		var permission_error: Error = FileAccess.set_unix_permissions(path + ".tmp", 384) # Owner read/write (0600).
		if permission_error != OK:
			file.close()
			return false
	var written: bool = file.store_string(JSON.stringify({"version":2,"access_token":_token,"refresh_token":_refresh_token,"refresh_request_id":_refresh_request_id,"refresh_expires_at":_refresh_expires_at}))
	file.close()
	if not written: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK

func _delete_saved_session() -> void:
	for path: String in [session_file(), session_file() + ".tmp"]:
		if FileAccess.file_exists(path):
			var removal_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if removal_error != OK: notice = "Could not remove the saved login file."

func _token_expiry(token: String) -> int:
	# Only a migration hint; the server still verifies the signature and expiry.
	var parts: PackedStringArray = token.split(".")
	if parts.size() != 3: return 0
	var encoded: String = parts[1].replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0: encoded += "="
	var claims: Dictionary = StrictData.dictionary(JSON.parse_string(Marshalls.base64_to_utf8(encoded)))
	return StrictData.integer(claims.get("exp", 0))

func _accept_session(body: Dictionary) -> bool:
	var account: Dictionary = StrictData.dictionary(body.get("user"))
	var access: String = str(body.get("access_token", ""))
	var refresh: String = str(body.get("refresh_token", ""))
	var lifetime: int = StrictData.integer(body.get("expires_in", 0))
	if str(account.get("id", "")).is_empty() or access.is_empty() or refresh.length() != 43 or lifetime <= 0 or StrictData.integer(body.get("refresh_expires_in", 0)) <= 0:
		return false
	user = account
	_token = access
	_refresh_token = refresh
	_refresh_request_id = ""
	_refresh_expires_at = StrictData.integer(body.get("refresh_expires_at", 0))
	_expires_at_ms = Time.get_ticks_msec() + lifetime * 1000
	_refresh_early_ms = mini(REFRESH_EARLY_MS, lifetime * 100)
	_next_refresh_attempt_ms = 0
	notice = "" if _save_session() else "Signed in, but this device could not save your login."
	return true

func restore_session() -> Dictionary:
	if is_authenticated(): return {"ok":true}
	if busy or _restoring: return {"ok":false,"message":"A request is already in progress."}
	if not FileAccess.file_exists(session_file()): return {"ok":false,"message":""}
	var file: FileAccess = FileAccess.open(session_file(), FileAccess.READ)
	if file == null: return {"ok":false,"message":"Could not read your saved login. Please log in again."}
	var saved: String = file.get_as_text().strip_edges() if file.get_length() <= 16384 else ""
	file.close()
	var legacy: bool = not saved.begins_with("{")
	if legacy:
		_token = saved
		_refresh_token = ""
	else:
		var data: Dictionary = StrictData.dictionary(JSON.parse_string(saved))
		_token = str(data.get("access_token", ""))
		_refresh_token = str(data.get("refresh_token", ""))
		_refresh_request_id = str(data.get("refresh_request_id", ""))
		_refresh_expires_at = StrictData.integer(data.get("refresh_expires_at", 0))
	if _refresh_token.is_empty() and _token_expiry(_token) <= StrictData.integer(Time.get_unix_time_from_system()):
		logout("Your saved session has expired. Please log in again.")
		return {"ok":false,"message":notice}
	_generation += 1
	var generation: int = _generation
	_restoring = true
	busy = true
	var response: Dictionary
	if _refresh_token.is_empty():
		# Upgrade an old, still-valid JWT file without asking for the password.
		response = await _http("/api/v1/auth/session", HTTPClient.METHOD_POST, {}, _token)
		if generation == _generation and response.ok and not _accept_session(StrictData.dictionary(response.data)):
			response = {"ok":false,"message":"The server returned an invalid session."}
	else:
		response = await _refresh_locked(generation)
	busy = false
	_restoring = false
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	if response.ok: return {"ok":true,"user":user}
	user = {}
	_expires_at_ms = 0
	if StrictData.integer(response.get("status",0)) == 401:
		logout(str(response.get("message","Your saved login has expired. Please log in again.")))
	# Network failures keep the credentials and pending refresh ID for a retry.
	return response

func api_url() -> String:
	var configured: String = OS.get_environment("RESCENE_API_URL").strip_edges()
	if configured.is_empty(): configured = str(ProjectSettings.get_setting("rescene/api/base_url", "")).strip_edges()
	if configured.is_empty() and OS.is_debug_build():
		configured = "http://10.0.2.2:8080" if OS.has_feature("android") else "http://127.0.0.1:8080"
	return configured.trim_suffix("/")

func is_authenticated() -> bool:
	return not _token.is_empty() and not user.is_empty() and (Time.get_ticks_msec() < _expires_at_ms or not _refresh_token.is_empty())

func authenticate(username: String, password: String, register: bool = false, accept_policies: bool = false) -> Dictionary:
	var path: String = "/api/v1/auth/register" if register else "/api/v1/auth/login"
	var payload: Dictionary = {"username":username.strip_edges(),"password":password}
	if register:
		payload["accept_policies"] = accept_policies
		payload["terms_version"] = LegalPolicies.version()
		payload["privacy_version"] = LegalPolicies.version()
	var result: Dictionary = await _send(path, HTTPClient.METHOD_POST, payload)
	if not result.ok: return result
	if not _accept_session(StrictData.dictionary(result.data)): return {"ok":false,"message":"The server returned an invalid session."}
	_generation += 1
	return {"ok":true,"user":user}

func fetch_profile() -> Dictionary:
	return await authorized_request("/api/v1/auth/me")

func authorized_request(path: String) -> Dictionary:
	return await _send(path, HTTPClient.METHOD_GET)

func fetch_wallet(retry: bool = false) -> Dictionary:
	var generation: int = _generation
	var path: String = "/api/v1/wallet/provision" if retry else "/api/v1/wallet"
	var response: Dictionary = await _send(path, HTTPClient.METHOD_POST if retry else HTTPClient.METHOD_GET)
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	if response.ok and StrictData.dictionary(response.data).get("wallet") is Dictionary:
		user.wallet = response.data.wallet
		wallet_updated.emit()
	return response

func _wait_for_idle(generation: int) -> bool:
	while busy:
		await get_tree().process_frame
		if generation != _generation: return false
	return generation == _generation

func _refresh_locked(generation: int) -> Dictionary:
	if _refresh_token.is_empty(): return {"ok":false,"status":401,"message":"Please log in again."}
	if _refresh_request_id.is_empty():
		var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
		if random_bytes.size() != 16: return {"ok":false,"message":"Could not renew your saved login."}
		_refresh_request_id = random_bytes.hex_encode()
	# Persist the retry intent before rotating the credential on the server.
	if not _save_session(): return {"ok":false,"message":"Could not save your login before renewing it."}
	var response: Dictionary = await _http("/api/v1/auth/refresh",HTTPClient.METHOD_POST,{"refresh_token":_refresh_token,"request_id":_refresh_request_id})
	_next_refresh_attempt_ms = Time.get_ticks_msec() + RETRY_MS
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	if response.ok and not _accept_session(StrictData.dictionary(response.data)):
		return {"ok":false,"message":"The server returned an invalid session."}
	return response

func refresh_session() -> Dictionary:
	var generation: int = _generation
	if not await _wait_for_idle(generation): return {"ok":false,"message":"The account session changed."}
	if Time.get_ticks_msec() + _refresh_early_ms < _expires_at_ms: return {"ok":true}
	busy = true
	var response: Dictionary = await _refresh_locked(generation)
	busy = false
	if generation == _generation and StrictData.integer(response.get("status",0)) == 401:
		logout(str(response.message))
	return response

func start_gameplay_run(payload: Dictionary) -> Dictionary:
	# Wallet/catalog HTTP calls can take seconds. A run with a valid access token
	# must not queue behind them; credential rotation still uses the session lock.
	var generation: int = _generation
	if not is_authenticated(): return {"ok":false,"status":401,"message":"Please log in again."}
	if not _refresh_token.is_empty() and Time.get_ticks_msec() + _refresh_early_ms >= _expires_at_ms:
		var renewed: Dictionary = await refresh_session()
		if not renewed.ok: return renewed
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	var response: Dictionary = await _http("/api/v1/runs", HTTPClient.METHOD_POST, payload, _token)
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	if StrictData.integer(response.get("status", 0)) == 401:
		# Reuse the normal serialized refresh/retry path on a rejected credential.
		return await _send("/api/v1/runs", HTTPClient.METHOD_POST, payload)
	return response

func _send(path: String, method: HTTPClient.Method, payload: Dictionary = {}, raw: PackedByteArray = PackedByteArray(), content_type: String = "", binary_response: bool = false) -> Dictionary:
	var generation: int = _generation
	if not await _wait_for_idle(generation): return {"ok":false,"message":"The account session changed."}
	var authorized: bool = path not in PUBLIC_PATHS
	if authorized and not is_authenticated(): return {"ok":false,"status":401,"message":"Please log in again."}
	busy = true
	if authorized and not _refresh_token.is_empty() and Time.get_ticks_msec() + _refresh_early_ms >= _expires_at_ms:
		var renewed: Dictionary = await _refresh_locked(generation)
		if not renewed.ok:
			busy = false
			if generation == _generation and StrictData.integer(renewed.get("status",0)) == 401: logout(str(renewed.message))
			return renewed
	var response: Dictionary = await _http(path,method,payload,_token if authorized else "", "", raw, content_type, binary_response)
	if authorized and StrictData.integer(response.get("status",0)) == 401 and not _refresh_token.is_empty() and generation == _generation:
		var renewed: Dictionary = await _refresh_locked(generation)
		response = await _http(path,method,payload,_token,"",raw,content_type,binary_response) if renewed.ok else renewed
	busy = false
	if generation != _generation: return {"ok":false,"message":"The account session changed."}
	if authorized and StrictData.integer(response.get("status",0)) == 401: logout(str(response.message))
	return response

func _http(path: String, method: HTTPClient.Method, payload: Dictionary = {}, access: String = "", origin: String = "", raw: PackedByteArray = PackedByteArray(), content_type: String = "", binary_response: bool = false) -> Dictionary:
	var base: String = api_url() if origin.is_empty() else origin
	if not base.begins_with("https://") and not (OS.is_debug_build() and base.begins_with("http://")):
		return {"ok":false,"message":"Set the game's HTTPS API address before connecting."}
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 30.0 if not raw.is_empty() or path.begins_with("/api/v1/shop/") or path.begins_with("/api/v1/collection/") else 12.0
	request.body_size_limit = 4194304 if binary_response else (262144 if path.begins_with("/api/v1/social") else 65536)
	request.max_redirects = 0
	add_child(request)
	var headers: PackedStringArray = PackedStringArray(["Accept: image/jpeg" if binary_response else "Accept: application/json", "Content-Type: " + (content_type if not content_type.is_empty() else "application/json")])
	if not access.is_empty():
		var _header_added: bool = headers.append("Authorization: Bearer " + access)
	var error: Error = request.request_raw(base+path,headers,method,raw) if not content_type.is_empty() else request.request(base+path,headers,method,"" if method == HTTPClient.METHOD_GET else JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		return {"ok":false,"message":"Could not connect. Check your connection and try again."}
	var response: Array = await request.request_completed
	request.queue_free()
	if StrictData.integer(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok":false,"message":"Cannot reach the server. Check your connection and try again."}
	var bytes: PackedByteArray = response[3]
	var status: int = StrictData.integer(response[1])
	if binary_response and status >= 200 and status < 300: return {"ok":true,"bytes":bytes,"status":status}
	var decoded: Dictionary = StrictData.dictionary(JSON.parse_string(bytes.get_string_from_utf8()))
	if status >= 200 and status < 300 and not decoded.is_empty(): return {"ok":true,"data":decoded,"status":status}
	return {"ok":false,"status":status,"message":str(StrictData.dictionary(decoded.get("error")).get("message","The server could not complete your request. Please try again."))}

func logout(message: String = "") -> void:
	var refresh: String = _refresh_token
	var origin: String = api_url()
	_generation += 1
	_token = ""
	_refresh_token = ""
	_refresh_request_id = ""
	_refresh_expires_at = 0
	_expires_at_ms = 0
	notice = message
	_delete_saved_session()
	user = {}
	session_ended.emit(message)
	if not refresh.is_empty(): _revoke_refresh.call_deferred(refresh,origin)

func _revoke_refresh(refresh: String, origin: String) -> void:
	while busy: await get_tree().process_frame
	busy = true
	var _response: Dictionary = await _http("/api/v1/auth/logout",HTTPClient.METHOD_POST,{"refresh_token":refresh},"",origin)
	busy = false

func _process(_delta: float) -> void:
	if _restoring or user.is_empty() or busy: return
	if not _refresh_token.is_empty() and Time.get_ticks_msec() + _refresh_early_ms >= _expires_at_ms:
		if Time.get_ticks_msec() >= _next_refresh_attempt_ms:
			_next_refresh_attempt_ms = Time.get_ticks_msec() + RETRY_MS
			refresh_session.call_deferred()
	elif not _token.is_empty() and Time.get_ticks_msec() >= _expires_at_ms:
		logout("Your session has expired. Please log in again.")
