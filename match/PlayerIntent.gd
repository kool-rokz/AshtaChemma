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

static func from_dict(d: Dictionary) -> PlayerIntent:
	var intent := make(Kind.get(d.get("kind", ""), -1), int(d.get("player", -1)))
	intent.index = int(d.get("index", -1))
	intent.pawn = Array(d.get("pawn", [])).map(func(v): return int(v))
	intent.card_id = StringName(d.get("card", ""))
	# Numbers may arrive as floats (JSON); ids are ints
	var raw_target: Dictionary = d.get("target", {})
	for key in raw_target:
		var value: Variant = raw_target[key]
		intent.target[key] = Array(value).map(func(v): return int(v)) if value is Array else int(value)
	intent.card_ids = Array(d.get("cards", [])).map(func(id): return StringName(id))
	return intent

func _to_string() -> String:
	return "PlayerIntent(%s)" % JSON.stringify(to_dict())
