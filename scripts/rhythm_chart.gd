class_name RhythmChart
extends RefCounted
## Beat/bar loader compatible with the track organization in g-metarave-beats.

static func chart_path(song_id: String, difficulty: String) -> String:
	return "res://assets/beatmaps/%s/%s.tres" % [song_id, difficulty.to_lower().replace(" ", "_")]


static func load_chart(song_id: String, difficulty: String) -> Dictionary:
	var path: String = chart_path(song_id, difficulty)
	if not ResourceLoader.exists(path):
		return {}
	var resource: JSON = load(path) as JSON
	if resource == null or not resource.data is Dictionary:
		return {}
	var chart: Dictionary = normalize(StrictData.dictionary(resource.data))
	chart.revision = (RhythmMomentum.SCORING_ID + ":" + JSON.stringify(resource.data).sha256_text()).sha256_text()
	return chart


static func normalize(data: Dictionary) -> Dictionary:
	var tempo: float = maxf(1.0, StrictData.number(data.get("tempo", 120.0)))
	var quarter: float = 60.0 / tempo
	# Old maps use 70/280 ticks; new maps explicitly declare 400 ticks per beat.
	var ticks: float = maxf(1.0, StrictData.number(data.get("ticks_per_beat", 280.0)))
	var offset: float = StrictData.number(data.get("offset_seconds", 0.0))
	var cutoff: float = StrictData.number(data.get("duration_seconds", 600.0))
	var notes: Array[Dictionary] = []
	var tracks: Array = data.get("tracks", [])
	for lane: int in tracks.size():
		var elapsed_beats: float = 0.0
		for bar: Dictionary in StrictData.dictionary(tracks[lane]).get("bars", []):
			for raw: Dictionary in bar.get("notes", []):
				var at: float = offset + (elapsed_beats + StrictData.number(raw.get("pos", 0.0)) / ticks) * quarter
				if at < 0.0 or at >= cutoff - 0.1:
					continue
				var kind: String = raw.get("kind", "hold" if StrictData.number(raw.get("len", 70.0)) > 70.0 else "tap")
				var duration: float = 0.0 if kind in ["tap", "swipe"] else StrictData.number(raw.get("len", 0.0)) / ticks * quarter
				duration = clampf(duration, 0.0, maxf(0.0, cutoff - at - 0.05))
				var curve: Array = raw.get("curve", [])
				if kind == "slide" and curve.size() < 2:
					kind = "hold"
				var checkpoints: Array[float] = []
				if kind in ["hold", "slide"]:
					var tick: float = at + quarter * 0.5
					while tick < at + duration - 0.05:
						checkpoints.append(tick)
						tick += quarter * 0.5
					checkpoints.append(at + duration)
				notes.append({"time": at, "duration": duration, "lane": StrictData.number(lane % 5),
					"kind": kind, "curve": curve, "checkpoints": checkpoints,
					"state": 0, "owner": -999, "next_tick": 0, "gap": 0.0})
			elapsed_beats += StrictData.number(bar.get("quarters_count", 4))
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for index: int in notes.size():
		notes[index]["id"] = index
	return {"tempo": tempo, "quarter": quarter, "duration": cutoff,
		"difficulty": data.get("difficulty", "Normal"), "generated": data.get("generated", false), "notes": notes}


static func lane_at(note: Dictionary, time: float) -> float:
	if note.kind != "slide" or StrictData.array(note.curve).size() < 2:
		return note.lane
	var progress: float = clampf(StrictData.number((time - note.time) / maxf(StrictData.number(note.duration), 0.001)), 0.0, 1.0)
	var points: Array = note.curve
	for index: int in range(1, points.size()):
		if progress <= StrictData.number(points[index].at):
			var start: Dictionary = points[index - 1]
			var finish: Dictionary = points[index]
			var local: float = clampf((progress - StrictData.number(start.at)) / maxf(0.001, StrictData.number(finish.at) - StrictData.number(start.at)), 0.0, 1.0)
			# Cubic easing gives the ribbon and its tracing target the identical curve.
			local = local * local * (3.0 - 2.0 * local)
			return lerpf(StrictData.number(start.lane), StrictData.number(finish.lane), local)
	return StrictData.number(points[-1].lane)
