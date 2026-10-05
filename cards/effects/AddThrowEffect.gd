class_name AddThrowEffect
extends CardEffect

## Puts a free throw of `value` into this turn's pool (spent like any other throw).

@export_range(1, 8) var value: int = 1

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.add_throw(ctx.player, value)]
