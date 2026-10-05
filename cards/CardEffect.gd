class_name CardEffect
extends Resource

## One step of what a card does. Subclasses add @export parameters (tuned in the
## Inspector) and override:
##   can_apply(ctx)      - false makes the card (or a target choice) unplayable.
##                         Also called with partial targets while the player is picking:
##                         skip checks for targets not picked yet (ctx.has_target).
##   build_commands(ctx) - the GameCommands to send; the default resolve() applies them in order.
##   resolve(ctx)        - override instead for effects that aren't commands (e.g. modifiers).

func can_apply(_ctx: CardContext) -> bool:
	return true

func build_commands(_ctx: CardContext) -> Array[GameCommand]:
	return []

func resolve(ctx: CardContext) -> void:
	for command in build_commands(ctx):
		await ctx.game.apply_command(command)
		if ctx.game.is_game_finished():
			return
