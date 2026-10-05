class_name CowryThrower
extends RefCounted

## Source of cowry shell outcomes. Subclasses decide HOW the shells land
## (RNG today, physics bodies later); scoring is shared and lives here.

const SHELL_COUNT := 4

## Moves awarded when every shell lands open side down ("ashta").
const ASHTA_MOVE := 8

## Chance a single shell lands open side up. GameManager sets it before each throw
## (rule hooks can change it); throwers that don't roll randomly may ignore it.
var open_up_probability: float = 0.5

## Returns one entry per shell: true = landed open side up.
func throw() -> Array[bool]:
	push_error("CowryThrower.throw() must be overridden")
	return []

## Maps a throw to movement points: k open-up shells move k,
## except zero open-up (all down, "ashta") which moves 8.
## All four up ("chamma") naturally scores 4.
static func score(shells: Array[bool]) -> int:
	var open_up := shells.count(true)
	return ASHTA_MOVE if open_up == 0 else open_up

## Shells that score `value` (the inverse of score()), for forced or modified throws.
static func shells_for(value: int) -> Array[bool]:
	var open_up := 0 if value == ASHTA_MOVE else clampi(value, 0, SHELL_COUNT)
	var shells: Array[bool] = []
	for i in SHELL_COUNT:
		shells.append(i < open_up)
	return shells
