extends SceneTree
var commerce: CommerceService
var failures: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	if OS.get_environment("RESCENE_CARD_ACTION_TEST") != "1": quit(1); return
	var login: Dictionary = await GameServices.session().authenticate("Fixture", "fixture password")
	check(StrictData.boolean(login.get("ok", false)), "Fixture authentication")
	commerce = GameServices.commerce(); await commerce.refresh()
	var refine: Dictionary = {"kind":"refine", "card_id":"pulse_14", "item_id":"prism_shards"}
	var quote: Dictionary = await commerce.quote_card(refine)
	await commerce.card_action(refine, quote); await settle()
	check(StrictData.integer(commerce.item_details("pulse_14").get("level", 0)) == 10 and StrictData.integer(commerce.item_details("pulse_14").get("training_xp", 0)) == 100, "Failed refinement retains level and XP from its bundle")
	check(commerce.message.contains("failed"), "A failed level attempt must not be announced as a level up")
	var sacrifice: Dictionary = {"kind":"star", "card_id":"pulse_14", "donors":["pulse_15", "pulse_16"]}
	quote = await commerce.quote_card(sacrifice); await commerce.card_action(sacrifice, quote); await settle()
	check(StrictData.integer(commerce.item_details("pulse_14").get("stars", 0)) == 2 and commerce.owned("pulse_15") == 0 and commerce.owned("pulse_16") == 0, "Two high-star donors still give only the first two-donor upgrade")
	var lock: Dictionary = {"kind":"lock", "card_id":"pulse_14", "locked":true}
	quote = await commerce.quote_card(lock); await commerce.card_action(lock, quote); await settle()
	check(StrictData.boolean(commerce.item_details("pulse_14").get("locked", false)), "Protection is confirmed by the server")
	var equip: Dictionary = {"kind":"equip", "set_id":"pulse", "member_index":0, "card_id":"pulse_14"}
	quote = await commerce.quote_card(equip); await commerce.card_action(equip, quote); await settle()
	check(commerce.deck_ids("pulse")[0] == "pulse_14" and commerce.deck_ids("glow_up")[0].is_empty(), "Equipment belongs to its album and member")
	var saved: Dictionary = equip.duplicate(true)
	saved.request_id = str(commerce.operation.get("request_id", "")); saved.quote_hash = str(quote.get("hash", "")); saved.acknowledge_warning = true; saved.member_index = 0.0
	commerce._intent = {"kind":"pulse", "body":saved}
	check(commerce._save(), "Save an immutable card-action intent")
	commerce._owner = ""; await commerce.refresh(); await settle()
	check(commerce.deck_ids("pulse")[0] == "pulse_14", "A saved card action restores numeric types and remains idempotent")
	GameServices.session().logout()
	check(commerce.decks.is_empty() and commerce.inventory.is_empty(), "Logout removes the previous account's decks")
	await create_timer(0.2).timeout
	print("Native individual card actions: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func settle() -> void:
	for step: int in 8:
		if not commerce.pending(): return
		await commerce.refresh(); await create_timer(0.1).timeout
	check(false, "Card action must settle after server confirmation")

func check(condition: bool, message: String) -> void:
	if not condition: failures += 1; push_error(message)
