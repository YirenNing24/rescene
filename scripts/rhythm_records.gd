class_name RhythmRecords
extends RefCounted

const PATH: String = "user://rhythm_records.cfg"

static func _cloud() -> CloudScoresService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("CloudScores") if tree != null else null

static func _better(a: Dictionary, b: Dictionary) -> bool:
	return StrictData.integer(a.get("score", -1)) > StrictData.integer(b.get("score", -1)) or (StrictData.integer(a.get("score", -1)) == StrictData.integer(b.get("score", -1)) and StrictData.integer(a.get("max_combo", 0)) > StrictData.integer(b.get("max_combo", 0)))

static func storage_path() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var session: ResceneAuthSession = tree.root.get_node_or_null("AuthSession") if tree != null else null
	if session != null and session.is_authenticated():
		return "user://rhythm_records_%s.cfg" % str(session.user.id).sha256_text()
	return PATH

static func key(song_id: String, difficulty: String) -> String:
	return song_id + "_" + difficulty.to_lower().replace(" ", "_")

static func best(song_id: String, difficulty: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var local: Dictionary = {}
	if config.load(storage_path()) == OK:
		local = config.get_value("scores", key(song_id, difficulty), {})
		if local.get("scoring_id", "") != RhythmMomentum.SCORING_ID: local = {}
		if not local.is_empty(): local.source = "device"
	var cloud: Dictionary = _cloud().best(song_id, difficulty) if _cloud() != null else {}
	return local if _better(local, cloud) else cloud

static func last_attempt(song_id: String, difficulty: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	if config.load(storage_path()) != OK: return {}
	var record: Dictionary = StrictData.dictionary(config.get_value("last_attempts",key(song_id,difficulty),{}))
	return record if record.get("scoring_id", "") == RhythmMomentum.SCORING_ID else {}

static func all_scores() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var merged: Dictionary[String, Dictionary] = {}
	if _cloud() != null:
		for record: Dictionary in _cloud().all_records(): merged[key(str(record.song_id),str(record.difficulty))] = record
	var config: ConfigFile = ConfigFile.new()
	if config.load(storage_path()) == OK and config.has_section("scores"):
		for id: String in config.get_section_keys("scores"):
			var record: Dictionary = config.get_value("scores", id, {})
			if record.is_empty(): continue
			if record.get("scoring_id", "") != RhythmMomentum.SCORING_ID: continue
			record.source = "device"
			if not record.has("song_id"):
				for song: Dictionary in SongCatalog.SONGS:
					if song.title == record.get("title", ""): record.song_id = song.id; break
			if not merged.has(id) or _better(record,StrictData.dictionary(merged[id])): merged[id] = record
	for record: Dictionary in merged.values(): result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return result

static func save(song: Dictionary, difficulty: String, result: Dictionary) -> void:
	var config: ConfigFile = ConfigFile.new()
	var _error_1: Error = config.load(storage_path())
	var id: String = key(str(song.id), difficulty)
	var previous: Dictionary = config.get_value("scores", id, {})
	if previous.get("scoring_id", "") != RhythmMomentum.SCORING_ID or _better(result, previous):
		var record: Dictionary = result.duplicate(true)
		record.title = song.title
		record.song_id = song.id
		record.source = "device"
		record.scoring_id = RhythmMomentum.SCORING_ID
		record.difficulty = difficulty
		config.set_value("scores", id, record)
	var last: Dictionary = result.duplicate(true)
	last.scoring_id = RhythmMomentum.SCORING_ID
	config.set_value("last_attempts",id,last)
	var _error_2: Error = config.save(storage_path())

static func save_last_attempt(song_id: String, difficulty: String, result: Dictionary) -> void:
	var config: ConfigFile = ConfigFile.new()
	var _load_error: Error = config.load(storage_path())
	var last: Dictionary = result.duplicate(true)
	last.scoring_id = RhythmMomentum.SCORING_ID
	config.set_value("last_attempts",key(song_id,difficulty),last)
	var _save_error: Error = config.save(storage_path())
