class_name ScriptedCowryThrower
extends CowryThrower

## Test double: returns a fixed sequence of throw values (1, 2, 3, 4 or 8).

var values: Array[int] = []

func _init(sequence: Array[int] = []) -> void:
	values = sequence

func throw() -> Array[bool]:
	var value: int = values.pop_front() if not values.is_empty() else 2
	var open_up := 0 if value == ASHTA_MOVE else value
	var shells: Array[bool] = []
	for i in SHELL_COUNT:
		shells.append(i < open_up)
	return shells
