class_name TeamColors
extends RefCounted

## The colours players can choose: every TeamColorData in FOLDER, in `order`. Loaded
## once and kept.

const FOLDER := "res://pawn/colors"

static var _all: Array[TeamColorData] = []

static func all() -> Array[TeamColorData]:
	if _all.is_empty():
		for res in ResourceFolder.load_all(FOLDER, func(r): return r is TeamColorData, "TeamColors"):
			_all.append(res)
		_all.sort_custom(func(a: TeamColorData, b: TeamColorData): return a.order < b.order)
	return _all

static func ids() -> Array[String]:
	var result: Array[String] = []
	for data in all():
		result.append(String(data.id))
	return result

static func has(id: String) -> bool:
	return _find(id) != null

## The colour with this id, or the first colour for anything unknown.
static func of(id: String) -> TeamColorData:
	var data := _find(id)
	return data if data else all()[0]

static func _find(id: String) -> TeamColorData:
	for data in all():
		if data.id == StringName(id):
			return data
	return null
