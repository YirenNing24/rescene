class_name EventsView
extends MenuDestination
## PULSE missions and eligibility are owned by the authenticated game API.

var _busy: bool = false
var _notice: String = ""
var _timer: Label
var _rotation: Label
var _clock: float = 0.0
var _refresh_at: int = 0
var _event: Dictionary = {}
var _event_index: int = 0

func _ready() -> void:
	name = "EventsView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var _changed: int = GameServices.progression().changed.connect(_render)
	_render()
	GameServices.progression().refresh.call_deferred()

func _render() -> void:
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var width: float = host._width
	var _background: Panel = host._panel(body, Rect2(30,155,width-60,885),Color("111325"),Color(0.72,0.68,0.95,0.35),26)
	var _back: Button = host._button(body,"‹",Rect2(60,185,72,65),host._close_dialog)
	var _title: Label = host._label(body,"EVENTS",Rect2(160,185,600,50),35,host.WHITE,host.BOLD)
	var _subtitle: Label = host._label(body,"A LIMITED-TIME ENCORE",Rect2(163,244,1000,24),13,host.LILAC)
	var refresh: Button = host._button(body,"REFRESH",Rect2(width-350,189,260,64),func() -> void: GameServices.progression().refresh.call_deferred())
	refresh.disabled = _busy or GameServices.progression().loading
	var entries: Array = StrictData.array(GameServices.progression().state.get("events",[]))
	if entries.is_empty():
		var _empty: Label = host._label(body,"Your event is loading. Refresh to reconnect.",Rect2(100,450,width-200,100),28,host.MUTED)
		return
	_event_index = clampi(_event_index,0,entries.size()-1)
	_event = StrictData.dictionary(entries[_event_index])
	_title.text = str(_event.get("name","EVENTS")).to_upper()
	if entries.size()>1:
		var previous: Button = host._button(body,"‹ EVENT",Rect2(width-910,189,245,64),func() -> void: _event_index = posmod(_event_index-1,entries.size()); _render())
		previous.name = "PreviousEvent"
		var next: Button = host._button(body,"EVENT ›",Rect2(width-650,189,245,64),func() -> void: _event_index = (_event_index+1)%entries.size(); _render())
		next.name = "NextEvent"
	_feature()
	var missions: Array = StrictData.array(_event.get("missions",[]))
	var right_x: float = 710.0
	var card_width: float = (width-right_x-110.0)/3.0
	for index: int in missions.size():
		var mission: Dictionary = StrictData.dictionary(missions[index])
		var rect: Rect2 = Rect2(right_x+(index%3)*(card_width+16),316+floori(float(index)/3.0)*250,card_width,234)
		if index == 6: rect = Rect2(right_x,820,width-right_x-78,124)
		_mission(mission,rect,index == 6)
	var message: String = _notice if not _notice.is_empty() else GameServices.progression().error_message
	if message.is_empty(): message = "Any difficulty · 50% accuracy to clear · Unpaused, verified attempts · 1 energy per attempt"
	var _footer: Label = _wrap(message,Rect2(right_x,966,width-right_x-90,52),17,host.LILAC)
	_tick()

func _wrap(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_font_override("font",host.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	host._at(body,label,rect)
	return label

func _feature() -> void:
	var _panel: Panel = host._panel(body,Rect2(60,316,606,685),Color("24223d"),Color(0.7,0.65,0.95,0.3),22)
	var image: TextureRect = TextureRect.new()
	for song: Dictionary in SongCatalog.SONGS:
		if str(song.id) == str(_event.featured_song_id):
			image.texture = load(str(song.cover_path)) as Texture2D
			break
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._at(body,image,Rect2(82,338,562,325))
	var _eyebrow: Label = host._label(body,"TODAY'S SPOTLIGHT",Rect2(92,687,520,28),14,host.LILAC,host.BOLD)
	var _song: Label = host._label(body,str(_event.featured_title),Rect2(90,727,520,58),44,host.WHITE,host.BOLD)
	_rotation = host._label(body,"",Rect2(93,791,520,30),18,host.MUTED)
	var play: Button = host._button(body,"EXPLORE FEATURED SONG  →",Rect2(90,843,545,65),func() -> void: host._open_event_song(str(_event.featured_song_id)),true)
	play.disabled = str(_event.status) != "active"
	_timer = host._label(body,"",Rect2(93,929,520,32),20,host.LILAC,host.BOLD)
	var _window: Label = host._label(body,"ENDS %s UTC  ·  CLAIM UNTIL %s UTC" % [str(_event.ends_at).substr(0,10),str(_event.claim_ends_at).substr(0,10)],Rect2(94,971,520,24),13,host.MUTED)

func _mission(mission: Dictionary, rect: Rect2, finale: bool) -> void:
	var claimed: bool = StrictData.boolean(mission.get("claimed",false))
	var claim_ready: bool = StrictData.boolean(mission.get("claimable",false))
	var target: int = StrictData.integer(mission.target)
	var progress: int = StrictData.integer(mission.progress)
	var _panel: Panel = host._panel(body,rect,Color("393150") if finale else Color("211f36"),Color(host.LILAC,0.65 if claim_ready else 0.23),18)
	var x: float = rect.position.x+22
	var y: float = rect.position.y+15
	var text_width: float = rect.size.x-44
	if finale: text_width = rect.size.x-450
	var _name: Label = _wrap(str(mission.name),Rect2(x,y,text_width,51),24,host.WHITE)
	var _description: Label = _wrap(str(mission.description),Rect2(x,y+56,text_width,49),17,host.MUTED)
	var bar_y: float = y+115
	if finale: bar_y = y+94
	host._line(body,Rect2(x,bar_y,text_width,5),Color("484159"))
	host._line(body,Rect2(x,bar_y,text_width*minf(1.0,float(progress)/float(maxi(1,target))),5),host.LILAC)
	if not finale:
		var _count: Label = host._label(body,"%d / %d" % [progress,target],Rect2(x,bar_y+10,120,26),14,host.MUTED)
	var reward: String = "+%d XP  ·  %d STARL" % [StrictData.integer(mission.xp),StrictData.integer(mission.starlight)]
	var shards: int = StrictData.integer(mission.get("shards",0))
	if shards > 0: reward += "  ·  %d Shard pack(s)" % shards
	var reward_x: float = rect.end.x-390 if finale else x
	var reward_y: float = y+12 if finale else y+155
	var _reward: Label = host._label(body,reward,Rect2(reward_x,reward_y,370,24),15,host.LILAC)
	var action: String = "COLLECTED" if claimed else "CLAIM REWARD" if claim_ready else "EVENT ENDED" if str(_event.status) == "ended" else "IN PROGRESS"
	var button: Button = host._button(body,action,Rect2(rect.end.x-390,y+51,370,49) if finale else Rect2(x,rect.end.y-47,text_width,34),func() -> void: await _claim(str(mission.id)),claim_ready)
	button.name = "EventClaim_"+str(mission.id)
	button.disabled = _busy or not claim_ready
	button.add_theme_font_size_override("font_size",15)

func _claim(mission_id: String) -> void:
	if _busy: return
	_busy = true
	_notice = ""
	_render()
	var response: Dictionary = await GameServices.progression().claim_event(str(_event.id),mission_id)
	if not is_inside_tree(): return
	_busy = false
	if StrictData.boolean(response.get("ok",false)):
		var reward: Dictionary = StrictData.dictionary(StrictData.dictionary(response.get("data")).get("reward"))
		_notice = "Already collected. Your reward is safe." if StrictData.boolean(reward.get("already_claimed",false)) else "REWARD COLLECTED  /  +%d XP  ·  +%d STARL" % [StrictData.integer(reward.get("xp",0)),StrictData.integer(reward.get("starlight",0))]
		if StrictData.integer(reward.get("shards",0)) > 0: _notice += "  ·  Prism Shards are arriving in Inventory."
	else:
		_notice = str(response.get("message","Please retry your reward claim."))
	_render()

func _tick() -> void:
	if not is_instance_valid(_timer): return
	var status: String = str(_event.get("status",""))
	var deadline: String = str(_event.starts_at) if status == "upcoming" else str(_event.claim_ends_at) if status == "claiming" else str(_event.ends_at)
	var seconds: int = GameServices.progression().event_seconds(deadline)
	_timer.text = "EVENT ENDED" if status == "ended" else "%s  %dd %02dh %02dm" % ["STARTS IN" if status == "upcoming" else "CLAIM WITHIN" if status == "claiming" else "ENDS IN",floori(seconds/86400.0),floori(float(seconds%86400)/3600.0),floori(float(seconds%3600)/60.0)]
	var rotation_seconds: int = GameServices.progression().event_seconds(str(_event.rotation_at))
	_rotation.text = "Spotlight rotates in %02dh %02dm" % [floori(rotation_seconds/3600.0),floori(float(rotation_seconds%3600)/60.0)] if status == "active" else "With you, in every beat."
	if status != "ended" and (seconds == 0 or (status == "active" and rotation_seconds == 0)) and Time.get_ticks_msec() >= _refresh_at:
		_refresh_at = Time.get_ticks_msec()+30000
		GameServices.progression().refresh.call_deferred()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0: return
	_clock = 0.0
	_tick()
