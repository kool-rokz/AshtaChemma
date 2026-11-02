class_name Emotes
extends RefCounted

## The emotes players can send (the HUD's emote wheel): every EmoteData in FOLDER, in
## `order`. Loaded once and kept. Add one by saving a new file there (plus its voice
## files). Cosmetic only: emotes never touch the game's state.

const FOLDER := "res://emotes/data"
## Seconds between one player's emotes (the host drops faster ones).
const COOLDOWN := 3.0

static var _all: Array[EmoteData] = []

static func all() -> Array[EmoteData]:
	if _all.is_empty():
		for res in ResourceFolder.load_all(FOLDER, func(r): return r is EmoteData, "Emotes"):
			_all.append(res)
		_all.sort_custom(func(a: EmoteData, b: EmoteData): return a.order < b.order)
	return _all

static func find(id: String) -> EmoteData:
	for emote in all():
		if emote.id == StringName(id):
			return emote
	return null

static func has(id: String) -> bool:
	return find(id) != null
