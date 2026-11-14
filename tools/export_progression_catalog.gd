extends SceneTree
## Run after changing charts: exports authoritative reward-validation metadata.
func _initialize() -> void:
	var entries: Array[Dictionary] = []
	for song: Dictionary in SongCatalog.SONGS:
		for difficulty: String in ["Easy", "Normal", "Hard", "Ultra Hard"]:
			var chart: Dictionary = RhythmChart.load_chart(str(song.id), difficulty)
			var units: int = 0
			for note: Dictionary in chart.notes: units += 1 + StrictData.array(note.checkpoints).size()
			var notes: Array[Dictionary] = []
			for note: Dictionary in chart.notes:
				notes.append({"time":note.time,"duration":note.duration,"lane":note.lane,"kind":note.kind,"curve":note.curve,"checkpoints":note.checkpoints})
			entries.append({"song_id":song.id, "title":song.title, "difficulty":difficulty, "duration":song.playable_seconds, "units":units, "revision":chart.revision, "notes":notes})
	# Retired songs keep replay evidence for existing tickets and score history.
	var active_keys: Dictionary[String, bool] = {}
	for entry: Dictionary in entries:
		active_keys[str(entry.song_id) + "/" + str(entry.difficulty)] = true
	var previous_order: Dictionary[String, int] = {}
	var previous_file: FileAccess = FileAccess.open("res://backend/charts.json", FileAccess.READ)
	if previous_file != null:
		var previous: Array = StrictData.array(JSON.parse_string(previous_file.get_as_text()))
		previous_file.close()
		for entry: Dictionary in previous:
			previous_order[str(entry.song_id) + "/" + str(entry.difficulty)] = previous_order.size()
			if not active_keys.has(str(entry.song_id) + "/" + str(entry.difficulty)):
				entry.units = StrictData.integer(entry.units)
				entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return StrictData.integer(previous_order.get(str(a.song_id) + "/" + str(a.difficulty), 99999)) < StrictData.integer(previous_order.get(str(b.song_id) + "/" + str(b.difficulty), 99999)))
	var file: FileAccess = FileAccess.open("res://backend/charts.json", FileAccess.WRITE)
	var _bool_1: bool = file.store_string(JSON.stringify(entries, "\t"))
	file.close()
	print("Exported ", entries.size(), " progression charts.")
	quit()
