extends SceneTree

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var progression: ProgressionService = GameServices.progression()
	progression.state = {"events":[{"id":"pulse_first_scene_2026","status":"active","starts_at":"2026-11-10T16:00:00Z","ends_at":"2026-11-24T16:00:00Z","claim_ends_at":"2026-11-26T16:00:00Z","featured_song_id":"ca722c0b0e8b","featured_title":"Finest Thing","rotation_at":"2026-11-11T16:00:00Z","missions":[
		{"id":"opening","name":"Your PULSE begins","description":"Clear a PULSE song.","target":1,"progress":1,"xp":100,"starlight":50,"shards":0,"claimed":false,"claimable":true},
		{"id":"encore","name":"Five little encores","description":"Clear 5 PULSE songs. Repeats count.","target":5,"progress":2,"xp":250,"starlight":100,"shards":1},
		{"id":"featured","name":"In the spotlight","description":"Clear the featured song 3 times. The spotlight rotates daily.","target":3,"progress":1,"xp":200,"starlight":100,"shards":1},
		{"id":"perfect","name":"A thousand perfect moments","description":"Collect 1,000 PERFECT judgments in cleared PULSE songs.","target":1000,"progress":250,"xp":300,"starlight":150,"shards":2},
		{"id":"harmony","name":"Perfect harmony","description":"Full combo any PULSE song. Any difficulty counts.","target":1,"progress":0,"xp":250,"starlight":100,"shards":1},
		{"id":"album","name":"Every side of PULSE","description":"Clear all 5 different PULSE songs.","target":5,"progress":1,"xp":400,"starlight":200,"shards":2},
		{"id":"finale","name":"The first scene, complete","description":"Complete all 6 event missions.","target":6,"progress":1,"xp":500,"starlight":250,"shards":3}
	]}]}
	progression._event_unix = Time.get_unix_time_from_datetime_string("2026-11-11T00:00:00")
	progression._event_tick = Time.get_ticks_msec()
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	await create_timer(0.8).timeout
	menu._open_event()
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://previews/pulse-event-game.png")
	if error != OK: push_error("Could not save event screenshot.")
	menu.queue_free()
	await process_frame
	quit()
