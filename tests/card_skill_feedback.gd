extends SceneTree

func _initialize() -> void:
	var battle: CardBoosts = CardBoosts.new()
	var messages: Array[String] = []
	var _connection: int = battle.skill_activated.connect(func(skill_name: String, _description: String) -> void: messages.append(skill_name))
	battle.setup({"version":2,"skills":[0,0,1,1,1,1,1],"perfect_score_bp":0,"recovery_ppm":0})
	for index: int in 30:
		var _earned: Vector2i = battle.hit(10,index+1,true,0,false,10.0,100.0,250000)
	if messages.count("Spotlight") != 1 or messages.count("Second Wind") != 1: push_error("Streak skill cues did not match actual activations.");quit(1);return
	var _hold: Vector2i = battle.hit(10,31,false,3,true,20.0,100.0,500000)
	if messages.count("Resonance") != 1: push_error("Perfect hold cue missing.");quit(1);return
	var _late: Vector2i = battle.hit(10,60,true,0,false,80.0,100.0,500000)
	if messages.count("Encore") != 1 or messages.count("Overdrive") != 1: push_error("Late-stage or momentum cue missing.");quit(1);return
	var _again: Vector2i = battle.hit(10,61,true,0,false,90.0,100.0,500000)
	if messages.count("Encore") != 1 or messages.count("Overdrive") != 1: push_error("Continuous skills announced repeatedly.");quit(1);return
	print("Card skill activation feedback: PASS");quit()
