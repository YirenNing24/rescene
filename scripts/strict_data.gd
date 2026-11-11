class_name StrictData
extends RefCounted
## Explicit conversions at JSON, ConfigFile, Dictionary and signal boundaries.
## Known game objects use named script types instead of this adapter.

static func integer(value: Variant) -> int:
	if value is int:
		var result: int = value
		return result
	if value is float:
		var result: float = value
		return int(result)
	if value is bool:
		var result: bool = value
		return int(result)
	if value is String:
		var result: String = value
		return result.to_int()
	return 0

static func number(value: Variant) -> float:
	if value is float:
		var result: float = value
		return result
	if value is int:
		var result: int = value
		return float(result)
	if value is bool:
		var result: bool = value
		return float(result)
	if value is String:
		var result: String = value
		return result.to_float()
	return 0.0

static func dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = value
		return result
	return {}

static func array(value: Variant) -> Array:
	if value is Array:
		var result: Array = value
		return result
	return []

static func boolean(value: Variant) -> bool:
	if value is bool:
		var result: bool = value
		return result
	return false
