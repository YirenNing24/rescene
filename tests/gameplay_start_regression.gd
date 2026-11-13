extends SceneTree
## A local HTTP fixture holds a wallet read until the run request arrives.
var failures: int = 0
var background_done: bool = false

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	if OS.get_environment("RESCENE_AUTH_FILE").is_empty(): quit(1); return
	var session: ResceneAuthSession = GameServices.session()
	var progress: ProgressionService = GameServices.progression()
	session.set_process(false); progress.set_process(false)
	session.user = {"id":"runtime-fixture","username":"runtime-fixture"}
	session._token = "fixture-access"
	session._refresh_token = "r".repeat(43)
	session._expires_at_ms = Time.get_ticks_msec() + 3600000
	background_read.call_deferred()
	while not session.busy: await process_frame
	var run_id: String = await progress.begin_run(str(SongCatalog.SONGS[0].id), "Normal")
	check(run_id == "fixture-run", "A valid run must bypass the unrelated wallet HTTP queue")
	while not background_done: await process_frame
	session._token = "rejected-access"
	var response: Dictionary = await session.start_gameplay_run({})
	check(StrictData.boolean(response.get("ok", false)) and session._token == "renewed-access", "Rejected access must still refresh and retry safely")
	session._expires_at_ms = Time.get_ticks_msec() - 1
	response = await session.start_gameplay_run({})
	check(StrictData.boolean(response.get("ok", false)), "Expired access must renew before requesting a run")
	var _changed: int = create_timer(0.05).timeout.connect(func() -> void: session._generation += 1)
	response = await session.start_gameplay_run({"delay":true})
	check(not StrictData.boolean(response.get("ok", false)), "Account changes must discard an in-flight run response")
	session.user = {}; session._token = ""; session._refresh_token = ""
	session._delete_saved_session()
	print("Gameplay start queue, refresh and account isolation: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)

func background_read() -> void:
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/starlight")
	check(StrictData.boolean(response.get("ok", false)), "Background read completes independently")
	background_done = true

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1; push_error(message)
