class_name LegalPolicies
extends RefCounted
## Shared versioned copy is also imported by the companion website.
const PATH: String = "res://assets/legal/policies.json"

static func data() -> Dictionary:
	return StrictData.dictionary(JSON.parse_string(FileAccess.get_file_as_string(PATH)))

static func version() -> String:
	return str(data().get("version", ""))

static func document(kind: String) -> Dictionary:
	return StrictData.dictionary(data().get(kind, {}))

static func bbcode(kind: String) -> String:
	var policy: Dictionary = data()
	var doc: Dictionary = document(kind)
	var result: String = "[color=#b7b9d5]Updated " + str(policy.get("updated", "")) + " · Version " + version() + "[/color]\n\n"
	for section: Dictionary in StrictData.array(doc.get("sections", [])):
		result += "[b][color=#d8ceff]" + str(section.title) + "[/color][/b]\n" + str(section.body) + "\n\n"
	return result
