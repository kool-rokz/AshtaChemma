class_name MovePawnEffect
extends CardEffect

## Moves the targeted pawn without spending a throw. It moves like a thrown move:
## captures, the inner-ring lock and the exact-home rule all apply (unless obey_rules is off).

@export var target_index: int = 0
@export_range(1, 24) var steps: int = 2
## Off = ignore the inner-ring lock and the no-stacking-on-normal-squares rule.
@export var obey_rules: bool = true

func can_apply(ctx: CardContext) -> bool:
	if not ctx.has_target(target_index):
		return true
	var pawn := ctx.pawn_target(target_index)
	return pawn != null and ctx.game.can_move_pawn(pawn, steps, obey_rules)

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.move_pawn(ctx.player, ctx.pawn_target(target_index), steps, obey_rules)]
