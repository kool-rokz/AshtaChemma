class_name UnlockInnerRingEffect
extends CardEffect

## Opens the card player's inner ring without a capture.

func can_apply(ctx: CardContext) -> bool:
	return not ctx.game.is_unlocked(ctx.player)

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.unlock_inner(ctx.player)]
