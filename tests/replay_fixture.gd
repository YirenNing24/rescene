class_name ReplayFixture
extends RefCounted
## Synthetic player inputs for tests; never changes judge totals directly.

static func autoplay(judge: RhythmJudge, chart: Dictionary, paused: bool = false, frame_step: float = 0.01, offset: float = 0.0, movement: bool = true, skip_heads: int = 0, slide_offset: float = 0.0) -> void:
	var inputs: Array[Dictionary] = []
	var free: Array[float] = []
	var _resize: int = free.resize(10)
	free.fill(-1.0)
	for index: int in range(skip_heads, StrictData.array(chart.notes).size()):
		var note: Dictionary = chart.notes[index]
		var at: float = StrictData.number(note.time) + offset
		var lane_offset: float = slide_offset if note.kind == "slide" else 0.0
		var swipe: bool = note.kind == "swipe"
		var begin: float = at - 0.04 if swipe else at
		var finish: float = at + StrictData.number(note.duration) + 0.01 if note.kind in ["hold", "slide"] else at
		var id: int = 0
		while id < 9 and free[id] > begin: id += 1
		free[id] = finish + 0.001
		_input(inputs, begin, 0, id, StrictData.number(note.lane) + lane_offset, 910.0 if swipe else -1.0)
		if swipe and movement: _input(inputs, at, 1, id, StrictData.number(note.lane), 840.0)
		if movement and note.kind == "slide":
			var tick: float = begin + 0.01
			while tick < finish:
				_input(inputs, tick, 1, id, RhythmChart.lane_at(note, tick - offset) + lane_offset)
				tick += 0.01
		_input(inputs, finish, 2, id)
	if paused: _input(inputs, 1.0 + offset, 3, 0)
	inputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at if a.at != b.at else a.order < b.order)
	var next: int = 0
	var time: float = -0.15
	var end: float = StrictData.number(chart.duration) + offset
	while time <= end + frame_step:
		while next < inputs.size() and StrictData.number(inputs[next].at) <= minf(time, end):
			var event: Dictionary = inputs[next]
			match StrictData.integer(event.kind):
				0:
					var _pressed: bool = judge.press(StrictData.integer(event.id), StrictData.number(event.lane), StrictData.number(event.at), false, StrictData.number(event.height))
				1: judge.move_pointer(StrictData.integer(event.id), StrictData.number(event.lane), StrictData.number(event.at), StrictData.number(event.height))
				2: judge.release(StrictData.integer(event.id), StrictData.number(event.at))
				3: judge.suspend(StrictData.number(event.at))
			next += 1
		judge.step(minf(time, end), frame_step)
		time += frame_step
	judge.finish(end)

static func _input(inputs: Array[Dictionary], time: float, kind: int, id: int, lane: float = 0.0, height: float = -1.0) -> void:
	inputs.append({"at":time,"kind":kind,"id":id,"lane":lane,"height":height,"order":inputs.size()})
