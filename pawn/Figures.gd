class_name Figures
extends RefCounted

## The pawn figures players can pick: every FigureData in FOLDER, in `order`. Loaded
## once and kept. Ids are what the menu saves and the network sends.

const FOLDER := "res://pawn/figures"

static var _all: Array[FigureData] = []

## Every figure, in default assignment order.
static func all() -> Array[FigureData]:
	if _all.is_empty():
		for res in ResourceFolder.load_all(FOLDER, func(r): return r is FigureData, "Figures"):
			_all.append(res)
		_all.sort_custom(func(a: FigureData, b: FigureData): return a.order < b.order)
	return _all

static func ids() -> Array[String]:
	var result: Array[String] = []
	for data in all():
		result.append(String(data.id))
	return result

static func find(id: String) -> FigureData:
	for data in all():
		if data.id == StringName(id):
			return data
	return null

static func has(id: String) -> bool:
	return find(id) != null

## A known figure id (the first figure for anything unknown).
static func or_default(id: String) -> String:
	return id if has(id) else String(all()[0].id)

static func display_name(id: String) -> String:
	var data := find(id)
	return data.display_name if data else ""
