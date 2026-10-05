class_name CardContext
extends RefCounted

## Everything an effect may need while a card resolves. Effects should change the
## game only through commands (game.apply_command) or modifiers (card_manager.add_modifier);
## direct access is the escape hatch for experiments.

var game: GameManager
var card_manager: CardManager
var card: CardData
## Player who played the card.
var player: int = -1
## Picks so far, in CardData.targets order (Pawn, tile index or player id).
var targets: Array = []

func target(index: int) -> Variant:
	return targets[index] if has_target(index) else null

func pawn_target(index: int) -> Pawn:
	var t: Variant = target(index)
	return t if t is Pawn else null

## True once target `index` has been picked (effects can skip checks before that).
func has_target(index: int) -> bool:
	return index >= 0 and index < targets.size()
