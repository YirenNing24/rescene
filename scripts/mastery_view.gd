class_name MasteryView
extends MenuDestination
## Milestones and claims are determined by the server, never the device record.
var song: Dictionary = {}
var _data: Dictionary = {}
var _notice: String = ""
var _busy: bool = false
var _loading: bool = false

func _ready() -> void:
	name = "SongMastery"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_render()
	_load.call_deferred()

func _load() -> void:
	if _loading: return
	_loading = true
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/mastery/"+str(song.id).uri_encode())
	if not is_inside_tree(): return
	_loading = false
	if StrictData.boolean(response.get("ok",false)): _data = StrictData.dictionary(StrictData.dictionary(response.data).get("mastery",{}))
	else: _notice = str(response.get("message","Could not load song mastery."))
	_render()

func _render() -> void:
	if is_instance_valid(body): body.hide(); body.queue_free()
	body = Control.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(body)
	var width: float = host._width
	var _frame: Panel = host._panel(body,Rect2(30,155,width-60,885),Color("111325"),Color(host.LILAC,0.35),25)
	var _back: Button = host._button(body,"‹",Rect2(60,185,72,65),go_back)
	var _title: Label = host._label(body,"SONG MASTERY",Rect2(160,184,1200,50),35,host.WHITE,host.BOLD)
	var _subtitle: Label = host._label(body,str(song.get("title",""))+"  /  YOUR NEXT MILESTONE",Rect2(163,245,1200,30),16,host.LILAC)
	var _hero: Panel = host._panel(body,Rect2(60,310,600,680),Color("24223d"),Color(host.LILAC,0.28),22)
	var cover: TextureRect = TextureRect.new(); cover.texture = load(str(song.get("cover_path",""))) as Texture2D
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._at(body,cover,Rect2(82,332,556,400))
	var _song: Label = host._label(body,str(song.get("title","")),Rect2(90,756,535,50),32,host.WHITE,host.BOLD)
	var count: String = "%d / 6 MILESTONES" % StrictData.integer(_data.get("completed",0))
	var _count: Label = host._label(body,count,Rect2(92,825,520,30),18,host.LILAC,host.BOLD)
	var _hint: Label = host._label(body,"Complete every milestone on a song\nto unlock the Song Specialist title.",Rect2(92,881,520,90),19,host.MUTED)
	var milestones: Array = StrictData.array(_data.get("milestones",[]))
	if milestones.is_empty():
		var _loading_label: Label = host._label(body,"Loading your mastery…" if _notice.is_empty() else _notice,Rect2(720,500,width-800,70),24,host.MUTED)
		return
	for index: int in milestones.size(): _row(StrictData.dictionary(milestones[index]),index)
	var msg: String = _notice if not _notice.is_empty() else "Verified clear results count. A paused run can still advance mastery."
	var _message: Label = host._label(body,msg,Rect2(720,960,width-800,35),17,host.LILAC)

func _row(m: Dictionary,index: int) -> void:
	var x: float = 720.0
	var w: float = host._width-800.0
	var y: float = 310.0+float(index)*106.0
	var complete: bool = StrictData.boolean(m.get("complete",false))
	var claimed: bool = StrictData.boolean(m.get("claimed",false))
	var _box: Panel = host._panel(body,Rect2(x,y,w,93),Color("211f36"),Color(host.LILAC,0.65 if complete and not claimed else 0.23),14)
	var _name: Label = host._label(body,str(m.name),Rect2(x+20,y+9,w-530,35),23,host.WHITE,host.BOLD)
	var _desc: Label = host._label(body,str(m.description),Rect2(x+22,y+49,w-540,30),16,host.MUTED)
	var reward: String = "+%d XP  ·  %d STARL" % [StrictData.integer(m.xp),StrictData.integer(m.starlight)]
	if StrictData.integer(m.get("shards",0))>0: reward += "  ·  1 SHARD PACK"
	var _rewards: Label = host._label(body,reward,Rect2(x+w-500,y+11,470,25),14,host.LILAC,host.FONT)
	var button: Button = host._button(body,"COLLECTED" if claimed else "CLAIM" if complete else "IN PROGRESS",Rect2(x+w-275,y+40,250,45),func() -> void: await _claim(str(m.id)),complete and not claimed)
	button.disabled = _busy or not complete or claimed
	button.name = "MasteryClaim_"+str(m.id)

func _claim(id: String) -> void:
	if _busy: return
	_busy = true; _notice = ""; _render()
	var response: Dictionary = await GameServices.progression().claim_mastery(str(song.id),id)
	if not is_inside_tree(): return
	_busy = false
	if StrictData.boolean(response.get("ok",false)):
		var reward: Dictionary = StrictData.dictionary(StrictData.dictionary(response.data).get("reward",{}))
		_notice = "Already collected." if StrictData.boolean(reward.get("already_claimed",false)) else "Reward collected!" + (" Prism Shards are arriving in Inventory." if StrictData.integer(reward.get("shards",0))>0 else "")
		await _load()
	else:
		_notice = str(response.get("message","Could not claim this reward.")); _render()
