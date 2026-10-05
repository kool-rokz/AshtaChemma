class_name ActiveModifier
extends RefCounted

## A CardModifier in play: who played it, what it targets, how long it has left.
## Created, ticked and removed by CardManager.

var data: CardModifier
var card: CardData
var owner: int = -1
var target_player: int = -1
var target_pawn: Pawn
var target_tile: int = -1
## Owner turn-starts remaining before it ends.
var turns_left: int = 1

func matches(ctx: Dictionary) -> bool:
	match data.scope:
		CardModifier.Scope.EVERYONE:
			return true
		CardModifier.Scope.CARD_OWNER:
			return ctx.get("player", -1) == owner
		CardModifier.Scope.OPPONENTS:
			var p: int = ctx.get("player", -1)
			return p >= 0 and p != owner
		CardModifier.Scope.TARGET_PLAYER:
			return target_player >= 0 and ctx.get("player", -1) == target_player
		CardModifier.Scope.TARGET_PAWN:
			return target_pawn != null and ctx.get("pawn") == target_pawn
		CardModifier.Scope.TARGET_TILE:
			return target_tile >= 0 and ctx.get("tile", -1) == target_tile
	return false
