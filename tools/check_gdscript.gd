extends SceneTree
## Cold-process compiler gate; invoke through tools/check_gdscript.py.

func _initialize() -> void:
	var failed: bool = false
	var rules: int = 0
	if not ProjectSettings.get_setting("debug/gdscript/warnings/enable", true):
		push_error("GDScript warnings must be enabled.")
		failed = true
	var exclusions: Dictionary = ProjectSettings.get_setting("debug/gdscript/warnings/directory_rules", {})
	if not exclusions.is_empty():
		push_error("Strict checking must cover every script directory.")
		failed = true
	for setting: Dictionary in ProjectSettings.get_property_list():
		var key: String = setting.name
		if not key.begins_with("debug/gdscript/warnings/"): continue
		var value: Variant = ProjectSettings.get_setting(key)
		if typeof(value) != TYPE_INT: continue
		rules += 1
		if value != 2:
			push_error("GDScript warning must be an error: " + key)
			failed = true
	var paths: Array[String] = []
	for folder: String in ["res://scripts", "res://tests", "res://tools"]:
		_collect_scripts(folder, paths)
	for path: String in paths:
		var source: GDScript = load(path) as GDScript
		if source == null or not source.can_instantiate():
			push_error("GDScript did not compile: " + path)
			failed = true
	print("Strict GDScript: %d scripts, %d error-level rules: %s" % [paths.size(), rules, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

func _collect_scripts(folder: String, paths: Array[String]) -> void:
	for filename: String in DirAccess.get_files_at(folder):
		if filename.ends_with(".gd"): paths.append(folder + "/" + filename)
	for directory: String in DirAccess.get_directories_at(folder):
		_collect_scripts(folder + "/" + directory, paths)
