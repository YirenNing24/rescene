extends SceneTree
## Local-only visual review with approved LE art; no account or chain mutations.

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var commerce: CommerceService = GameServices.commerce()
	var ids: Array[String] = []
	for member: int in 5:
		var id: String = "pulse_%d" % (901 + member)
		ids.append(id)
		commerce.inventory.append({"id":id, "template_id":"scene_%02d" % (member + 1), "category":"cards", "set_id":"pulse", "member_name":SongSets.MEMBERS[member], "member_index":member, "quantity":1, "stars":2, "level":12, "skill":"Overture"})
	commerce.decks["pulse"] = ids
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	menu.force_mobile_gameplay_rendering = true
	root.add_child(menu)
	current_scene = menu
	menu._open_songs()
	await process_frame
	var song: Dictionary = SongCatalog.SONGS[0]
	for entry: Dictionary in SongCatalog.SONGS:
		if str(entry.title) == "With": song = entry
	menu._request_song_start(song, "Hard")
	var stage: RhythmStage = menu._stage
	stage.test_mode = true
	stage.set_process(false)
	stage.audio.stop()
	stage.phase = "playing"
	stage._count_label.hide()
	var next: int = 0
	var time: float = 0.0
	var until: float = 6.0
	for note: Dictionary in stage.judge.notes:
		if note.kind == "slide":
			until = StrictData.number(note.time) + StrictData.number(note.duration) * 0.27
			break
	while time <= until:
		stage.song_time = time
		stage.visual_age = time
		while next < stage.judge.notes.size() and StrictData.number(stage.judge.notes[next].time) <= time:
			var note: Dictionary = stage.judge.notes[next]
			var _hit: bool = stage.judge.press(next, StrictData.number(note.lane), StrictData.number(note.time))
			if note.kind == "tap": stage.judge.release(next)
			next += 1
		for note: Dictionary in stage.judge.notes:
			if note.state == 1: stage.judge.move_pointer(StrictData.integer(note.owner), RhythmChart.lane_at(note, time))
		stage.judge.step(time, 0.01)
		time += 0.01
	stage._process(0.0)
	stage.deck_showcase.show_time(5.8)
	await snap("gameplay-wide-road-cards.png")
	stage.deck_showcase.configure([])
	await snap("gameplay-wide-road-empty.png")
	menu.queue_free()
	await create_timer(0.2).timeout
	quit()

func snap(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://previews/" + filename)
	if error != OK: push_error("Could not save wide road preview")
