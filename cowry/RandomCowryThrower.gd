class_name RandomCowryThrower
extends CowryThrower

## Each shell independently lands open side up with probability `open_up_probability`,
## so the open-up count is Binomial(4, p). At p = 0.5:
##   1 → 25%, 2 → 37.5%, 3 → 25%, 4 (chamma) → 6.25%, 8 (ashta) → 6.25%

var rng := RandomNumberGenerator.new()

## seed_value = 0 picks a random seed; any other value makes throws reproducible.
func _init(p: float = 0.5, seed_value: int = 0) -> void:
	open_up_probability = clampf(p, 0.0, 1.0)
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

func throw() -> Array[bool]:
	var shells: Array[bool] = []
	for i in SHELL_COUNT:
		shells.append(rng.randf() < open_up_probability)
	return shells
