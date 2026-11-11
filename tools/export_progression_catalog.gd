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
	var file: FileAccess = FileAccess.open("res://backend/charts.json", FileAccess.WRITE)
	var _bool_1: bool = file.store_string(JSON.stringify(entries, "\t"))
	file.close()
	print("Exported ", entries.size(), " progression charts.")
	quit()
