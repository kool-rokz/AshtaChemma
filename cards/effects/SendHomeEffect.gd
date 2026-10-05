class_name SendHomeEffect
extends CardEffect

## Sends the targeted pawn back to its homebase. Not a capture: it doesn't unlock
## the inner ring or earn an extra throw.

@export var target_index: int = 0

func can_apply(ctx: CardContext) -> bool:
	if not ctx.has_target(target_index):
		return true
	var pawn := ctx.pawn_target(target_index)
	return pawn != null and pawn.current_tile_index != ctx.game.get_homebase_tile(pawn.team_id)

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.send_home(ctx.player, ctx.pawn_target(target_index))]
