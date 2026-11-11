class_name SocialService
extends Node
signal notification_received(kind: String, peer_id: String)
signal typing_changed(peer_id: String)
signal changed
signal people_changed
signal conversation_changed(peer_id: String, older: bool)
signal message_sent(peer_id: String, text: String)

var summary: Dictionary = {"counts":{},"online_friends":[],"conversations":[],"unread":0}
var people: Array[Dictionary] = []
var next_cursor: String = ""
var messages: Dictionary[String, Array] = {}
var peers: Dictionary[String, Dictionary] = {}
var has_older: Dictionary[String, bool] = {}
var active_peer: String = ""
var active_view: int = 0
var message: String = ""
var loading_people: bool = false
var typing_until: Dictionary[String, int] = {}
var _event_cursor: String = ""
var _events_running: bool = false
var _events_retry: int = 0
var _typing_next: int = 0
var _owner: String = ""
var _generation: int = 0
var _device: String = ""
var _next_pulse: int = 0
var _next_poll: int = 0
var _foreground: bool = true
var _pulse_running: bool = false
var _summary_running: bool = false
var _thread_running: bool = false
var _sending: bool = false
var _people_generation: int = 0
var _last_access: String = ""
var _last_origin: String = ""
var _pending: Dictionary[String, Dictionary] = {}

func _ready() -> void:
	_device = Crypto.new().generate_random_bytes(16).hex_encode()
	var _logout: int = GameServices.session().session_ended.connect(func(_notice: String) -> void: clear())

func clear() -> void:
	if not _owner.is_empty() and not _last_access.is_empty(): _offline.call_deferred(_last_access, _last_origin, _device)
	_generation += 1; _people_generation += 1; _owner = ""; _last_access = ""; _last_origin = ""
	active_peer = ""; _pulse_running = false; _summary_running = false; _thread_running = false; _sending = false
	_next_pulse = 0; _next_poll = 0; loading_people = false; message = ""
	summary = {"counts":{},"online_friends":[],"conversations":[],"unread":0}
	_event_cursor = ""; _events_running = false; _events_retry = 0; typing_until.clear()
	people.clear(); messages.clear(); peers.clear(); has_older.clear(); _pending.clear()
	changed.emit(); people_changed.emit()

func _bind() -> void:
	var account_owner: String = GameServices.session().api_url() + "/" + str(GameServices.session().user.get("id", ""))
	if _owner != account_owner:
		clear(); _owner = account_owner; _device = Crypto.new().generate_random_bytes(16).hex_encode()

func _process(_delta: float) -> void:
	if not GameServices.session().is_authenticated(): return
	_bind()
	if not _foreground: return
	var now: int = Time.get_ticks_msec()
	if now >= _events_retry and not _events_running: _listen_events.call_deferred()
	for peer_id: String in typing_until.keys():
		if now >= typing_until[peer_id]:
			var _removed: bool = typing_until.erase(peer_id)
			typing_changed.emit(peer_id)
	if now >= _next_pulse and not _pulse_running:
		_next_pulse = now + 30000
		pulse.call_deferred()
	if not active_peer.is_empty() and now >= _next_poll and not _thread_running:
		_next_poll = now + 15000
		poll_thread.call_deferred(active_peer)

func pulse() -> void:
	if _pulse_running or not GameServices.session().is_authenticated(): return
	_bind(); _pulse_running = true
	var generation: int = _generation
	_last_access = GameServices.session()._token; _last_origin = GameServices.session().api_url()
	var _response: Dictionary = await GameServices.session()._send("/api/v1/social/presence", HTTPClient.METHOD_POST, {"device_id":_device,"online":_foreground,"activity":"lobby"})
	if generation != _generation: return
	_last_access = GameServices.session()._token
	_pulse_running = false
	if _foreground:
		await refresh()
		await _retry_pending()

func _offline(access: String, origin: String, device: String) -> void:
	var _response: Dictionary = await GameServices.session()._http("/api/v1/social/presence", HTTPClient.METHOD_POST, {"device_id":device,"online":false,"activity":""}, access, origin)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
		if not _last_access.is_empty(): _offline.call_deferred(_last_access, _last_origin, _device)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true; _next_pulse = 0; _next_poll = 0

func refresh() -> void:
	if _summary_running or not GameServices.session().is_authenticated(): return
	_bind(); _summary_running = true
	var generation: int = _generation
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/social")
	if generation != _generation: return
	_summary_running = false
	if response.ok:
		summary = StrictData.dictionary(StrictData.dictionary(response.data).get("social", {})); changed.emit()

func load_people(kind: String, query: String = "", more: bool = false) -> void:
	_bind(); _people_generation += 1
	var generation: int = _generation
	var request_generation: int = _people_generation
	loading_people = true
	if not more: people.clear(); next_cursor = ""
	people_changed.emit()
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/social/players?kind=%s&q=%s&cursor=%s" % [kind.uri_encode(), query.uri_encode(), next_cursor.uri_encode()])
	if generation != _generation or request_generation != _people_generation: return
	loading_people = false
	if response.ok:
		for raw: Variant in StrictData.array(StrictData.dictionary(response.data).get("players", [])): people.append(StrictData.dictionary(raw))
		next_cursor = str(StrictData.dictionary(response.data).get("next_cursor", "")); message = ""
	else: message = str(response.get("message", "Players could not be loaded."))
	people_changed.emit()

func player_action(peer_id: String, action: String, enabled: bool) -> Dictionary:
	var generation: int = _generation
	var response: Dictionary = await GameServices.session()._send("/api/v1/social/players/%s/%s" % [peer_id.uri_encode(), action], HTTPClient.METHOD_POST, {"enabled":enabled})
	if generation != _generation: return {"ok":false}
	if response.ok:
		var peer: Dictionary = StrictData.dictionary(StrictData.dictionary(response.data).get("player", {}))
		peers[peer_id] = peer
		for index: int in people.size():
			if str(people[index].get("id", "")) == peer_id: people[index] = peer
		people_changed.emit(); conversation_changed.emit(peer_id, false)
		await refresh()
	else: message = str(response.get("message", "This action could not be completed."))
	return response

func open_chat(peer: Dictionary) -> void:
	active_peer = str(peer.get("id", "")); peers[active_peer] = peer
	_next_poll = Time.get_ticks_msec() + 2500
	poll_thread.call_deferred(active_peer)

func poll_thread(peer_id: String, older: bool = false) -> void:
	if _thread_running or peer_id.is_empty(): return
	_thread_running = true
	var generation: int = _generation
	var current: Array = messages.get(peer_id, [])
	var after: int = StrictData.integer(StrictData.dictionary(current.back()).get("seq", 0)) if not current.is_empty() and not older else 0
	var before: int = StrictData.integer(StrictData.dictionary(current.front()).get("seq", 0)) if not current.is_empty() and older else 0
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/social/conversations/%s?after=%d&before=%d" % [peer_id.uri_encode(), after, before])
	if generation != _generation: return
	_thread_running = false
	if not response.ok: message = str(response.get("message", "Chat could not be loaded.")); conversation_changed.emit(peer_id, older); return
	var data: Dictionary = StrictData.dictionary(response.data)
	peers[peer_id] = StrictData.dictionary(data.get("peer", {}))
	var incoming: Array = StrictData.array(data.get("messages", []))
	if after == 0: has_older[peer_id] = StrictData.boolean(data.get("has_more", false))
	var seen: Dictionary[String, bool] = {}
	var merged: Array = []
	var combined: Array = incoming + current if older else current + incoming
	for raw: Variant in combined:
		var item: Dictionary = StrictData.dictionary(raw)
		var id: String = str(item.get("id", ""))
		if seen.has(id): continue
		seen[id] = true; merged.append(item)
		if _pending.has(peer_id) and id.ends_with(str(_pending[peer_id].get("request_id", ""))):
			var text: String = str(_pending[peer_id].get("text", ""))
			var _removed: bool = _pending.erase(peer_id)
			message = ""
			message_sent.emit(peer_id, text)
	messages[peer_id] = merged
	if not incoming.is_empty() and active_peer == peer_id and _foreground:
		var seq: int = StrictData.integer(StrictData.dictionary(merged.back()).get("seq", 0))
		var _read: Dictionary = await GameServices.session()._send("/api/v1/social/conversations/%s/read" % peer_id.uri_encode(), HTTPClient.METHOD_POST, {"seq":seq})
		if generation != _generation: return
	conversation_changed.emit(peer_id, older)
	if not incoming.is_empty(): await refresh()

func send_text(peer_id: String, text: String) -> Dictionary:
	if _sending: return {"ok":false,"message":"Sending your previous message…"}
	text = text.strip_edges()
	if _pending.has(peer_id) and str(_pending[peer_id].get("text", "")) != text: return {"ok":false,"message":"Retry your previous message first."}
	if not _pending.has(peer_id): _pending[peer_id] = {"request_id":Crypto.new().generate_random_bytes(16).hex_encode(),"text":text}
	_sending = true
	var generation: int = _generation
	var response: Dictionary = await GameServices.session()._send("/api/v1/social/conversations/%s/messages" % peer_id.uri_encode(), HTTPClient.METHOD_POST, _pending[peer_id])
	if generation != _generation: return {"ok":false}
	_sending = false
	if response.ok:
		var _removed: bool = _pending.erase(peer_id)
		message_sent.emit(peer_id, text); message = ""
	else:
		message = str(response.get("message", "Message not sent. Tap Send to retry."))
		if StrictData.integer(response.get("status", 0)) in [400, 403, 404, 409]:
			var _removed: bool = _pending.erase(peer_id)
	await poll_thread(peer_id)
	if generation != _generation: return {"ok":false}
	if not response.ok and StrictData.integer(response.get("status",0)) not in [400,403,404,409] and not _pending.has(peer_id): return {"ok":true,"recovered":true}
	return response

func _retry_pending() -> void:
	if _sending: return
	var keys: Array[String] = _pending.keys()
	for peer_id: String in keys:
		if _pending.has(peer_id):
			var _response: Dictionary = await send_text(peer_id, str(_pending[peer_id].get("text", "")))

func _listen_events() -> void:
	if _events_running or not _foreground or not GameServices.session().is_authenticated(): return
	_events_running = true
	var generation: int = _generation
	# Separate request keeps long polling out of the serialized gameplay/auth queue.
	var response: Dictionary = await GameServices.session()._http("/api/v1/social/events?cursor=" + _event_cursor.uri_encode() + "&device=" + _device, HTTPClient.METHOD_GET, {}, GameServices.session()._token)
	if generation != _generation: return
	_events_running = false
	_events_retry = Time.get_ticks_msec() + (100 if response.ok else 4000)
	if not response.ok:
		if StrictData.integer(response.get("status", 0)) == 401: refresh.call_deferred()
		return
	var data: Dictionary = StrictData.dictionary(response.data)
	_event_cursor = str(data.get("cursor", ""))
	for raw: Variant in StrictData.array(data.get("events", [])):
		var event: Dictionary = StrictData.dictionary(raw)
		var peer_id: String = str(event.get("peer_id", ""))
		var kind: String = str(event.get("kind", ""))
		if kind == "typing":
			if Time.get_unix_time_from_system() * 1000.0 - StrictData.number(event.get("at", 0)) < 5000.0:
				typing_until[peer_id] = Time.get_ticks_msec() + 4500; typing_changed.emit(peer_id)
			continue
		refresh.call_deferred()
		if peer_id == active_peer: _next_poll = 0
		elif kind in ["message", "challenge", "duet"]: notification_received.emit(kind, peer_id)

func send_typing(peer_id: String) -> void:
	if peer_id.is_empty() or Time.get_ticks_msec() < _typing_next: return
	_typing_next = Time.get_ticks_msec() + 2500
	var _response: Dictionary = await GameServices.session()._send("/api/v1/social/conversations/%s/typing" % peer_id.uri_encode(), HTTPClient.METHOD_POST)
