class_name CardModifier
extends Resource

## A lasting rule change from a card. While active it answers one rule hook
## (see game_manager/RuleHooks.gd for the hooks and their ctx keys) for whatever its
## scope matches, e.g. hook "can_capture" + scope TARGET_PAWN + SET 0 = a shield.
## Duration counts the card owner's turns: it ends when the owner's Nth next turn starts.
## For logic SET/ADD/MULTIPLY can't express, subclass and override apply().

enum Scope {
	EVERYONE,
	CARD_OWNER,     ## ctx.player is the card's player
	OPPONENTS,      ## ctx.player is anyone else
	TARGET_PLAYER,  ## ctx.player is the targeted player (or the targeted pawn's owner)
	TARGET_PAWN,    ## ctx.pawn is the targeted pawn
	TARGET_TILE,    ## ctx.tile is the targeted square
}

enum Op { SET, ADD, MULTIPLY }

## Shown in the log and the players panel, e.g. "shielded".
@export var label: String = ""
@export var hook: StringName = &""
@export var scope: Scope = Scope.CARD_OWNER
@export var op: Op = Op.SET
## For true/false hooks, SET uses 0 = false and anything else = true.
@export var amount: float = 0.0
@export_range(1, 20) var duration_turns: int = 1
## Ring on a targeted pawn / tint on a targeted square while active (alpha 0 = none).
@export var marker_color: Color = Color(0, 0, 0, 0)

func apply(value: Variant, _ctx: Dictionary, _active: ActiveModifier) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return amount != 0.0 if op == Op.SET else value
		TYPE_INT:
			match op:
				Op.SET: return int(amount)
				Op.ADD: return value + int(amount)
				Op.MULTIPLY: return roundi(value * amount)
		TYPE_FLOAT:
			match op:
				Op.SET: return amount
				Op.ADD: return value + amount
				Op.MULTIPLY: return value * amount
	return value
