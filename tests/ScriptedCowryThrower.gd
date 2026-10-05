class_name ScriptedCowryThrower
extends CowryThrower

## Test double: returns a fixed sequence of throw values (1, 2, 3, 4 or 8).

var values: Array[int] = []

func _init(sequence: Array[int] = []) -> void:
	values = sequence

func throw() -> Array[bool]:
	var value: int = values.pop_front() if not values.is_empty() else 2
	return CowryThrower.shells_for(value)
