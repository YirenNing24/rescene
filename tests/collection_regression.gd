extends SceneTree
var failures: int = 0
var menu: ResceneMainMenu

func _initialize() -> void:
	verify.call_deferred()

func card(token: int, member: int, level: int, stars: int, skill: int, equipped: bool) -> Dictionary:
	var names: Array[String] = ["None", "Overture", "Spotlight", "Second Wind", "Encore", "Resonance", "Overdrive"]
	var skills: Array[int] = [0, 0, 0, 0, 0, 0, 0]; skills[skill] = stars
	var scale_bp: int = 10000 + floori(float((level - 1) * 2000) / 99.0)
	var score: int = floori(StrictData.number([900, 800, 1000, 700, 900][member] * scale_bp) / 10000.0)
	var recovery: int = floori(StrictData.number([800, 1000, 700, 900, 800][member] * scale_bp) / 10000.0)
	return {"id":"pulse_%d" % token, "template_id":"scene_%02d" % (member + 1), "token_id":str(token), "category":"cards", "set_id":"pulse", "series":"PULSE", "rarity":"LE", "member":SongSets.MEMBERS[member], "member_name":SongSets.MEMBERS[member], "member_index":member, "quantity":1, "level":level, "max_level":100, "stars":stars, "star_progress":5 if token == 14 else 0, "training_xp":380 if token != 19 else 999, "level_xp":380, "level_cost":20 + (level - 1) * 5, "success_chance_bp":6000, "skill":names[skill], "skill_id":skill, "skill_description":"Start with 80% of the first momentum bar. Lost on the first miss." if skill == 1 else "PERFECT hits activate this card's skill. Higher stars improve its effect.", "locked":false, "equipped":equipped, "listed":false, "in_use":false, "stats":{"id":"pulse_%d" % token, "member_index":member, "version":2, "perfect_score_bp":score, "recovery_ppm":recovery, "skills":skills}}

func verify() -> void:
	var commerce: CommerceService = GameServices.commerce()
	commerce.catalog = [{"id":"energy_drink", "price":100, "stock":9999, "available":true, "max_quantity":10}]
	commerce.inventory = [{"id":"energy_drink", "quantity":2}]
	for index: int in 5:
		commerce.catalog.append({"id":"scene_%02d" % (index + 1), "price":450, "available":true, "stock":1, "max_quantity":1})
		commerce.inventory.append(card(14 + index, index, StrictData.integer([40, 28, 55, 16, 70][index]), StrictData.integer([4, 2, 4, 1, 5][index]), StrictData.integer([1, 2, 3, 4, 6][index]), true))
	for index: int in 5: commerce.inventory.append(card(19 + index, index, 90 if index == 0 else 1, 5 if index == 0 else 1, 5, false))
	for index: int in 3:
		var id: String = ["prism_shards", "resonance_core", "aurora_catalyst"][index]
		commerce.catalog.append({"id":id, "price":[150, 300, 550][index], "stock":1000, "available":true, "max_quantity":10, "training_xp":[100, 225, 450][index]})
		commerce.inventory.append({"id":id, "quantity":2})
	commerce.decks = {"pulse":["pulse_14", "pulse_15", "pulse_16", "pulse_17", "pulse_18"]}
	GameServices.progression().state = {"energy":{"current":9}, "level":3, "unlocks":[]}
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; root.add_child(menu); current_scene = menu
	await create_timer(0.4).timeout
	menu._open_destination("COLLECTION")
	var collection: CollectionView = menu._dialog as CollectionView
	for member: int in 5: check(collection.body.find_child("DeckSlot_%d" % member, true, false) != null, "Five member-specific deck slots")
	check(StrictData.array(SongSets.find_set("pulse").get("songs", [])).size() == 5, "Exactly five PULSE songs")
	await capture("pulse-deck-20-9.png")
	(collection.body.find_child("DeckSlot_0", true, false) as Button).pressed.emit()
	check(commerce.cards_for_set("pulse", 0).size() == 2, "Duplicate members are separate individual cards")
	check(commerce.cards_for_set("glow_up").is_empty(), "PULSE inventory cannot leak into another song set")
	collection.selected_id = "pulse_14"; collection._render()
	var equip: Button = collection.body.find_child("EquipMemberCard", true, false) as Button
	check(equip != null and equip.text == "REMOVE FROM SLOT", "The selected individual member card occupies its matching slot")
	await capture("pulse-card-detail-20-9.png")
	collection._enhancing = true; collection._render()
	check(collection.body.find_child("ConfirmCardEnhancement", true, false) != null, "Refinement-only XP controls")
	await capture("pulse-card-refinement-20-9.png")
	collection._enhancing = false; collection._stars = true
	collection._donors.assign(["pulse_19", "pulse_20", "pulse_21", "pulse_22", "pulse_23"])
	collection._payload = {"kind":"star", "card_id":"pulse_14", "donors":collection._donors.duplicate()}
	collection._quote = {"hash":"preview", "stars_before":4, "stars_after":5, "star_progress_after":0, "donors_wasted":2, "warnings":["Sacrifice is permanent. Every selected card contributes exactly ONE donor. No XP, level, stars, skills or progress are inherited.", "Woni #19: Level 90, 999 XP and 5 stars will be destroyed. It still counts as ONE donor.", "2 excess donors give no further progress and will still be destroyed."]}
	collection._render()
	var confirm: Button = collection.body.find_child("ConfirmIndividualCardAction", true, false) as Button
	check(confirm != null and not confirm.disabled and confirm.text.contains("DESTROY 5 CARDS"), "Overflow is warned and allowed, never silently rejected")
	await capture("pulse-sacrifice-warning-20-9.png")
	collection._quote.clear(); collection._stars = false; collection.selected_set = "glow_up"; collection.selected_id = ""; collection.inventory_mode = false
	collection._render(); await capture("glow-up-empty-deck-20-9.png")
	collection.selected_set = "pulse"; collection.selected_id = "pulse_14"; menu._rebuild(); await process_frame
	check((menu._dialog as CollectionView).selected_set == "pulse" and (menu._dialog as CollectionView).selected_id == "pulse_14", "Song-set selection and card survive resize")
	var song: Dictionary = {}
	for entry: Dictionary in SongCatalog.SONGS:
		if str(entry.title) == "With": song = entry
	menu._request_song_start(song, "Normal")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true; stage.set_process(false); stage.audio.stop(); stage._count_label.hide()
	stage.phase = "playing"; stage.song_time = 24.0; stage.visual_age = 24.0
	var team: Array[Dictionary] = []
	for id: String in commerce.deck_ids("pulse"): team.append(StrictData.dictionary(commerce.item_details(id).get("stats", {})))
	stage.judge.card_loadout = CardBoosts.combined(team)
	stage.judge.combo = 124; stage.judge.max_combo = 124; stage.judge.life = 934.0
	stage._score_label.text = "0284760"; stage._combo_label.text = "124"; stage._life.value = 934.0; stage._life_label.text = "LIFE   0934"; stage._accuracy_label.text = "ACCURACY   98.42%"; stage._time_label.text = "0:24  /  1:35"
	stage._progress.value = 25.2; stage.momentum_visual = 2.0; stage._update_momentum()
	for note: Dictionary in stage.judge.notes:
		if StrictData.number(note.time) < 24.0: note.state = 2
	stage.deck_showcase.show_time(0.8); stage.highway.queue_redraw()
	check(stage.deck_showcase.deck_ids.size() == 5, "Stage receives five set-specific equipped cards")
	await capture("pulse-gameplay-woni-20-9.png")
	stage.deck_showcase.show_time(5.3)
	check(stage.deck_showcase._member_label.text.begins_with("Liv"), "Showcase animates to the next member without changing active bonuses")
	await capture("pulse-gameplay-liv-20-9.png")
	stage.deck_showcase.show_time(9.8)
	await capture("pulse-gameplay-minami-20-9.png")
	menu.queue_free(); commerce.catalog.clear(); commerce.inventory.clear(); commerce.decks.clear(); GameServices.progression().state.clear()
	await create_timer(0.3).timeout
	print("Individual cards, refinement, sacrifice warnings, album decks, combined team and stage carousel: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/" + filename)

func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
