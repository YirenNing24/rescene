extends SceneTree
## Validate clipped ribbon strips across every chart, including shrinking tails.

var failures: int = 0
var cases_checked: int = 0

class RibbonCanvas extends "res://scripts/rhythm_highway.gd":
	var samples: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _draw() -> void:
		for sample: Dictionary in samples:
			game.approach_seconds = sample.approach
			_draw_ribbon(StrictData.dictionary(sample.note), Color("a99acb"),StrictData.number(sample.now))

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var highway: RhythmHighway = RhythmHighway.new()
	var game: RhythmStage = RhythmStage.new()
	game.approach_seconds = 1.45
	highway.game = game
	var canvas: RibbonCanvas = RibbonCanvas.new()
	canvas.game = game
	game.visual_age = 0.55
	verify_curved_style(highway, game)
	for song: Dictionary in SongCatalog.SONGS:
		for difficulty: String in ["Easy", "Normal", "Hard", "Ultra Hard"]:
			var approach: float = {"Easy": 2.2, "Normal": 1.9, "Hard": 1.65, "Ultra Hard": 1.45}[difficulty]
			highway.game.approach_seconds = approach
			var chart: Dictionary = RhythmChart.load_chart(str(song.id), difficulty)
			for note: Dictionary in chart.notes:
				if note.kind in ["tap", "swipe"]: continue
				for active: bool in [false, true]:
					note.state = 1 if active else 0
					var tail: float = note.time + note.duration
					for now: float in [note.time - approach, note.time - approach + 0.000001,
						note.time - 0.1, note.time, note.time + note.duration * 0.5,
						tail - 0.001, tail - 0.000001, tail, tail + 0.01]:
						var strip: Dictionary = highway._ribbon_strip(note, Color("a99acb"), now)
						cases_checked += 1
						if strip.is_empty(): continue
						var points: PackedVector2Array = strip.points
						var colors: PackedColorArray = strip.colors
						var indices: PackedInt32Array = strip.indices
						check(StrictData.boolean(points.size() == colors.size()), "Every vertex needs a matching color")
						check(StrictData.boolean(indices.size() % 3 == 0), "Indices must describe whole triangles")
						for vertex: Vector2 in strip.points:
							check(vertex.is_finite(), "Ribbon coordinates must remain finite")
						for index: int in strip.indices:
							check(StrictData.boolean(index >= 0 and index < points.size()), "Triangle indices must stay in bounds")
						if canvas.samples.size() < 64:
							canvas.samples.append({"note": note.duplicate(true), "now": now, "approach": approach})
	# Exercise the real canvas command path, not just the strip builder.
	root.add_child(canvas)
	await process_frame
	await process_frame
	canvas.queue_free()
	highway.free()
	game.free()
	await process_frame
	print("Ribbon boundaries: ", cases_checked, " cases; ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(failures)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func verify_curved_style(highway: RhythmHighway, game: RhythmStage) -> void:
	var fixture: Dictionary = RhythmChart.normalize({"tempo": 120, "ticks_per_beat": 400,
		"duration_seconds": 5, "tracks": [{"bars": [{"notes": [{"pos": 800, "len": 1600,
		"kind": "slide", "curve": [{"at": 0.0, "lane": 0.0}, {"at": 1.0, "lane": 3.0}]}]}]}]})
	var note: Dictionary = StrictData.dictionary(StrictData.array(fixture.notes)[0])
	note.state = 1
	var first: Dictionary = highway._ribbon_strip(note, Color("a99acb"), 1.2)
	var points: PackedVector2Array = first.points
	var colors: PackedColorArray = first.colors
	var width: float = points[3].x - points[1].x
	check(width > highway.CATCHER_RADIUS * 2.3 and width < highway.CATCHER_RADIUS * 2.6, "A collected curved ribbon must have a wider readable tracing surface")
	game.visual_age += 0.5
	var changed: Dictionary = highway._ribbon_strip(note, Color("a99acb"), 1.2)
	var changed_colors: PackedColorArray = changed.colors
	check(not colors[2].is_equal_approx(changed_colors[2]), "Curved ribbon colors must animate while chart position stays fixed")
	check(StrictData.boolean(first.points == changed.points), "Color pulsing must not change the tracing path")
	var frozen: Dictionary = highway._ribbon_strip(note, Color("a99acb"), 1.2)
	check(StrictData.boolean(changed.colors == frozen.colors), "A frozen visual clock must freeze the color pulse")
	note.kind = "hold"
	var straight: Dictionary = highway._ribbon_strip(note, Color("a99acb"), 1.2)
	var straight_points: PackedVector2Array = straight.points
	check(straight_points[3].x - straight_points[1].x < width * 0.6, "Straight holds must retain their existing width")
