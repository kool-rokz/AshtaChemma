class_name GameConfig
extends RefCounted

## Match setup handed from the start screen to MainGame.
## Static so it survives change_scene_to_file() without an autoload.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const PAWNS_PER_PLAYER := 4

## Pawn colour choices, in default assignment order.
const COLORS: Dictionary = {
	"Red": Color(0.91, 0.30, 0.24),
	"Blue": Color(0.29, 0.51, 0.95),
	"Yellow": Color(0.98, 0.80, 0.18),
	"Green": Color(0.30, 0.78, 0.36),
}

## Board sides a player can sit at; pawns enter on that side's safe square.
## 0 = bottom, 1 = right, 2 = top, 3 = left (counter-clockwise, matching movement).
const SEATS_BY_PLAYER_COUNT: Dictionary = {
	2: [0, 2],
	3: [0, 1, 2],
	4: [0, 1, 2, 3],
}

## One entry per player: {"name": String, "color_name": String}. Empty = use defaults.
static var players: Array[Dictionary] = []

## Experimental card layer (cards/CardManager). false = the plain game, exactly as before.
static var cards_enabled: bool = false

static func get_players() -> Array[Dictionary]:
	if players.size() >= MIN_PLAYERS:
		return players
	return default_players(MIN_PLAYERS)

static func default_players(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names := COLORS.keys()
	for i in count:
		result.append({"name": "Player %d" % (i + 1), "color_name": names[i]})
	return result

static func color_of(player: Dictionary) -> Color:
	return COLORS.get(player.get("color_name", "Red"), Color.WHITE)

static func seats_for(count: int) -> Array:
	return SEATS_BY_PLAYER_COUNT[clampi(count, MIN_PLAYERS, MAX_PLAYERS)]
