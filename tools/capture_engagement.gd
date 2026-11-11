extends SceneTree

func _initialize() -> void:
	capture.call_deferred()

func capture() -> void:
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false; root.add_child(menu)
	await create_timer(0.7).timeout
	menu._open_songs()
	menu._open_mastery(SongCatalog.SONGS[0])
	var view: MasteryView = menu._dialog as MasteryView
	view._data = {"completed":2,"milestones":[
		{"id":"easy","name":"Opening note","description":"Clear Easy.","complete":true,"claimed":false,"xp":40,"starlight":20,"shards":0},
		{"id":"normal","name":"Finding the rhythm","description":"Clear Normal.","complete":true,"claimed":true,"xp":60,"starlight":30,"shards":0},
		{"id":"hard","name":"In the spotlight","description":"Clear Hard.","complete":false,"claimed":false,"xp":80,"starlight":40,"shards":0},
		{"id":"ultra_hard","name":"A brighter stage","description":"Clear Ultra Hard.","complete":false,"claimed":false,"xp":120,"starlight":60,"shards":0},
		{"id":"accuracy","name":"Every beat","description":"Clear with at least 90% accuracy on any difficulty.","complete":false,"claimed":false,"xp":80,"starlight":40,"shards":0},
		{"id":"full_combo","name":"Perfect harmony","description":"Full combo any difficulty.","complete":false,"claimed":false,"xp":100,"starlight":50,"shards":1}]}
	view._render()
	await snap("song-mastery-preview")
	menu._open_coop()
	var duet: CoopView = menu._dialog as CoopView
	duet._week = "2026-11-09"
	duet._duets = [{"id":"fixture","owner":"me","peer":"friend","owner_name":"RE:PLAYER","peer_name":"RE:MINE","week":"2026-11-09","status":"active","owner_clears":3,"peer_clears":2,"goals":[{"id":"clears","name":"Together on stage","description":"Clear 6 songs together. Each friend contributes at least once.","progress":5,"target":6,"xp":150,"starlight":100,"complete":false,"claimed":false},{"id":"perfect","name":"Perfect together","description":"Earn 1,000 PERFECT judgments together.","progress":1000,"target":1000,"xp":200,"starlight":150,"complete":true,"claimed":false}]}]
	duet._render()
	await snap("weekly-duet-preview")
	menu.queue_free(); await process_frame; quit()

func snap(file_name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://previews/"+file_name+".png")
	if error != OK: push_error("Could not save preview.")
