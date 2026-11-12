class_name MarketCatalog
extends RefCounted
## Display artwork/copy. Price and purchase availability come from the backend.

const CATEGORIES: Array[Dictionary] = [
	{"id":"featured", "label":"Featured", "icon":"star"},
	{"id":"cards", "label":"Cards", "icon":"cards"},
	{"id":"packs", "label":"Card packs", "icon":"gift"},
	{"id":"upgrades", "label":"Upgrade items", "icon":"gem"},
	{"id":"energy", "label":"Energy drinks", "icon":"heart"},
]
const ITEMS: Array[Dictionary] = [
	{"id":"scene_01", "category":"cards", "name":"Woni · PULSE", "member_name":"Woni", "tag":"LE · PHOTO CARD", "price":450, "member":0, "accent":"c7bbff", "description":"An individual PULSE LE card. Rolls 7–10% Perfect Score, 7–10 Recovery and one permanent skill. Refine to level 100; sacrifice eligible cards to improve its stars.", "contents":"1 unique LE card / Level 1 / 1 star", "detail":"Each stat value: 25% chance. Guaranteed skill: one of six, equally likely. Rolls are fixed after generation. Initial sale: 50 per member."},
	{"id":"encore_pack", "category":"packs", "name":"Encore Card Pack", "tag":"5-CARD PACK", "price":1200, "accent":"dfafd2", "description":"A little encore for your collection. A foil card pack designed around the game's pearl and rose palette.", "contents":"5 photo cards", "detail":"Pack contents and drop rates will be shown before purchases launch."},
	{"id":"prism_shards", "category":"upgrades", "name":"Prism Shards ×10", "tag":"CARD UPGRADE", "price":150, "accent":"a4d9e9", "description":"A bundle of shimmering fragments for card training. Save them for your favourite portraits.", "contents":"10 Prism Shards / 100 training XP", "detail":"Adds the listed XP and attempts one level if enough XP. Odds decrease toward level 100. Failure keeps all XP and your level; the bundle is consumed."},
	{"id":"energy_drink", "category":"energy", "name":"Energy Drink", "tag":"+5 ENERGY", "price":100, "accent":"b4ded4", "description":"A refreshing little boost for your next scene. Restore 5 energy when used, up to the 15-energy cap.", "contents":"1 energy drink", "detail":"Purchase with Starlight, then use it from Inventory. Keep it for later when your energy is full."},
	{"id":"scene_02", "category":"cards", "name":"Liv · PULSE", "member_name":"Liv", "tag":"LE · PHOTO CARD", "price":450, "member":1, "accent":"e0b3cf", "description":"An individual PULSE LE card. Rolls 7–10% Perfect Score, 7–10 Recovery and one permanent skill. Refine to level 100; sacrifice eligible cards to improve its stars.", "contents":"1 unique LE card / Level 1 / 1 star", "detail":"Each stat value: 25% chance. Guaranteed skill: one of six, equally likely. Rolls are fixed after generation. Initial sale: 50 per member."},
	{"id":"first_scene_pack", "category":"packs", "name":"PULSE Pack", "tag":"3-CARD PACK", "price":700, "accent":"c7bbff", "description":"Start a new collection with a trio of photo cards, wrapped in a lavender PULSE sleeve.", "contents":"3 photo cards", "detail":"Pack contents and drop rates will be shown before purchases launch."},
	{"id":"resonance_core", "category":"upgrades", "name":"Resonance Cores ×3", "tag":"CARD UPGRADE", "price":300, "accent":"c1aff1", "description":"Concentrated resonance for card training. A second upgrade material for your collection.", "contents":"3 Resonance Cores / 225 training XP", "detail":"Adds the listed XP and attempts one level if enough XP. Odds decrease toward level 100. Failure keeps all XP and your level; the bundle is consumed."},
	{"id":"energy_trio", "category":"energy", "name":"Energy Drink Trio", "tag":"3 × ENERGY DRINK", "price":260, "accent":"b4ded4", "description":"Three energy drinks to keep for future sessions. Each drink is designed to restore 5 energy when used.", "contents":"3 energy drinks", "detail":"A planned consumable bundle. Energy use will be validated by the server."},
	{"id":"scene_03", "category":"cards", "name":"Minami · PULSE", "member_name":"Minami", "tag":"LE · PHOTO CARD", "price":450, "member":2, "accent":"a9cbea", "description":"An individual PULSE LE card. Rolls 7–10% Perfect Score, 7–10 Recovery and one permanent skill. Refine to level 100; sacrifice eligible cards to improve its stars.", "contents":"1 unique LE card / Level 1 / 1 star", "detail":"Each stat value: 25% chance. Guaranteed skill: one of six, equally likely. Rolls are fixed after generation. Initial sale: 50 per member."},
	{"id":"scene_04", "category":"cards", "name":"May · PULSE", "member_name":"May", "tag":"LE · PHOTO CARD", "price":450, "member":3, "accent":"c8b2e6", "description":"An individual PULSE LE card. Rolls 7–10% Perfect Score, 7–10 Recovery and one permanent skill. Refine to level 100; sacrifice eligible cards to improve its stars.", "contents":"1 unique LE card / Level 1 / 1 star", "detail":"Each stat value: 25% chance. Guaranteed skill: one of six, equally likely. Rolls are fixed after generation. Initial sale: 50 per member."},
	{"id":"scene_05", "category":"cards", "name":"Zena · PULSE", "member_name":"Zena", "tag":"LE · PHOTO CARD", "price":450, "member":4, "accent":"b1d6d4", "description":"An individual PULSE LE card. Rolls 7–10% Perfect Score, 7–10 Recovery and one permanent skill. Refine to level 100; sacrifice eligible cards to improve its stars.", "contents":"1 unique LE card / Level 1 / 1 star", "detail":"Each stat value: 25% chance. Guaranteed skill: one of six, equally likely. Rolls are fixed after generation. Initial sale: 50 per member."},
	{"id":"aurora_catalyst", "category":"upgrades", "name":"Aurora Catalyst", "tag":"RARE MATERIAL", "price":550, "accent":"e0b3cf", "description":"A rare, iridescent catalyst designed for advanced card training.", "contents":"1 Aurora Catalyst / 450 training XP", "detail":"Adds the listed XP and attempts one level if enough XP. Odds decrease toward level 100. Failure keeps all XP and your level; the bundle is consumed."},
]

static func find_item(id: String) -> Dictionary:
	if id.begins_with("pulse_"):
		var instance: Dictionary = GameServices.commerce().item_details(id)
		if instance.is_empty(): return {}
		var display: Dictionary = find_item(str(instance.get("template_id", ""))).duplicate(true)
		display.merge(instance, true)
		return display
	if id.begins_with("legacy_scene_"):
		var legacy: Dictionary = find_item(id.trim_prefix("legacy_")).duplicate(true)
		if not legacy.is_empty():
			legacy.id = id; legacy.name = str(legacy.get("member_name", "")) + " · First Scene"; legacy.tag = "SR · ARCHIVE"; legacy.legacy = true
		return legacy
	for item: Dictionary in all_items():
		if item.id == id: return item
	return {}

static func all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = CardReleases.templates()
	for item: Dictionary in ITEMS:
		if str(item.category) != "cards": result.append(item)
	return result

static func filtered(category: String, query: String, sort_index: int, set_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in all_items():
		if not set_id.is_empty() and (str(item.category) != "cards" or str(item.get("set_id", "")) != set_id): continue
		if category != "featured" and item.category != category: continue
		if not query.strip_edges().is_empty() and not (str(item.name) + " " + str(item.tag)).to_lower().contains(query.strip_edges().to_lower()): continue
		result.append(item)
	if sort_index > 0:
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.price == b.price: return str(a.id) < str(b.id)
			return a.price < b.price if sort_index == 1 else a.price > b.price)
	return result
