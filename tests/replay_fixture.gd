class_name ReplayFixture
extends RefCounted
## Synthetic player inputs for tests; never changes judge totals directly.

static func autoplay(judge: RhythmJudge, chart: Dictionary, paused: bool = false, frame_step: float = 0.01, offset: float = 0.0, movement: bool = true, skip_heads: int = 0) -> void:
	var next: int = 0
	var owners: Dictionary = {}
	var t: float = 0.0
	var did_pause: bool = false
	while t <= StrictData.number(chart.duration) + 0.01:
		while next < StrictData.array(chart.notes).size() and StrictData.number(chart.notes[next].time) <= t:
			if next < skip_heads: next += 1; continue
			var note: Dictionary = chart.notes[next]
			var at: float = StrictData.number(note.time)
			for id: int in owners.keys():
				if StrictData.number(owners[id].time) + StrictData.number(owners[id].duration) + 0.01 <= at:
					judge.release(id, at + offset)
					var _bool_1: bool = owners.erase(id)
			var id: int = 0
			while owners.has(id): id += 1
			var _bool_2: bool = judge.press(id,StrictData.number(note.lane), at + offset)
			if note.kind == "tap": judge.release(id, at + offset)
			else: owners[id] = note
			next += 1
		for id: int in owners.keys():
			var note: Dictionary = owners[id]
			if t >= StrictData.number(note.time) + StrictData.number(note.duration) + 0.01:
				judge.release(id, minf(t,StrictData.number(chart.duration)) + offset)
				var _bool_3: bool = owners.erase(id)
			elif movement: judge.move_pointer(id, preload("res://scripts/rhythm_chart.gd").lane_at(note,t), minf(t,StrictData.number(chart.duration)) + offset)
		if paused and not did_pause and t >= 1.0:
			judge.suspend(t + offset)
			for id: int in owners:
				var _bool_4: bool = judge.press(id, preload("res://scripts/rhythm_chart.gd").lane_at(StrictData.dictionary(owners[id]),t),t + offset)
			did_pause = true
		judge.step(minf(t,StrictData.number(chart.duration)) + offset,frame_step)
		t += frame_step
	judge.finish(StrictData.number(chart.duration) + offset)
