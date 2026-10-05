class_name ModifierHooks
extends RuleHooks

## The card system's answer to rule queries: folds every active modifier for the
## asked hook over the base value, in the order they were played.

var _manager: CardManager

func _init(manager: CardManager) -> void:
	_manager = manager

func modify(hook: StringName, value: Variant, ctx: Dictionary = {}) -> Variant:
	for active in _manager.active_modifiers:
		if active.data.hook == hook and active.matches(ctx):
			value = active.data.apply(value, ctx, active)
	return value
