class_name PlayerIntent
extends RefCounted

## Something a player wants to do, as plain data. UI never changes the game directly:
## it submits intents to MatchController, which checks them (on the host, online)
## and turns accepted ones into numbered events that every copy of the game applies.
## Pawns, targets and cards are referenced by stable ids, never node references,
## so intents survive the network (to_dict / from_dict).

enum Kind {
	THROW,          ## throw the shells
	SELECT_THROW,   ## index = which pooled throw to use next
	MOVE_PAWN,      ## pawn = [player, index]
	PLAY_CARD,      ## card_id from the player's hand
	CHOOSE_TARGET,  ## target = {"pawn": [p, i]} | {"tile": t} | {"player": p}
	CANCEL_CARD,
	DRAFT_PICKS,    ## card_ids kept from the player's draft offer
}

var kind: Kind
## Seat of the player acting.
var player: int = -1
var index: int = -1
var pawn: Array = []
var card_id: StringName = &""
var target: Dictionary = {}
var card_ids: Array = []

static func make(intent_kind: Kind, by_player: int) -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.kind = intent_kind
	intent.player = by_player
	return intent

static func throw_shells(by_player: int) -> PlayerIntent:
	return make(Kind.THROW, by_player)

static func select_throw(by_player: int, pool_index: int) -> PlayerIntent:
	var intent := make(Kind.SELECT_THROW, by_player)
	intent.index = pool_index
	return intent

static func move_pawn(by_player: int, pawn_ref: Array) -> PlayerIntent:
	var intent := make(Kind.MOVE_PAWN, by_player)
	intent.pawn = pawn_ref
	return intent

static func play_card(by_player: int, id: StringName) -> PlayerIntent:
	var intent := make(Kind.PLAY_CARD, by_player)
	intent.card_id = id
	return intent

static func choose_target(by_player: int, target_ref: Dictionary) -> PlayerIntent:
	var intent := make(Kind.CHOOSE_TARGET, by_player)
	intent.target = target_ref
	return intent

static func cancel_card(by_player: int) -> PlayerIntent:
	return make(Kind.CANCEL_CARD, by_player)

static func draft_picks(by_player: int, ids: Array) -> PlayerIntent:
	var intent := make(Kind.DRAFT_PICKS, by_player)
	intent.card_ids = ids
	return intent

func to_dict() -> Dictionary:
	var d := {"kind": Kind.keys()[kind], "player": player}
	if index >= 0: d["index"] = index
	if not pawn.is_empty(): d["pawn"] = pawn
	if card_id != &"": d["card"] = String(card_id)
	if not target.is_empty(): d["target"] = target
	if not card_ids.is_empty(): d["cards"] = card_ids.map(func(id): return String(id))
	return d

## Parses an intent from the network. Returns null for anything malformed (unknown
## kind, wrong types), so a buggy or outdated client can never smuggle in an action.
static func from_dict(d: Variant) -> PlayerIntent:
	if not d is Dictionary:
		return null
	var kind_name: Variant = d.get("kind")
	if not kind_name is String or not Kind.has(kind_name):
		return null
	var intent := make(Kind[kind_name], _as_int(d.get("player"), -1))
	intent.index = _as_int(d.get("index"), -1)
	var raw_pawn: Variant = d.get("pawn", [])
	if raw_pawn is Array and raw_pawn.size() == 2:
		intent.pawn = [_as_int(raw_pawn[0], -1), _as_int(raw_pawn[1], -1)]
	var raw_card: Variant = d.get("card", "")
	if raw_card is String:
		intent.card_id = StringName(raw_card)
	# Numbers may arrive as floats (JSON); ids are ints. Only known target keys survive.
	var raw_target: Variant = d.get("target", {})
	if raw_target is Dictionary:
		if raw_target.get("pawn") is Array and raw_target["pawn"].size() == 2:
			intent.target = {"pawn": [_as_int(raw_target["pawn"][0], -1), _as_int(raw_target["pawn"][1], -1)]}
		elif raw_target.has("tile"):
			intent.target = {"tile": _as_int(raw_target["tile"], -1)}
		elif raw_target.has("player"):
			intent.target = {"player": _as_int(raw_target["player"], -1)}
	var raw_cards: Variant = d.get("cards", [])
	if raw_cards is Array:
		intent.card_ids = raw_cards.filter(func(id): return id is String or id is StringName).map(func(id): return StringName(id))
	return intent

static func _as_int(value: Variant, fallback: int) -> int:
	return int(value) if value is int or value is float else fallback

func _to_string() -> String:
	return "PlayerIntent(%s)" % JSON.stringify(to_dict())
