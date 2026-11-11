class_name CommerceService
extends Node
## Durable intents scoped to API/account; balances and item use come from server.
signal changed
var catalog: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var operation: Dictionary = {}
var equipped_card: String = ""
var decks: Dictionary = {}
var message: String = ""
var loading: bool = false
var busy: bool = false
var _owner: String = ""
var _generation: int = 0
var _intent: Dictionary = {}
var _refresh_at: int = 0

func _ready() -> void:
	var _connection: int = GameServices.session().session_ended.connect(func(_reason: String) -> void:
		_generation += 1
		catalog.clear(); inventory.clear(); operation.clear(); _intent.clear(); decks.clear(); equipped_card = ""
		_owner = ""; message = ""; changed.emit())

func _path() -> String:
	return "user://shop_intent_%s.json" % _owner

func _bind() -> void:
	var owner_key: String = (GameServices.session().api_url() + "/" + str(GameServices.session().user.get("id", ""))).sha256_text()
	if _owner == owner_key: return
	_generation += 1; _owner = owner_key
	catalog.clear(); inventory.clear(); operation.clear(); _intent.clear(); decks.clear(); equipped_card = ""; message = ""
	if FileAccess.file_exists(_path()):
		var file: FileAccess = FileAccess.open(_path(), FileAccess.READ)
		if file != null and file.get_length() < 4096: _intent = StrictData.dictionary(JSON.parse_string(file.get_as_text()))

func _save() -> bool:
	if _intent.is_empty():
		if not FileAccess.file_exists(_path()): return true
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path())) == OK
	var file: FileAccess = FileAccess.open(_path() + ".tmp", FileAccess.WRITE)
	if file == null: return false
	var written: bool = file.store_string(JSON.stringify(_intent))
	file.close()
	return written and DirAccess.rename_absolute(ProjectSettings.globalize_path(_path() + ".tmp"), ProjectSettings.globalize_path(_path())) == OK

func product(id: String) -> Dictionary:
	for item: Dictionary in catalog:
		if str(item.get("id", "")) == id: return item
	return {}

func item_details(id: String) -> Dictionary:
	for item: Dictionary in inventory:
		if str(item.get("id", "")) == id: return item
	return {}

func owned(id: String) -> int:
	for item: Dictionary in inventory:
		if str(item.get("id", "")) == id: return StrictData.integer(item.get("quantity", 0))
	return 0

func pending() -> bool:
	return busy or not _intent.is_empty() or str(operation.get("status", "")) == "pending"

func refresh() -> void:
	if loading or not GameServices.session().is_authenticated(): return
	_bind(); loading = true
	var generation: int = _generation
	if not _intent.is_empty() and not busy: await _submit()
	var products: Dictionary = await GameServices.session().authorized_request("/api/v1/shop/catalog")
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/inventory")
	loading = false
	if generation != _generation: return
	if StrictData.boolean(products.get("ok", false)):
		catalog.clear()
		for value: Variant in StrictData.array(StrictData.dictionary(products.get("data")).get("catalog")):
			if value is Dictionary: catalog.append(value)
	if StrictData.boolean(response.get("ok", false)):
		var data: Dictionary = StrictData.dictionary(response.get("data"))
		inventory.clear()
		for value: Variant in StrictData.array(data.get("items")):
			if value is Dictionary: inventory.append(value)
		equipped_card = str(data.get("equipped_card", ""))
		decks = StrictData.dictionary(data.get("decks", {}))
		operation = StrictData.dictionary(data.get("operation"))
		if str(operation.get("status", "")) == "confirmed":
			var kind: String = str(operation.get("kind", ""))
			message = "Added to Inventory." if kind in ["buy", "pulse_buy"] else "Energy restored. Enjoy your next scene!"
			if kind in ["enhance", "pulse_refine"]:
				if StrictData.boolean(operation.get("level_upgraded", false)): message = "Level up! Your card reached level %d." % StrictData.integer(operation.get("level_after", 1))
				elif StrictData.boolean(operation.get("upgrade_attempted", false)): message = "Level attempt failed. Your level and all XP were kept. Refinement item used."
				else: message = "Card XP added. More XP is needed for the next level attempt."
			if kind == "pulse_star": message = "Star progress updated. Selected donor cards were sacrificed."
			if kind == "pulse_lock": message = "Card protection updated."
			if kind == "pulse_equip": message = "Song-set deck updated."
		elif str(operation.get("status", "")) == "failed": message = str(operation.get("message", "This item action could not finish."))
		elif str(operation.get("status", "")) == "pending": message = "Processing your card or item action…"
		if data.get("progression") is Dictionary:
			GameServices.progression().refresh.call_deferred()
	else:
		message = str(response.get("message", "Your inventory could not be refreshed."))
	_refresh_at = Time.get_ticks_msec() + (4000 if pending() else 30000)
	changed.emit()

func purchase(id: String, quantity: int) -> void:
	await _begin("buy", id, quantity)

func consume(id: String) -> void:
	await _begin("consume", id, 1)

func enhance(card_id: String, material_id: String) -> void:
	await _begin("enhance", material_id, 1, card_id)

func _begin(kind: String, id: String, quantity: int, card_id: String = "") -> void:
	if not GameServices.session().is_authenticated() or busy: return
	_bind()
	if pending(): message = "Your previous item action is still processing."; changed.emit(); return
	var item: Dictionary = product(id)
	if kind == "buy" and (item.is_empty() or not StrictData.boolean(item.get("available", false))): return
	var request_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var payload: Dictionary = {"request_id":request_id,"item_id":id,"quantity":quantity}
	if kind == "enhance": payload.card_id = card_id
	if kind == "buy": payload.expected_total = str(StrictData.integer(item.get("price", 0)) * quantity)
	_intent = {"kind":kind,"body":payload}
	if not _save(): _intent.clear(); message = "Could not save this request. Please try again."; changed.emit(); return
	await _submit()
	await refresh()

func _submit() -> void:
	if busy or _intent.is_empty(): return
	busy = true; changed.emit()
	var generation: int = _generation
	var payload: Dictionary = StrictData.dictionary(_intent.get("body")).duplicate(true)
	if str(_intent.get("kind", "")) != "pulse": payload.quantity = StrictData.integer(payload.get("quantity", 1))
	var kind: String = str(_intent.get("kind", ""))
	if kind == "pulse" and payload.has("member_index"): payload.member_index = StrictData.integer(payload.member_index)
	var path: String = "/api/v1/collection/action" if kind == "pulse" else "/api/v1/shop/purchase" if kind == "buy" else "/api/v1/collection/enhance" if kind == "enhance" else "/api/v1/inventory/consume"
	var response: Dictionary = await GameServices.session()._send(path, HTTPClient.METHOD_POST, payload)
	busy = false
	if generation != _generation: return
	if StrictData.boolean(response.get("ok", false)):
		_intent.clear()
		var _saved: bool = _save()
		var data: Dictionary = StrictData.dictionary(response.get("data"))
		operation = StrictData.dictionary(data.get("operation", data.get("reward", {})))
		message = "Processing…"
	else:
		var status: int = StrictData.integer(response.get("status", 0))
		if status >= 400 and status < 500 and status != 429:
			_intent.clear()
			var _saved: bool = _save()
		message = str(response.get("message", "Your request is saved. Refresh to check its status."))
	_refresh_at = Time.get_ticks_msec() + 4000
	changed.emit()

func _process(_delta: float) -> void:
	if _owner.is_empty() or loading or not GameServices.session().is_authenticated(): return
	if Time.get_ticks_msec() >= _refresh_at: refresh.call_deferred()

func equip(id: String) -> void:
	if busy or not GameServices.session().is_authenticated(): return
	_bind()
	if not id.is_empty() and owned(id) < 1: return
	busy = true; changed.emit()
	var generation: int = _generation
	var response: Dictionary = await GameServices.session()._send("/api/v1/collection/equip", HTTPClient.METHOD_POST, {"item_id":id})
	busy = false
	if generation != _generation: return
	var succeeded: bool = StrictData.boolean(response.get("ok", false))
	await refresh()
	if generation != _generation: return
	message = ("Favorite card equipped." if not id.is_empty() else "Favorite card removed.") if succeeded else str(response.get("message", "Could not equip this card."))
	changed.emit()

func deck_ids(set_id: String) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in StrictData.array(decks.get(set_id, [])): result.append(str(value))
	while result.size() < 5: result.append("")
	return result

func cards_for_set(set_id: String, member_index: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in inventory:
		if str(value.get("set_id", "")) == set_id and StrictData.integer(value.get("quantity", 0)) > 0 and (member_index < 0 or StrictData.integer(value.get("member_index", -1)) == member_index): result.append(value)
	return result

func quote_card(payload: Dictionary) -> Dictionary:
	if busy or not GameServices.session().is_authenticated(): return {}
	var response: Dictionary = await GameServices.session()._send("/api/v1/collection/quote", HTTPClient.METHOD_POST, payload)
	if not StrictData.boolean(response.get("ok", false)):
		message = str(response.get("message", "Could not preview this card action.")); changed.emit(); return {}
	return StrictData.dictionary(StrictData.dictionary(response.get("data")).get("quote", {}))

func card_action(payload: Dictionary, quote: Dictionary) -> void:
	if busy or pending() or not GameServices.session().is_authenticated(): return
	_bind()
	var data: Dictionary = payload.duplicate(true)
	data.request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	data.quote_hash = str(quote.get("hash", ""))
	data.acknowledge_warning = true
	_intent = {"kind":"pulse", "body":data}
	if not _save(): _intent.clear(); message = "Could not save this request."; changed.emit(); return
	await _submit()
	await refresh()
