class_name RuleHooks
extends RefCounted

## Rule queries GameManager (and Board) ask at the moment a rule is applied.
## This default answers with the unchanged value, so the base game plays as written.
## Another system (the card system) installs a subclass via GameManager.set_rules().
##
## Hooks and the ctx keys they pass:
##   &"open_up_probability" float  {player}                 before each shell throw
##   &"throw_value"         int    {player}                 after a throw is scored
##   &"move_steps"          int    {player, pawn}           every move length (throws and commands)
##   &"is_safe"             bool   {tile}                   safe-square checks (board.is_safe)
##   &"can_capture"         bool   {player (attacker), pawn (victim), victim_player, tile}
##   &"skip_turn"           bool   {player}                 when the turn passes to `player`
## Adding a hook = one rules.modify() call at the place the rule lives.

func modify(_hook: StringName, value: Variant, _ctx: Dictionary = {}) -> Variant:
	return value
