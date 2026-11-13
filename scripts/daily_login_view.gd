class_name DailyLoginView
extends MenuDestination
## Account-owned daily gifts. All reward amounts and eligibility come from Fiber.

var _countdown: Label
var _busy: bool = false
var _notice: String = ""
var _clock: float = 0.0
var _refresh_at: int = 0

func _ready() -> void:
	name = "DailyLoginView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var _int_1: int = GameServices.progression().changed.connect(_render)
	_render()

func _render() -> void:
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var width: float = host._width
	var _panel_2: Panel = host._panel(body, Rect2(30, 155, width-60, 885), Color("111325"), Color(0.72,0.68,0.95,0.35), 26)
	var back: Button = host._button(body, "‹", Rect2(60,185,72,65), host._close_dialog)
	back.add_theme_font_size_override("font_size", 35)
	var _label_3: Label = host._label(body, "DAILY GIFTS", Rect2(159,185,1000,50), 36, host.WHITE, host.BOLD)
	var _label_4: Label = host._label(body, "SEVEN LITTLE REASONS TO RETURN", Rect2(162,243,1000,26), 13, host.LILAC)
	var refresh: Button = host._button(body, "REFRESH", Rect2(width-350,189,260,64), func() -> void:
		_notice = ""
		GameServices.progression().refresh.call_deferred())
	refresh.disabled = _busy or GameServices.progression().loading
	_summary()
	var login: Dictionary = GameServices.progression().state.get("daily_login", {})
	if login.is_empty():
		var _label_5: Label = host._label(body, "Your gifts are loading…" if GameServices.progression().loading else "Connect to the server to load your calendar.", Rect2(650,470,width-750,100), 28, host.MUTED)
	else:
		_calendar(login)
	var message: String = _notice if not _notice.is_empty() else GameServices.progression().error_message
	if message.is_empty(): message = "One gift per day · Resets at 00:00 UTC · Missed days keep your progress."
	var footer: Label = _wrapped(message, Rect2(650,944,width-750,66),18,host.LILAC)
	footer.name = "DailyGiftMessage"
	_update_countdown()

func _summary() -> void:
	var _panel_6: Panel = host._panel(body, Rect2(60,320,530,680), Color("24223d"), Color(0.7,0.65,0.95,0.28), 22)
	var _label_7: Label = host._label(body, "A LITTLE ENCORE", Rect2(94,353,450,28), 15, host.LILAC, host.BOLD)
	var _texturerect_8: TextureRect = host._icon(body, "gift", Rect2(98,415,95,95), host.LILAC)
	var _label_9: Label = host._label(body, "Every day,\na new scene.", Rect2(92,546,450,170), 52, host.WHITE, host.ITALIC)
	var explanation: Label = _wrapped("Collect XP and Starlight. Finish all seven days for an extra special gift, then begin again.", Rect2(96,745,450,100),21,host.MUTED)
	explanation.name = "DailyGiftHint"
	host._line(body, Rect2(96,873,450,1), Color(0.7,0.65,0.95,0.25))
	_countdown = host._label(body, "", Rect2(96,900,450,38), 22, host.LILAC, host.BOLD)
	var _label_10: Label = host._label(body, "NEXT DAILY RESET", Rect2(97,949,450,24), 12, host.MUTED)

func _wrapped(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	# Enable wrapping before assigning text so its unwrapped minimum width
	# cannot expand this absolute-positioned label beyond the card.
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_font_override("font",host.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	host._at(body,label,rect)
	return label

func _calendar(login: Dictionary) -> void:
	var available_width: float = host._width-740
	var gap: float = 18.0
	var column: float = (available_width-gap*3) / 4.0
	var completed: int = StrictData.integer(login.completed)
	var claimed: bool = login.claimed_today
	for reward: Dictionary in login.get("rewards", []):
		var day: int = StrictData.integer(reward.day)
		var rect: Rect2
		if day == 7:
			rect = Rect2(650+3*(column+gap),320,column,500)
		else:
			var index: int = day-1
			rect = Rect2(650+(index%3)*(column+gap),320+floori(StrictData.number(index)/3.0)*259,column,241)
		var is_current: bool = not claimed and day == StrictData.integer(login.next_day)
		var collected: bool = day <= completed
		var tint: Color = host.MINT if is_current or collected else Color("e3b5ce") if day == 7 else host.LILAC
		var fill: Color = Color("243a3c") if is_current else Color("201f36")
		var _panel_11: Panel = host._panel(body,rect,fill,Color(tint,0.85 if is_current else 0.25),20)
		var _label_12: Label = host._label(body,"DAY %02d" % day,Rect2(rect.position+Vector2(24,20),Vector2(column-48,32)),21,tint,host.BOLD)
		var center_y: float = rect.position.y + (123 if day == 7 else 78)
		if day == 7:
			var _label_13: Label = host._label(body,"THE ENCORE",Rect2(rect.position+Vector2(24,65),Vector2(column-48,28)),13,host.MUTED)
			var _texturerect_14: TextureRect = host._icon(body,"gift",Rect2(rect.position.x+column*0.5-45,center_y,90,90),tint)
			center_y += 141
		var _label_15: Label = host._label(body,"+%d XP" % StrictData.integer(reward.xp),Rect2(rect.position.x+24,center_y,column-48,42),32,host.WHITE,host.BOLD)
		var _label_16: Label = host._label(body,"+%d Starlight" % StrictData.integer(reward.starlight),Rect2(rect.position.x+25,center_y+53,column-48,30),20,tint)
		var status: String = "COLLECTED" if collected else "TODAY'S GIFT" if is_current else "UPCOMING"
		var status_label: Label = host._label(body,status,Rect2(rect.position.x+24,rect.end.y-45,column-48,26),13,tint if is_current else host.MUTED,host.BOLD)
		status_label.name = "DailyGiftDay%dStatus" % day
	var claimable: bool = not claimed and GameServices.progression().daily_reset_seconds() != 0
	var label: String = "CLAIMING…" if _busy else "CLAIM DAY %d" % StrictData.integer(login.next_day) if claimable else "COME BACK TOMORROW"
	var claim: Button = host._button(body,label,Rect2(650,849,available_width,72),func() -> void: await _claim(str(login.date),StrictData.integer(login.next_day)),claimable)
	claim.name = "ClaimDailyGiftButton"
	claim.disabled = _busy or GameServices.progression().loading or not claimable
	claim.add_theme_stylebox_override("disabled",host._style(Color("28253f"),Color(0.7,0.65,0.95,0.25),16))
	claim.add_theme_color_override("font_disabled_color",host.MUTED)

func _claim(date: String, day: int) -> void:
	if _busy: return
	_busy = true
	_notice = ""
	_render()
	var response: Dictionary = await GameServices.progression().claim_daily_login(date,day)
	if not is_inside_tree(): return
	_busy = false
	if response.ok:
		var reward: Dictionary = response.data.reward
		_notice = "Already collected today. Your gift is safe." if reward.get("already_claimed",false) else "DAY %d COLLECTED  /  +%d XP  ·  +%d Starlight" % [reward.day,reward.xp,reward.starlight]
		if StrictData.integer(reward.level_after) > StrictData.integer(reward.level_before): _notice += "  ·  LEVEL UP!"
		if not StrictData.array(reward.get("unlocks",[])).is_empty(): _notice += "  ·  Unlocked: " + ", ".join(PackedStringArray(StrictData.array(reward.unlocks)))
	else:
		_notice = response.get("message","Could not claim your gift. Please try again.")
	_render()

func _update_countdown() -> void:
	if not is_instance_valid(_countdown): return
	var seconds: int = GameServices.progression().daily_reset_seconds()
	_countdown.text = "%02d : %02d : %02d" % [floori(seconds/3600.0),floori((seconds%3600)/60.0),seconds%60] if seconds >= 0 else "00:00 UTC"

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0: return
	_clock = 0.0
	_update_countdown()
	# Refresh promptly across midnight even with a wrong device wall clock.
	if GameServices.progression().daily_reset_seconds() == 0 and Time.get_ticks_msec() >= _refresh_at and not GameServices.progression().loading and not _busy:
		_refresh_at = Time.get_ticks_msec()+30000
		GameServices.progression().refresh.call_deferred()
