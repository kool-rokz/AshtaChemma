class_name GrantExtraThrowEffect
extends CardEffect

## One more throw once this turn's throws are used up (like a capture earns).

func build_commands(ctx: CardContext) -> Array[GameCommand]:
	return [GameCommand.grant_extra_throw(ctx.player)]
