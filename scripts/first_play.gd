class_name FirstPlay
extends RefCounted
## Fixed teaching chart; never sent to the run/reward endpoints.
static func chart() -> Dictionary:
	var notes: Array[Dictionary] = []
	for time: float in [5.0, 7.0, 9.0]: _note(notes, time, 2.0)
	_note(notes, 15.0, 1.0, "hold", 3.0)
	_note(notes, 24.0, 0.0, "slide", 4.0)
	for time: float in [30.5, 32.0, 33.5]: _note(notes, time, 2.0, "swipe")
	for index: int in 20: _note(notes, 36.0 + float(index) * 0.45, float(index % 5))
	return {"tempo":120.0, "quarter":0.5, "duration":47.0, "difficulty":"Tutorial", "notes":notes, "revision":"tutorial-v2"}

static func _note(notes: Array[Dictionary], time: float, lane: float, kind: String = "tap", duration: float = 0.0) -> void:
	var checkpoints: Array[float] = []
	if kind in ["hold", "slide"]:
		var tick: float = time + 0.25
		while tick < time + duration - 0.01: checkpoints.append(tick); tick += 0.25
		checkpoints.append(time + duration)
	var curve: Array[Dictionary] = []
	if kind == "slide": curve.assign([{"at":0.0,"lane":0.0}, {"at":0.5,"lane":2.0}, {"at":1.0,"lane":4.0}])
	notes.append({"id":notes.size(), "time":time, "lane":lane, "kind":kind, "duration":duration, "curve":curve, "checkpoints":checkpoints, "state":0, "owner":-999, "next_tick":0, "gap":0.0})

static func account_key() -> String:
	return (GameServices.session().api_url() + "/" + str(GameServices.session().user.get("id", "local"))).sha256_text()

static func seen() -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://tutorial.cfg") != OK: return false
	return StrictData.boolean(config.get_value(account_key(), "seen", false))

static func mark_seen() -> void:
	var config: ConfigFile = ConfigFile.new()
	var _loaded: Error = config.load("user://tutorial.cfg")
	config.set_value(account_key(), "seen", true)
	var _saved: Error = config.save("user://tutorial.cfg")
