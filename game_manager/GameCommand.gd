class_name GameCommand
extends RefCounted

## A request to change game state, applied by GameManager.apply_command().
## Plain data so it can be logged, tested, replayed or (later) sent over a network.
## Anything may issue commands: cards today, a debug console or network peer later.

enum Kind {
	MOVE_PAWN,          ## pawn, value = steps, obey_rules
	SEND_HOME,          ## pawn back to its homebase (not a capture)
	SWAP_PAWNS,         ## pawn <-> other_pawn
	FORCE_THROW,        ## the next throw lands on `value`
	ADD_THROW,          ## `value` joins the current throw pool
	GRANT_EXTRA_THROW,  ## one more throw once the pool is spent
	UNLOCK_INNER,       ## `player` may enter the inner ring
}

var kind: Kind
## Player issuing the command (or affected by it, for UNLOCK_INNER).
var player: int = -1
var pawn: Pawn
var other_pawn: Pawn
var value: int = 0
## false = a move may ignore the inner-ring lock and own-stacking rules.
var obey_rules: bool = true

static func move_pawn(by_player: int, target: Pawn, steps: int, obey: bool = true) -> GameCommand:
	var c := _make(Kind.MOVE_PAWN, by_player)
	c.pawn = target
	c.value = steps
	c.obey_rules = obey
	return c

static func send_home(by_player: int, target: Pawn) -> GameCommand:
	var c := _make(Kind.SEND_HOME, by_player)
	c.pawn = target
	return c

static func swap_pawns(by_player: int, a: Pawn, b: Pawn) -> GameCommand:
	var c := _make(Kind.SWAP_PAWNS, by_player)
	c.pawn = a
	c.other_pawn = b
	return c

static func force_throw(by_player: int, throw_value: int) -> GameCommand:
	var c := _make(Kind.FORCE_THROW, by_player)
	c.value = throw_value
	return c

static func add_throw(by_player: int, throw_value: int) -> GameCommand:
	var c := _make(Kind.ADD_THROW, by_player)
	c.value = throw_value
	return c

static func grant_extra_throw(by_player: int) -> GameCommand:
	return _make(Kind.GRANT_EXTRA_THROW, by_player)

static func unlock_inner(for_player: int) -> GameCommand:
	return _make(Kind.UNLOCK_INNER, for_player)

static func _make(command_kind: Kind, by_player: int) -> GameCommand:
	var c := GameCommand.new()
	c.kind = command_kind
	c.player = by_player
	return c

func _to_string() -> String:
	return "GameCommand(%s, player=%d, value=%d)" % [Kind.keys()[kind], player, value]
