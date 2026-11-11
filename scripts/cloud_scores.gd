class_name CloudScoresService
extends Node
## Account/API-scoped cloud cache. No upload endpoint accepts old local scores.

signal changed

var records: Array[Dictionary] = []
var loading: bool = false
var error_message: String = ""
var _owner: String = ""
var _generation: int = 0

func _ready() -> void:
	var _int_1: int = GameServices.session().session_ended.connect(func(_message: String) -> void:
		_generation += 1
		_owner = ""
		records.clear()
		loading = false
		error_message = ""
		changed.emit())
	var _int_2: int = GameServices.progression().run_rewarded.connect(func(_id: String, reward: Dictionary) -> void:
		if reward.get("ranked", false): refresh.call_deferred())

func _path() -> String:
	return "user://cloud_records_%s_%s.json" % [_owner, RhythmMomentum.SCORING_ID]

func _bind() -> void:
	var account_owner: String = (GameServices.session().api_url()+"/"+str(GameServices.session().user.get("id", ""))).sha256_text() if GameServices.session().is_authenticated() else ""
	if account_owner == _owner: return
	_generation += 1
	_owner = account_owner
	loading = false
	error_message = ""
	records.clear()
	if not account_owner.is_empty() and FileAccess.file_exists(_path()):
		var file: FileAccess = FileAccess.open(_path(), FileAccess.READ)
		if file != null and file.get_length() < 131072:
			_accept(JSON.parse_string(file.get_as_text()))

func _accept(data: Variant) -> void:
	if not data is Array: return
	records.clear()
	for item: Dictionary in data:
		if not item is Dictionary or not item.has_all(["song_id", "difficulty", "score", "rank", "accuracy"]): continue
		if StrictData.integer(item.get("verification",0)) != 2: continue
		var record: Dictionary = item.duplicate(true)
		record.source = "cloud"
		record.score = StrictData.integer(record.score)
		record.max_combo = StrictData.integer(record.get("max_combo", 0))
		records.append(record)

func all_records() -> Array[Dictionary]:
	_bind()
	return records.duplicate(true)

func best(song_id: String, difficulty: String) -> Dictionary:
	_bind()
	for record: Dictionary in records:
		if record.song_id == song_id and record.difficulty == difficulty: return record.duplicate(true)
	return {}

func refresh() -> void:
	_bind()
	if _owner.is_empty(): return
	if loading:
		# Await the existing request rather than returning an empty/stale snapshot.
		var pending_generation: int = _generation
		while loading and pending_generation == _generation:
			await get_tree().process_frame
		return
	loading = true
	var generation: int = _generation
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/records")
	if generation != _generation: return
	loading = false
	if response.ok and StrictData.dictionary(response.data).get("records") is Array:
		_accept(response.data.records)
		error_message = ""
		var file: FileAccess = FileAccess.open(_path()+".tmp", FileAccess.WRITE)
		if file != null:
			var _bool_3: bool = file.store_string(JSON.stringify(records))
			file.close()
			var _error_4: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(_path()+".tmp"), ProjectSettings.globalize_path(_path()))
	else:
		error_message = response.get("message", "Cloud records could not be loaded.")
	changed.emit()

func leaderboard(song_id: String, difficulty: String) -> Dictionary:
	return await GameServices.session().authorized_request("/api/v1/leaderboards?song_id=%s&difficulty=%s" % [song_id.uri_encode(), difficulty.uri_encode()])

func player(user_id: String) -> Dictionary:
	return await GameServices.session().authorized_request("/api/v1/players/"+user_id.uri_encode())
