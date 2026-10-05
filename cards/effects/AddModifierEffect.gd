class_name AddModifierEffect
extends CardEffect

## Starts a lasting rule change (see CardModifier). The modifier's TARGET_* scopes
## refer to the card target at `target_index` (-1 = no target).

@export var modifier: CardModifier
@export var target_index: int = -1

func resolve(ctx: CardContext) -> void:
	ctx.card_manager.add_modifier(modifier, ctx, target_index)
