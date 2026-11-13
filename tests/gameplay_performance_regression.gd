extends SceneTree
## Culling must match a full scan through all charts and retries. The deck must
## reuse its prepared nodes instead of allocating new portraits during play.

var failures: int = 0
var cases: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var stage: RhythmStage = RhythmStage.new()
	var highway: RhythmHighway = RhythmHighway.new()
	highway.game = stage
	stage.judge = RhythmJudge.new()
	for song: Dictionary in SongCatalog.SONGS:
		for difficulty: String in ["Easy","Normal","Hard","Ultra Hard"]:
			var chart: Dictionary = RhythmChart.load_chart(str(song.id),difficulty)
			stage.judge.setup(chart)
			stage.judge.life = 1000000.0
			for sample: int in 25:
				stage.song_time = StrictData.number(chart.duration) * float(sample) / 25.0
				stage.judge.step(stage.song_time, 0.0)
				for approach: float in [1.45,2.2]:
					stage.approach_seconds = approach
					check_window(highway,stage)
			stage.judge.setup(chart)
			stage.song_time = 0.0
			check_window(highway,stage)
		await process_frame
	highway.free(); stage.free()
	var commerce: CommerceService = GameServices.commerce()
	for member: int in 5:
		commerce.inventory.append({"id":"pulse_%d" % (900+member),"template_id":"scene_%02d" % (member+1),"category":"cards","quantity":1,"member_name":SongSets.MEMBERS[member],"member_index":member,"level":1,"stars":1})
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; root.add_child(menu); current_scene = menu
	var showcase: DeckShowcase = DeckShowcase.new(); showcase.host = menu
	showcase.deck_ids = ["pulse_900","pulse_901","pulse_902","pulse_903","pulse_904"]
	menu.add_child(showcase)
	var portraits: Dictionary[int,int] = {}
	for member: int in 5: portraits[member] = showcase._portraits[member].get_instance_id()
	for turn: int in 30:
		showcase.show_time(float(turn)*4.5+1.0)
		check(showcase._portrait.get_instance_id() == portraits[turn%5], "Carousel must reuse the prepared member portrait")
	menu.queue_free(); await create_timer(0.2).timeout
	print("Gameplay culling: %d windows; prepared card carousel: %s" % [cases,"PASS" if failures == 0 else "FAIL"])
	quit(failures)

func check_window(highway: RhythmHighway, stage: RhythmStage) -> void:
	var expected: Array[int] = []
	for note: Dictionary in stage.judge.notes:
		if note.state < 2 and note.time <= stage.song_time + stage.approach_seconds and note.time + note.duration >= stage.song_time - 0.2: expected.append(StrictData.integer(note.id))
	var actual: Array[int] = []
	for note: Dictionary in highway.visible_notes(): actual.append(StrictData.integer(note.id))
	cases += 1
	check(expected == actual, "Visible notes must match the full chart scan, including retry and approach changes")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
