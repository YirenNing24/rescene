class_name CoopView
extends MenuDestination
## A weekly duet is joined by invitation and credited from verified runs.
var _duets: Array = []
var _week: String = ""
var _index: int = 0
var _show_invites: bool = false
var _friends: Array = []
var _notice: String = ""
var _busy: bool = false
var _loading: bool = false

func _ready() -> void:
	name = "WeeklyDuet"; mouse_filter = Control.MOUSE_FILTER_STOP
	_render(); _load.call_deferred()

func _load() -> void:
	if _loading: return
	_loading = true
	var response: Dictionary = await GameServices.session().authorized_request("/api/v1/coop")
	var friends: Dictionary = await GameServices.session().authorized_request("/api/v1/social/players?kind=friends")
	if not is_inside_tree(): return
	_loading = false
	if StrictData.boolean(response.get("ok",false)):
		_duets = StrictData.array(StrictData.dictionary(response.data).get("duets",[]))
		_week = str(StrictData.dictionary(response.data).get("week",""))
		_index = clampi(_index,0,maxi(0,_duets.size()-1))
	else: _notice = str(response.get("message","Could not load your weekly duet."))
	if StrictData.boolean(friends.get("ok",false)): _friends = StrictData.array(StrictData.dictionary(friends.data).get("players",[]))
	_render()

func _render() -> void:
	if is_instance_valid(body): body.hide();body.queue_free()
	body = Control.new();body.mouse_filter = Control.MOUSE_FILTER_IGNORE;add_child(body)
	var w: float = host._width
	var _frame: Panel = host._panel(body,Rect2(30,155,w-60,885),Color("111325"),Color(host.LILAC,0.35),25)
	var _back: Button = host._button(body,"‹",Rect2(60,185,72,65),go_back)
	var _title: Label = host._label(body,"WEEKLY DUET",Rect2(160,185,1000,50),35,host.WHITE,host.BOLD)
	var _hint: Label = host._label(body,"TWO FRIENDS. ONE SHARED STAGE.  ·  RESETS MONDAY 00:00 UTC",Rect2(163,245,w-250,30),15,host.LILAC)
	var _info: Label = host._label(body,"One duet per week. Both friends contribute verified, unpaused clears; each claims their own rewards.",Rect2(74,300,w-150,36),19,host.MUTED)
	var has_current: bool = false
	for entry: Variant in _duets:
		if str(StrictData.dictionary(entry).get("week","")) == _week: has_current = true
	if not has_current and not _duets.is_empty():
		var _switch: Button = host._button(body,"VIEW REWARDS" if _show_invites else "INVITE FRIEND",Rect2(w-450,188,360,60),func() -> void: _show_invites = not _show_invites; _render())
	if _duets.is_empty() or _show_invites:
		var _empty: Label = host._label(body,"Invite a mutual friend to start this week's duet.",Rect2(75,380,w-150,45),25,host.WHITE,host.BOLD)
		for index: int in mini(6,_friends.size()):
			var friend: Dictionary = StrictData.dictionary(_friends[index])
			var y: float = 445.0+float(index)*72.0
			var _name: Label = host._label(body,str(friend.get("username","Friend")),Rect2(100,y+14,700,35),22,host.WHITE)
			var invite: Button = host._button(body,"INVITE",Rect2(w-450,y,300,55),func() -> void: await _post("/api/v1/coop/invite",{"player_id":str(friend.id)}),true)
			invite.disabled = _busy
		if _friends.is_empty():
			var _no_friends: Label = host._label(body,"Follow each other in Social to become friends.",Rect2(100,480,w-200,45),20,host.MUTED)
	else:
		if _duets.size()>1:
			var _prev: Button = host._button(body,"‹ WEEK",Rect2(w-660,188,220,60),func() -> void: _index = posmod(_index-1,_duets.size()); _render())
			var _next: Button = host._button(body,"WEEK ›",Rect2(w-430,188,220,60),func() -> void: _index = (_index+1)%_duets.size(); _render())
		var duet: Dictionary = StrictData.dictionary(_duets[_index]);var status: String = str(duet.get("status",""));var is_owner: bool = str(duet.get("owner","")) == str(GameServices.session().user.get("id",""))
		var partner: String = str(duet.get("peer_name","Friend")) if is_owner else str(duet.get("owner_name","Friend"))
		var _name: Label = host._label(body,"YOU  +  "+partner.to_upper(),Rect2(75,375,w-150,54),31,host.WHITE,host.BOLD)
		var _status: Label = host._label(body,"THIS WEEK  ·  "+status.to_upper()+"  ·  WEEK OF "+str(duet.week),Rect2(78,432,w-155,30),16,host.LILAC)
		if status == "pending":
			var pending: String = "Waiting for your friend to accept." if is_owner else "Your friend invited you to a weekly duet."
			var _pending: Label = host._label(body,pending,Rect2(78,500,w-160,45),22,host.MUTED)
			if not is_owner:
				var _accept: Button = host._button(body,"ACCEPT",Rect2(78,570,300,64),func() -> void: await _post("/api/v1/coop/"+str(duet.id)+"/action",{"action":"accept"}),true)
			var _decline: Button = host._button(body,"CANCEL" if is_owner else "DECLINE",Rect2(398,570,300,64),func() -> void: await _post("/api/v1/coop/"+str(duet.id)+"/action",{"action":"cancel" if is_owner else "decline"}))
		else:
			var _counts: Label = host._label(body,"%s: %d CLEARS   ·   %s: %d CLEARS" % [str(duet.owner_name),StrictData.integer(duet.owner_clears),str(duet.peer_name),StrictData.integer(duet.peer_clears)],Rect2(78,482,w-160,38),20,host.MUTED)
			var goals: Array = StrictData.array(duet.get("goals",[]))
			for index: int in goals.size():
				var goal: Dictionary = StrictData.dictionary(goals[index]);var y: float = 550.0+float(index)*165.0
				var _box: Panel = host._panel(body,Rect2(75,y,w-150,145),Color("24223d"),Color(host.LILAC,0.3),18)
				var _goal: Label = host._label(body,str(goal.name)+"   %d / %d" % [StrictData.integer(goal.progress),StrictData.integer(goal.target)],Rect2(100,y+15,w-700,35),23,host.WHITE,host.BOLD)
				var _desc: Label = host._label(body,str(goal.description),Rect2(100,y+60,w-700,30),16,host.MUTED)
				var _reward: Label = host._label(body,"+%d XP  ·  %d STARL" % [StrictData.integer(goal.xp),StrictData.integer(goal.starlight)],Rect2(w-550,y+15,350,25),15,host.LILAC)
				var complete: bool = StrictData.boolean(goal.get("complete",false));var claimed: bool = StrictData.boolean(goal.get("claimed",false))
				var claim: Button = host._button(body,"COLLECTED" if claimed else "CLAIM" if complete else "IN PROGRESS",Rect2(w-450,y+57,300,57),func() -> void: await _claim(str(duet.id),str(goal.id)),complete and not claimed)
				claim.disabled = _busy or claimed or not complete
	var _message: Label = host._label(body,_notice,Rect2(75,953,w-150,35),17,host.LILAC)

func _post(path: String, payload: Dictionary) -> void:
	if _busy: return
	_busy = true
	var response: Dictionary = await GameServices.session()._send(path,HTTPClient.METHOD_POST,payload)
	if not is_inside_tree(): return
	_busy = false
	if StrictData.boolean(response.get("ok",false)): _show_invites = false; _index = 0
	_notice = "Updated." if StrictData.boolean(response.get("ok",false)) else str(response.get("message","Please try again."))
	await _load()

func _claim(duet_id: String,goal: String) -> void:
	if _busy: return
	_busy = true
	var response: Dictionary = await GameServices.progression()._request("/api/v1/coop/"+duet_id.uri_encode()+"/claim",HTTPClient.METHOD_POST,{"goal":goal})
	if not is_inside_tree(): return
	_busy = false
	_notice = "Reward collected." if StrictData.boolean(response.get("ok",false)) else str(response.get("message","Please try again."))
	await _load()
