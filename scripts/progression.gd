class_name ProgressionService
extends Node
## Server-owned progression; durable completion queue is scoped to API + account.

signal changed
signal run_rewarded(run_id: String, reward: Dictionary)

var state: Dictionary = {}
var run_card: Dictionary = {}
var run_rival: Dictionary = {}
var run_deck_ids: Array[String] = []
var loading: bool = false
var error_message: String = ""
var _owner: String = ""
var _pending: Array = []
var _working: bool = false
var _generation: int = 0
var _event_unix: int = 0
var _event_tick: int = 0
var _daily_clock: float = 0.0
var _reset_ticks: int = 0
var _energy_ticks: int = 0
var _energy_refresh_after: int = 0
var _pending_start: Dictionary = {}
var _begin_busy: bool = false
var starlight_wallet: Dictionary = {}
var _starlight_loading: bool = false
var _starlight_refresh_ticks: int = 0

func _ready() -> void:
	var _int_1: int = GameServices.session().session_ended.connect(func(_message: String) -> void:
		_generation += 1
		state = {}
		run_card = {}
		run_rival = {}
		run_deck_ids.clear()
		starlight_wallet = {}
		_starlight_refresh_ticks = 0
		_reset_ticks = 0
		_energy_ticks = 0
		_owner = ""
		_pending = []
		_pending_start = {}
		_begin_busy = false
		error_message = ""
		changed.emit())

func _account_key() -> String:
	return (GameServices.session().api_url() + "/" + str(GameServices.session().user.get("id", ""))).sha256_text()

func _queue_path() -> String:
	return "user://pending_progression_%s.json" % _owner

func _bind_account() -> void:
	var key: String = _account_key()
	if key == _owner: return
	_generation += 1
	_owner = key
	state = {}
	run_card.clear(); run_rival.clear(); run_deck_ids.clear()
	starlight_wallet = {}
	_starlight_refresh_ticks = 0
	_reset_ticks = 0
	_energy_ticks = 0
	_energy_refresh_after = 0
	_pending = []
	_pending_start = {}
	_begin_busy = false
	if FileAccess.file_exists(_start_path()):
		var start_file: FileAccess = FileAccess.open(_start_path(), FileAccess.READ)
		if start_file != null and start_file.get_length() < 4096:
			_pending_start = StrictData.dictionary(JSON.parse_string(start_file.get_as_text()))
	if FileAccess.file_exists(_queue_path()):
		var file: FileAccess = FileAccess.open(_queue_path(), FileAccess.READ)
		if file != null and file.get_length() < 2097152:
			var saved: Variant = JSON.parse_string(file.get_as_text())
			if saved is Array: _pending = saved

func _save_queue() -> void:
	if _owner.is_empty(): return
	if _pending.is_empty():
		var _error_2: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_queue_path()))
		return
	var file: FileAccess = FileAccess.open(_queue_path()+".tmp", FileAccess.WRITE)
	if file != null:
		var _bool_3: bool = file.store_string(JSON.stringify(_pending))
		file.close()
		var _error_4: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(_queue_path()+".tmp"),ProjectSettings.globalize_path(_queue_path()))

func _request(path: String, method: HTTPClient.Method, body: Dictionary = {}) -> Dictionary:
	var generation: int = _generation
	while _working or GameServices.session().busy:
		await get_tree().process_frame
		if generation != _generation or not GameServices.session().is_authenticated(): return {"ok":false, "message":"Please log in again."}
	if not GameServices.session().is_authenticated(): return {"ok":false, "message":"Please log in again."}
	_working = true
	var response: Dictionary = await GameServices.session()._send(path, method, body)
	_working = false
	if generation != _generation: return {"ok":false, "message":"The account session changed."}
	if response.ok:
		if StrictData.dictionary(response.data).get("progression") is Dictionary:
			state = response.data.progression
			var energy: Dictionary = StrictData.dictionary(state.get("energy", {}))
			_energy_ticks = Time.get_ticks_msec() + StrictData.integer(energy.get("next_recovery_in_seconds", 0)) * 1000 if energy.get("next_recovery_at") != null else 0
			var server_time: String = str(state.get("server_time", ""))
			if not server_time.is_empty():
				_event_unix = Time.get_unix_time_from_datetime_string(server_time.split(".")[0].trim_suffix("Z"))
				_event_tick = Time.get_ticks_msec()
				var remaining: int = Time.get_unix_time_from_datetime_string(str(state.daily_reset_at)) - Time.get_unix_time_from_datetime_string(server_time)
				_reset_ticks = Time.get_ticks_msec() + StrictData.integer(remaining * 1000)
			error_message = ""
			changed.emit()
			_refresh_starlight.call_deferred()
	else:
		error_message = response.get("message", "Progress could not be synced.")
	return response

func refresh() -> void:
	if not GameServices.session().is_authenticated() or loading: return
	_bind_account()
	loading = true
	await _flush_pending()
	await _request("/api/v1/progression", HTTPClient.METHOD_GET)
	loading = false
	changed.emit()

func begin_run(song_id: String, difficulty: String) -> String:
	if not GameServices.session().is_authenticated(): return ""
	_bind_account()
	if _begin_busy: return ""
	_begin_busy = true
	var generation: int = _generation
	var run_id: String = await _begin_run(song_id, difficulty)
	if generation == _generation: _begin_busy = false
	return run_id

func _start_path() -> String:
	return "user://pending_start_%s.json" % _owner

func _save_pending_start() -> bool:
	if _pending_start.is_empty():
		if not FileAccess.file_exists(_start_path()): return true
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(_start_path())) == OK
	var file: FileAccess = FileAccess.open(_start_path() + ".tmp", FileAccess.WRITE)
	if file == null: return false
	var written: bool = file.store_string(JSON.stringify(_pending_start))
	file.close()
	return written and DirAccess.rename_absolute(ProjectSettings.globalize_path(_start_path() + ".tmp"), ProjectSettings.globalize_path(_start_path())) == OK

func _begin_run(song_id: String, difficulty: String) -> String:
	var generation: int = _generation
	await _flush_pending()
	if generation != _generation: return ""
	# Never replace the server's active ticket before a pending result is delivered.
	if not _pending.is_empty():
		error_message = "Your previous result is still syncing. Please reconnect before starting another song."
		return ""
	var chart: Dictionary = RhythmChart.load_chart(song_id, difficulty)
	if _pending_start.get("song_id", "") != song_id or _pending_start.get("difficulty", "") != difficulty or _pending_start.get("revision", "") != str(chart.get("revision", "")):
		var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
		if random_bytes.size() != 16: error_message = "Could not prepare this song attempt."; return ""
		_pending_start = {"request_id":random_bytes.hex_encode(), "song_id":song_id, "difficulty":difficulty, "revision":str(chart.get("revision", "")), "replay_version":RhythmJudge.REPLAY_VERSION}
	if not _save_pending_start(): error_message = "Could not save this song attempt. Please try again."; return ""
	var body: Dictionary = {"request_id":str(_pending_start.request_id), "song_id":song_id, "difficulty":difficulty, "revision":str(chart.get("revision", "")), "replay_version":RhythmJudge.REPLAY_VERSION}
	var response: Dictionary = await _request("/api/v1/runs", HTTPClient.METHOD_POST, body)
	if generation != _generation: return ""
	if response.ok or StrictData.integer(response.get("status", 0)) in [400, 404, 409]:
		_pending_start = {}
		var _start_removed: bool = _save_pending_start()
	if response.ok and StrictData.dictionary(response.data).get("reward") is Dictionary:
		run_card = StrictData.dictionary(StrictData.dictionary(response.data.reward).get("card")).duplicate(true)
		run_rival = StrictData.dictionary(StrictData.dictionary(response.data.reward).get("rival")).duplicate(true)
		run_deck_ids.clear()
		for value: Variant in StrictData.array(StrictData.dictionary(response.data.reward).get("deck_ids", [])): run_deck_ids.append(str(value))
		return str(StrictData.dictionary(response.data.reward).get("id", ""))
	if StrictData.integer(response.get("status", 0)) == 409:
		var message: String = error_message
		await refresh()
		if generation == _generation: error_message = message
	return ""

func finish_run(run_id: String, result: Dictionary) -> void:
	if run_id.is_empty() or not GameServices.session().is_authenticated(): return
	_bind_account()
	for item: Dictionary in _pending:
		if item is Dictionary and item.get("id") == run_id: return
	_pending.append({"id":run_id, "result":result})
	_save_queue()
	await _flush_pending()

func _flush_pending() -> void:
	# Concurrent refresh/start calls may send a receipt twice; the API is idempotent.
	var generation: int = _generation
	for item: Dictionary in _pending.duplicate(true):
		if StrictData.boolean(item.get("abandon", false)):
			var abandoned: Dictionary = await _request("/api/v1/runs/%s/abandon" % str(item.get("id", "")).uri_encode(), HTTPClient.METHOD_POST)
			if generation != _generation: return
			if StrictData.boolean(abandoned.get("ok", false)) or StrictData.integer(abandoned.get("status", 0)) in [400, 404, 409]:
				_pending.erase(item); _save_queue()
			else: break
			continue
		if not item is Dictionary or not item.get("result") is Dictionary or str(item.get("id", "")).is_empty():
			_pending.erase(item)
			continue
		# Godot parses JSON numbers as floats. Restore integer fields before sending
		# a queued result to Go's strictly typed request decoder after a restart.
		var counts: Dictionary = {}
		var saved_counts: Variant = StrictData.dictionary(item.result).get("counts", {})
		if saved_counts is Dictionary:
			for kind: String in ["PERFECT", "GREAT", "GOOD", "MISS"]:
				counts[kind] = StrictData.integer(StrictData.dictionary(saved_counts).get(kind, -1))
		var payload: Dictionary = {"score":StrictData.integer(StrictData.dictionary(item.result).get("score", -1)),"max_combo":StrictData.integer(StrictData.dictionary(item.result).get("max_combo", -1)),"counts":counts}
		if StrictData.dictionary(item.result).has("trace"): payload.trace = str(item.result.trace)
		if StrictData.dictionary(item.result).get("replay") is Dictionary:
			var saved: Dictionary = item.result.replay
			var events: Array = []
			for event: Variant in saved.get("events", []):
				if event is Array:
					var converted: Array = []
					for value: Variant in event: converted.append(StrictData.integer(value))
					events.append(converted)
			payload.replay = {"version":StrictData.integer(saved.get("version",0)),"run_id":str(saved.get("run_id","")),"revision":str(saved.get("revision","")),"end_us":StrictData.integer(saved.get("end_us",0)),"events":events}
		var response: Dictionary = await _request("/api/v1/runs/%s/complete" % str(item.id).uri_encode(), HTTPClient.METHOD_POST, payload)
		if generation != _generation: return
		if response.ok:
			_pending.erase(item)
			_save_queue()
			run_rewarded.emit(str(item.id), response.data.reward)
		elif StrictData.integer(response.get("status", 0)) in [400, 404, 409, 413]:
			_pending.erase(item)
			_save_queue()
			run_rewarded.emit(str(item.id), {"error":response.message})
		else:
			run_rewarded.emit(str(item.id), {"pending":true})
			break

func claim(mission_id: String, day: String) -> Dictionary:
	return await _request("/api/v1/missions/%s/claim" % mission_id.uri_encode(), HTTPClient.METHOD_POST, {"day":day})

func claim_daily_login(date: String, day: int) -> Dictionary:
	_bind_account()
	var response: Dictionary = await _request("/api/v1/daily-login/claim", HTTPClient.METHOD_POST, {"date":date, "day":day})
	if StrictData.integer(response.get("status", 0)) == 409: await refresh()
	return response

func daily_reset_seconds() -> int:
	if _reset_ticks == 0: return -1
	return maxi(0, ceili(StrictData.number(_reset_ticks - Time.get_ticks_msec()) / 1000.0))

func energy_recovery_seconds() -> int:
	if _energy_ticks == 0: return -1
	return maxi(0, ceili(float(_energy_ticks - Time.get_ticks_msec()) / 1000.0))

func energy_text() -> String:
	var energy: Dictionary = StrictData.dictionary(state.get("energy", {}))
	return "%d/%d" % [StrictData.integer(energy.get("current", 0)), StrictData.integer(energy.get("max", 15))] if not energy.is_empty() else "—/15"

func energy_hint() -> String:
	var seconds: int = energy_recovery_seconds()
	if state.get("energy") == null: return ""
	if seconds < 0: return "FULL"
	if seconds == 0: return "SYNCING…"
	return "+1 IN %02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]

func equip(cosmetic_id: String) -> Dictionary:
	return await _request("/api/v1/progression/equip", HTTPClient.METHOD_POST, {"id":cosmetic_id})

func equipped_title() -> String:
	for item: Dictionary in state.get("unlocks", []):
		if item.kind == "title" and item.equipped: return item.name
	return "First Scene"

func frame_color() -> Color:
	for item: Dictionary in state.get("unlocks", []):
		if item.kind == "frame" and item.equipped: return Color(str(item.color))
	return Color("c7bbff")

func starlight_text() -> String:
	var token: Dictionary = StrictData.dictionary(state.get("starlight_token"))
	if not StrictData.boolean(token.get("enabled", false)):
		return str(StrictData.integer(state.get("starlight", 0)))
	return str(starlight_wallet.get("balance", "…"))

func starlight_hint() -> String:
	var pending: String = str(starlight_wallet.get("pending", "0"))
	if pending != "0": return "%s Starlight arriving in your wallet" % pending
	return "Starlight in your wallet" if starlight_wallet.get("status", "") == "ready" else "Your Starlight balance is updating"

func _refresh_starlight() -> void:
	if _starlight_loading or not GameServices.session().is_authenticated(): return
	if not StrictData.boolean(StrictData.dictionary(state.get("starlight_token")).get("enabled", false)): return
	var generation: int = _generation
	_starlight_loading = true
	_starlight_refresh_ticks = Time.get_ticks_msec() + 15000
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/starlight")
	_starlight_loading = false
	if generation != _generation: return
	if StrictData.boolean(response.get("ok", false)):
		starlight_wallet = StrictData.dictionary(StrictData.dictionary(response.get("data")).get("starlight"))
		_starlight_refresh_ticks = Time.get_ticks_msec() + (5000 if str(starlight_wallet.get("pending", "0")) != "0" or str(starlight_wallet.get("status", "")) == "wallet_pending" else 30000)
		changed.emit()

func _process(delta: float) -> void:
	_daily_clock += delta
	if _daily_clock < 1.0: return
	_daily_clock = 0.0
	if not GameServices.session().is_authenticated() or state.is_empty(): return
	if Time.get_ticks_msec() >= _starlight_refresh_ticks: _refresh_starlight.call_deferred()
	if energy_recovery_seconds() == 0 and Time.get_ticks_msec() >= _energy_refresh_after and not loading:
		_energy_refresh_after = Time.get_ticks_msec() + 30000
		refresh.call_deferred()
	elif daily_reset_seconds() == 0 and not loading and Time.get_ticks_msec() >= _energy_refresh_after:
		_energy_refresh_after = Time.get_ticks_msec() + 30000
		refresh.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree() and GameServices.session().is_authenticated():
		refresh.call_deferred()

func abandon_run(run_id: String) -> void:
	if run_id.is_empty() or not GameServices.session().is_authenticated(): return
	_bind_account()
	for item: Dictionary in _pending:
		if str(item.get("id", "")) == run_id: return
	_pending.append({"id":run_id, "abandon":true})
	_save_queue()
	await _flush_pending()

func event_seconds(deadline: String) -> int:
	if _event_unix == 0: return 0
	var now: int = _event_unix + floori(float(Time.get_ticks_msec()-_event_tick)/1000.0)
	return maxi(0,Time.get_unix_time_from_datetime_string(deadline.trim_suffix("Z"))-now)

func claim_event(event_id: String, mission_id: String) -> Dictionary:
	return await _request("/api/v1/events/%s/missions/%s/claim" % [event_id.uri_encode(),mission_id.uri_encode()],HTTPClient.METHOD_POST,{})

func claim_mastery(song_id: String, mission_id: String) -> Dictionary:
	return await _request("/api/v1/mastery/%s/%s/claim" % [song_id.uri_encode(),mission_id.uri_encode()],HTTPClient.METHOD_POST,{})

func next_mastery(song_id: String, difficulty: String) -> String:
	var all: Dictionary = StrictData.dictionary(state.get("mastery",{}))
	var mastery: Dictionary = StrictData.dictionary(all.get(song_id,{}))
	var clears: Dictionary = StrictData.dictionary(mastery.get("clears",{}))
	if not StrictData.boolean(clears.get(difficulty,false)): return "CLEAR " + difficulty.to_upper()
	if StrictData.integer(mastery.get("best_accuracy",0)) < 9000: return "REACH 90% ACCURACY"
	if not StrictData.boolean(mastery.get("full_combo",false)): return "FULL COMBO ANY DIFFICULTY"
	for value: String in ["Easy","Normal","Hard","Ultra Hard"]:
		if not StrictData.boolean(clears.get(value,false)): return "CLEAR " + value.to_upper()
	return "ALL MASTERY GOALS COMPLETE"
