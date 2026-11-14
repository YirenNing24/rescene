extends SceneTree
## Offline CPU and rendered stress workload. Never submits scores or purchases.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var chart: Dictionary = {}
	var song: Dictionary = {}
	for candidate: Dictionary in SongCatalog.SONGS:
		var loaded: Dictionary = RhythmChart.load_chart(str(candidate.id), "Ultra Hard")
		if StrictData.array(loaded.notes).size() > StrictData.array(chart.get("notes", [])).size(): chart = loaded; song = candidate
	var report: Dictionary = {"song":str(song.title),"notes":StrictData.array(chart.notes).size(),"rendered":DisplayServer.get_name() != "headless"}
	var judge: RhythmJudge = RhythmJudge.new()
	judge.setup(chart)
	judge.life = 1000000.0
	var samples: Array[float] = []
	var time: float = 0.0
	while time < StrictData.number(chart.duration):
		var start: int = Time.get_ticks_usec()
		judge.step(time, 1.0 / 60.0)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
		time += 1.0 / 60.0
	report.judge_ms = statistics(samples)
	var stage: RhythmStage = RhythmStage.new()
	stage.mobile_rendering = true
	stage.approach_seconds = 1.45
	var highway: RhythmHighway = RhythmHighway.new()
	highway.game = stage
	samples.clear()
	var ribbons: Array[Dictionary] = []
	for note: Dictionary in chart.notes:
		if note.kind == "slide": ribbons.append(note)
	for index: int in 1200:
		var note: Dictionary = ribbons[index % ribbons.size()]
		stage.visual_age = float(index) / 60.0
		var start: int = Time.get_ticks_usec()
		var _strip: Dictionary = highway._ribbon_strip(note, Color("a99acb"), StrictData.number(note.time) + StrictData.number(note.duration) * 0.4)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	report.ribbon_ms = statistics(samples)
	highway.free(); stage.free()
	if DisplayServer.get_name() != "headless": await render_stress(song, report)
	var path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://builds/gameplay-benchmark.json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var _stored: bool = output.store_string(JSON.stringify(report, "  "))
	output.close()
	print(JSON.stringify(report))
	quit()

func render_stress(song: Dictionary, report: Dictionary) -> void:
	for index: int in 5:
		GameServices.commerce().inventory.append({"id":"pulse_%d" % (900 + index),"template_id":"scene_%02d" % (index+1),"member_name":SongSets.MEMBERS[index],"member_index":index,"category":"cards","quantity":1,"level":20,"stars":2,"skill":"Overture"})
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; menu.force_mobile_gameplay_rendering = true
	root.add_child(menu); current_scene = menu
	await create_timer(0.3).timeout
	menu._open_songs(); menu._request_song_start(song,"Ultra Hard")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true; stage.set_process(false); stage.audio.stop()
	stage.phase = "playing"; stage.song_time = 40.0; stage.visual_age = 40.0
	stage._count_label.hide()
	var stress_notes: Array[Dictionary] = []
	for note: Dictionary in stage.judge.notes:
		if note.time < 38.0: note.state = 2; stress_notes.append(note)
	for lane: int in 5:
		stress_notes.append({"id":stress_notes.size(),"time":39.0,"duration":4.0,"lane":float(lane),"kind":"slide","curve":[{"at":0.0,"lane":float(lane)},{"at":1.0,"lane":float(lane)}],"checkpoints":[43.0],"next_tick":0,"state":1,"owner":lane,"gap":0.0})
	stage.judge.setup({"notes":stress_notes,"duration":100.0})
	for lane: int in 5:
		stage.judge.pointers[lane] = {"lane":float(lane),"keyboard":false}
	stage.judge.step(40.0, 0.0)
	stage.deck_showcase.configure(["pulse_900","pulse_901","pulse_902","pulse_903","pulse_904"])
	stage.highway._fx_rng.seed = 42
	if OS.get_cmdline_user_args().has("--max-momentum"):
		stage.judge.combo = 85
		stage.momentum_visual = 3.0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var frames: Array[float] = []
	var calls: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for frame: int in 420:
		stage.visual_age = 40.0 + float(frame) / 60.0
		stage._process(0.0)
		if frame % 4 == 0: stage.highway.hit("PERFECT", float(frame % 5), 1.0)
		if frame % 10 == 0: stage.highway.combo_effects.on_judgment(frame + 10, float(frame % 5), 1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		if frame >= 60:
			frames.append(float(now - previous) / 1000.0)
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		previous = now
	report.render_frame_ms = statistics(frames)
	report.render_calls = statistics(calls)
	var _saved: Error = root.get_texture().get_image().save_png("res://previews/gameplay-stress.png")
	menu.queue_free(); await create_timer(0.2).timeout

func statistics(samples: Array[float]) -> Dictionary:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted: total += value
	return {"mean":snappedf(total / sorted.size(),0.001),"p50":sorted[floori(sorted.size()*0.5)],"p95":sorted[mini(sorted.size()-1,floori(sorted.size()*0.95))],"p99":sorted[mini(sorted.size()-1,floori(sorted.size()*0.99))]}
