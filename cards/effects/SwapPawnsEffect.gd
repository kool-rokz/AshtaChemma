class_name SwapPawnsEffect
extends CardEffect

## Two targeted pawns trade squares. Keep both targets on the outer ring
## (CardTarget.outer_ring_only) so a locked pawn never lands inside the inner ring.

@export var first_index: int = 0
@export var second_index: int = 1

func can_apply(ctx: CardContext) -> bool:
	if not ctx.has_target(first_index) or not ctx.has_target(second_index):
		return true
	var a := ctx.pawn_target(first_index)
	var b := ctx.pawn_target(second_index)
	return a != null and b != null and a.current_tile_index != b.current_tile_index

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.swap_pawns(ctx.player, ctx.pawn_target(first_index), ctx.pawn_target(second_index))]
