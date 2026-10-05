class_name CardTarget
extends Resource

## Something the player must pick when playing a card. Effects read the pick
## through CardContext.target(index), where index is this entry's position in CardData.targets.

enum Kind {
	OWN_PAWN,       ## one of the card player's pawns
	ENEMY_PAWN,     ## a pawn of another player
	ANY_PAWN,
	TILE,           ## a board square (value is the tile index)
	NEXT_OPPONENT,  ## picked automatically: the next player in turn order (value is a player id)
}

@export var kind: Kind = Kind.OWN_PAWN
## Shown while picking, e.g. "Pick one of your pawns".
@export var prompt: String = ""

@export_group("Filters")
## Skip pawns already home, and the home square itself.
@export var exclude_finished: bool = true
## Skip pawns sitting on their own homebase, and every player's homebase square.
@export var exclude_homebase: bool = false
## Skip anything on a safe square.
@export var exclude_safe: bool = false
@export var outer_ring_only: bool = false
## TILE only: skip squares with pawns on them.
@export var empty_tiles_only: bool = false

func is_pawn() -> bool:
	return kind in [Kind.OWN_PAWN, Kind.ENEMY_PAWN, Kind.ANY_PAWN]

func get_prompt() -> String:
	if prompt != "":
		return prompt
	match kind:
		Kind.OWN_PAWN: return "Pick one of your pawns"
		Kind.ENEMY_PAWN: return "Pick an opponent's pawn"
		Kind.ANY_PAWN: return "Pick a pawn"
		Kind.TILE: return "Pick a square"
	return ""
