extends SceneTree
## Wider slide tracking, honest contact feedback, multi-touch and lifecycle reset.
var failures: int = 0

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; menu.force_mobile_gameplay_rendering = true
	root.add_child(menu); current_scene = menu
	menu._open_songs()
	await process_frame
	menu._request_song_start(SongCatalog.SONGS[0], "Easy")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true; stage.set_process(false); stage.audio.stop()
	stage.phase = "playing"; stage._count_label.hide()
	var fixture: Dictionary = RhythmChart.normalize({"tempo":120,"ticks_per_beat":400,"duration_seconds":5,"tracks":[
		{"bars":[]}, {"bars":[{"notes":[{"pos":800,"len":1600,"kind":"slide","curve":[{"at":0.0,"lane":1.0},{"at":1.0,"lane":3.0}]}]}]},
		{"bars":[]}, {"bars":[]}, {"bars":[{"notes":[{"pos":800,"len":1600,"kind":"hold"}]}]}]})
	stage.judge.setup(fixture)
	check(stage.judge.press(0, 1.9, 1.0, false, 895.0), "A slide head accepts the wider offset")
	check(stage.judge.press(1, 4.0, 1.0, false, 895.0), "Another finger independently holds a straight ribbon")
	var note: Dictionary = stage.judge.notes[0]
	for tick: int in range(1, 51):
		var time: float = 1.0 + float(tick) * 0.01
		stage.judge.move_pointer(0, RhythmChart.lane_at(note, time) + 0.9, time, 895.0)
		stage.judge.step(time, 0.01)
	stage.song_time = 1.5; stage.visual_age = 1.5
	stage.highway.sustain_effects._process(0.0)
	stage.highway.slide_touches._process(0.0)
	var glow: Sprite2D = stage.highway.slide_touches._sprites[0]
	check(glow.visible, "Tracking a slide within the wider region shows a contact glow")
	var finger_lane: float = StrictData.number(stage.judge.pointers[0].lane)
	check(glow.position.is_equal_approx(Vector2(stage.highway.project(finger_lane, 0.0).x, 895.0)), "Glow is centered on the actual finger, not the ribbon target")
	check(stage.highway.sustain_effects._is_collected(note), "Vortex collection uses the same wider tolerance")
	check(stage.highway.slide_touches._sprites[1].visible == false, "Straight holds do not duplicate slide contact effects")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var saved: Error = root.get_texture().get_image().save_png("res://previews/slide-touch-glow-20-9.png")
		check(saved == OK, "Capture mobile-rendered slide feedback")
	stage.phase = "paused"
	var frozen: Vector2 = glow.position
	stage.highway.slide_touches._process(1.0)
	check(glow.position == frozen and glow.visible, "Pause freezes contact feedback")
	stage.phase = "playing"
	stage.judge.move_pointer(0, finger_lane, 1.51, 500.0)
	stage.highway.slide_touches._process(0.0)
	check(not glow.visible and not stage.highway.sustain_effects._is_collected(note), "Leaving the collector removes glow and collected feedback immediately")
	stage.judge.move_pointer(0, RhythmChart.lane_at(note, 1.52) + 0.9, 1.52, 895.0)
	stage.song_time = 1.52; stage.highway.slide_touches._process(0.0)
	check(glow.visible, "Returning within release grace restores contact feedback")
	stage.judge.release(0, 1.53)
	stage.highway.slide_touches._process(0.0)
	check(not glow.visible, "Releasing a finger removes the glow")
	stage.judge.setup(fixture)
	stage.highway.slide_touches._process(0.0)
	check(not glow.visible, "Retry clears every prior slide glow")
	for offset: float in [-0.9, 0.9]:
		var judge: RhythmJudge = RhythmJudge.new(); judge.setup(fixture)
		ReplayFixture.autoplay(judge, fixture, false, 0.01, 0.0, true, 0, offset)
		check(judge.score() == 1000000 and judge.counts.MISS == 0, "Wider tracking completes both slide and hold without scoring changes")
	stage.judge.setup(fixture)
	check(not stage.judge.press(0, 2.0, 1.0), "An adjacent lane cannot collect the slide")
	menu.queue_free()
	await create_timer(0.2).timeout
	print("Slide collection and contact feedback: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func check(condition: bool, detail: String) -> void:
	if not condition: failures += 1; push_error(detail)
