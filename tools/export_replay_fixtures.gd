extends SceneTree

var fixtures: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("generate")

func generate() -> void:
	var path: String = OS.get_environment("RESCENE_REPLAY_GOLDENS")
	if path.is_empty(): push_error("Set RESCENE_REPLAY_GOLDENS to an isolated temporary output."); quit(1); return
	for song: Dictionary in SongCatalog.SONGS:
		for difficulty: String in ["Easy","Normal","Hard","Ultra Hard"]:
			var song_chart: Dictionary = RhythmChart.load_chart(str(song.id),difficulty)
			capture(str(song.id),difficulty,song_chart)
		await process_frame
	var chart: Dictionary = RhythmChart.load_chart(SongCatalog.SONGS[0].id,"Easy")
	for frame_step: float in [1.0/30.0,1.0/60.0,1.0/240.0]: capture(SongCatalog.SONGS[0].id,"Easy",chart,false,frame_step)
	capture(SongCatalog.SONGS[0].id,"Easy",chart,true)
	capture(SongCatalog.SONGS[0].id,"Easy",chart,false,0.01,0.07)
	for offset: float in [-0.15,-0.09,-0.045,0.045,0.09,0.15]: capture(SongCatalog.SONGS[0].id,"Easy",chart,false,0.01,offset)
	capture(SongCatalog.SONGS[0].id,"Easy",chart,false,0.01,0.0,false)
	# Use a server-exported real slide to exercise keyboard lane handoffs.
	var keyboard: RhythmJudge = RhythmJudge.new()
	keyboard.setup(chart)
	var next: int = 0
	var t: float = 0.0
	while t < StrictData.number(chart.duration):
		while next < StrictData.array(chart.notes).size() and chart.notes[next].time <= t:
			var note: Dictionary = chart.notes[next]
			var lane: int = roundi(StrictData.number(note.lane))
			keyboard.release(-100-lane,StrictData.number(note.time))
			var _bool_1: bool = keyboard.press(-100-lane,lane,StrictData.number(note.time),true)
			if note.kind=="tap": keyboard.release(-100-lane,StrictData.number(note.time))
			next += 1
		for note: Dictionary in keyboard.notes:
			if note.state==1:
				var lane: int = roundi(RhythmChart.lane_at(note,t))
				var _bool_2: bool = keyboard.press(-100-lane,lane,t,true)
		keyboard.step(t,0.01)
		t += 0.01
	keyboard.finish(StrictData.number(chart.duration))
	append(SongCatalog.SONGS[0].id,"Easy",chart,keyboard)
	var pulse_song: Dictionary = {}
	for song: Dictionary in SongCatalog.SONGS:
		if str(song.title) == "With": pulse_song = song
	var pulse_chart: Dictionary = RhythmChart.load_chart(str(pulse_song.id), "Normal")
	for skill: int in range(1, 7):
		for stars: int in [1, 5]:
			for offset: float in [0.0, 0.07]:
				var boosted: RhythmJudge = RhythmJudge.new(); boosted.setup(pulse_chart)
				var skills: Array[int] = [0, 0, 0, 0, 0, 0, 0]; skills[skill] = stars
				boosted.card_loadout = {"id":"pulse_test", "version":2, "perfect_score_bp":6000, "recovery_ppm":6000, "skills":skills}
				ReplayFixture.autoplay(boosted, pulse_chart, false, 0.01, offset, true, 19)
				append(str(pulse_song.id), "Normal", pulse_chart, boosted)
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	var _bool_3: bool = file.store_string(JSON.stringify(fixtures))
	print("Exported ",fixtures.size()," Godot input replay fixtures.")
	quit()

func capture(song_id: String,difficulty: String,chart: Dictionary,with_pause: bool = false,frame_step: float = 0.01,offset: float = 0.0,movement: bool = true) -> void:
	var judge: RhythmJudge = RhythmJudge.new()
	judge.setup(chart)
	ReplayFixture.autoplay(judge,chart,with_pause,frame_step,offset,movement)
	append(song_id,difficulty,chart,judge)

func append(song_id: String,difficulty: String,chart: Dictionary,judge: RhythmJudge) -> void:
	fixtures.append({"song_id":song_id,"difficulty":difficulty,"dead":judge.dead,"paused":judge.paused,"card":judge.card_loadout,"card_points":judge.card_points,"life_milli":roundi(judge.life * 1000.0),"result":{"score":judge.score(),"max_combo":judge.max_combo,"counts":judge.counts.duplicate(),"trace":judge.trace,"replay":judge.replay_payload("parity-run",str(chart.revision))}})
