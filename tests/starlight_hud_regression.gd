extends SceneTree

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var progress: ProgressionService = GameServices.progression()
	var saved: Dictionary = progress.state.duplicate(true)
	progress.state = {"starlight":260, "starlight_token":{"enabled":true}}
	progress.starlight_wallet = {}
	if progress.starlight_text() != "…": fail("Unloaded token balance must not show ledger earnings as available funds"); return
	progress.starlight_wallet = {"status":"ready", "balance":"80", "pending":"60"}
	if progress.starlight_text() != "80" or not progress.starlight_hint().contains("60"): fail("Show actual wallet balance and pending earnings"); return
	var menu: ResceneMainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	menu.require_auth = false
	root.add_child(menu)
	menu._update_progression_hud()
	if menu._starlight_label.text != "80": fail("HUD must read ERC-20 wallet balance"); return
	progress.starlight_wallet.balance = "20.5"
	menu._update_progression_hud()
	if menu._starlight_label.text != "20.5": fail("Wallet transfers must be reflected without integer truncation"); return
	progress.state = {"starlight":260}
	if progress.starlight_text() != "260": fail("Unconfigured/offline fixtures retain ledger display"); return
	progress.state = saved
	progress.starlight_wallet = {}
	menu.queue_free()
	await create_timer(0.2).timeout
	print("Starlight wallet HUD, pending rewards and exact token display: PASS")
	quit()

func fail(message: String) -> void:
	push_error(message)
	quit(1)
