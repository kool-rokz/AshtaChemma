class_name SwapPawnsEffect
extends CardEffect

## Two targeted pawns trade squares. Keep both targets on the outer ring
## (CardTarget.outer_ring_only) so a locked pawn never lands inside the inner ring.
## A pawn the rules protect from swaps (the "can_be_swapped" hook, e.g. Aegis) can't be
## picked, on either side.

@export var first_index: int = 0
@export var second_index: int = 1

func can_apply(ctx: CardContext) -> bool:
	for index in [first_index, second_index]:
		if ctx.has_target(index) and not _swappable(ctx, ctx.pawn_target(index)):
			return false
	if not ctx.has_target(first_index) or not ctx.has_target(second_index):
		return true
	var a := ctx.pawn_target(first_index)
	var b := ctx.pawn_target(second_index)
	return a != null and b != null and a.current_tile_index != b.current_tile_index

static func _swappable(ctx: CardContext, pawn: Pawn) -> bool:
	return pawn != null and ctx.game.rules.modify(&"can_be_swapped", true,
		{"player": ctx.player, "pawn": pawn, "pawn_player": pawn.team_id})

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.swap_pawns(ctx.player, ctx.pawn_target(first_index), ctx.pawn_target(second_index))]
