extends SceneTree
var commerce: CommerceService
var failures: int = 0
func _initialize() -> void:
	verify.call_deferred()
func verify() -> void:
	if OS.get_environment("RESCENE_COMMERCE_TEST") != "1": quit(1); return
	var response: Dictionary = await GameServices.session().authenticate("Fixture", "test password")
	check(StrictData.boolean(response.get("ok", false)), "Fixture login")
	commerce = GameServices.commerce()
	await commerce.refresh()
	check(not commerce.product("energy_drink").is_empty() and commerce.owned("energy_drink") == 0, "Load actual server catalog and inventory")
	await commerce.purchase("energy_drink", 1)
	await settle()
	check(commerce.owned("energy_drink") == 1 and str(commerce.operation.get("status", "")) == "confirmed", "Lost purchase response must recover the same order")
	var request_id: String = str(commerce.operation.get("request_id", ""))
	commerce._intent = {"kind":"buy","body":{"request_id":request_id,"item_id":"energy_drink","quantity":1.0,"expected_total":"100"}}
	check(commerce._save(), "Durably save a retry before restarting the client service")
	commerce._owner = ""
	await commerce.refresh()
	await settle()
	check(commerce.owned("energy_drink") == 1, "Reloading the saved order must not buy twice")
	await commerce.consume("energy_drink")
	await settle()
	check(commerce.owned("energy_drink") == 0 and str(commerce.operation.get("kind", "")) == "consume", "Consumption reflects confirmed server inventory")
	await GameServices.progression().refresh()
	check(StrictData.integer(StrictData.dictionary(GameServices.progression().state.get("energy")).get("current")) == 14, "Only server confirmation restores energy")
	var request: HTTPRequest = HTTPRequest.new();root.add_child(request)
	var _error: Error = request.request(GameServices.session().api_url() + "/test/summary")
	var result: Array = await request.request_completed
	var bytes: PackedByteArray = result[3]
	var summary: Dictionary = StrictData.dictionary(JSON.parse_string(bytes.get_string_from_utf8()))
	check(StrictData.integer(summary.get("buys")) == 1 and StrictData.integer(summary.get("uses")) == 1, "Exactly one purchase and consumption reached the server")
	request.queue_free()
	GameServices.session().logout()
	check(commerce.inventory.is_empty() and commerce.operation.is_empty(), "Logout clears account inventory")
	await create_timer(0.2).timeout
	print("Native commerce request/restart flow: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
func settle() -> void:
	for step: int in 8:
		if not commerce.pending(): return
		await commerce.refresh()
		await create_timer(0.1).timeout
	check(false, "Order must settle after server confirmation")
func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
