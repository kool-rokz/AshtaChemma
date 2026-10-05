class_name ForceThrowEffect
extends CardEffect

## The card player's next throw lands on `value` (4 and 8 still chain a bonus throw).

@export_enum("1:1", "2:2", "3:3", "4:4", "8:8") var value: int = 4

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.force_throw(ctx.player, value)]
