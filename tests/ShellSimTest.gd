extends SceneTree

## The planned shell physics (shells/ShellSim.gd): the same throw always plays the same
## way, every combination of faces can be landed from a spread of throws, shells stay
## on the board, and planning is fast enough to hide inside the release animation.
## Run: godot --headless --path . -s res://tests/ShellSimTest.gd

## The board in stage units (ShellStage: 1 unit = 100 px; board at 470,207, 320 px wide).
const BOARD := Rect2(4.7, 2.07, 3.2, 3.2)
## Average planning time allowed per throw (desktop, headless; the web build is slower).
const BUDGET_MSEC := 60.0

var failures := 0

func _init() -> void:
	var sim := ShellSim.new(BOARD)
	_check_deterministic(sim)
	_check_every_target(sim)
	if failures == 0:
		print("✅ SHELL SIM TESTS PASSED")
		quit(0)
	else:
		print("❌ SHELL SIM TESTS FAILED: %d check(s)" % failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

func _start(origin: Vector3, direction: Vector3, power: float, faces: Array[bool], seed_value: int) -> Array:
	return ShellSim.release_state(ShellSim.hand_poses(origin, faces, seed_value), direction, power, seed_value)

func _check_deterministic(sim: ShellSim) -> void:
	var faces: Array[bool] = [true, false, true, false]
	var start := _start(Vector3(6.3, 0.9, 5.6), Vector3(0, 0, -1), 0.6, faces, 42)
	var a := sim.simulate(start)
	var b := sim.simulate(start)
	_check(a["frames"].size() == b["frames"].size() and a["frames"].back() == b["frames"].back(), "the same throw must play out identically")
	print("one throw: %d frames (%.2f s), faces %s" % [a["frames"].size(), a["frames"].size() / ShellSim.HZ, str(a["faces"])])

func _check_every_target(sim: ShellSim) -> void:
	var origins := [Vector3(6.3, 0.9, 5.6), Vector3(8.2, 0.9, 3.7), Vector3(6.3, 0.9, 1.8), Vector3(4.4, 0.9, 3.7)]
	var total_msec := 0.0
	var plans := 0
	var tries := 0
	var hops := 0
	var longest := 0.0
	var natural: Array = []
	for combo in 16:
		var targets: Array[bool] = []
		for i in 4:
			targets.append(combo & (1 << i) != 0)
		for k in 6:
			var origin: Vector3 = origins[k % origins.size()]
			var to_centre := Vector3(6.3, 0.0, 3.67) - origin
			var faces: Array[bool] = [k % 2 == 0, k % 3 == 0, true, false]
			var power: float = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0][k]
			var seed_value := combo * 100 + k
			var start := _start(origin, to_centre, power, faces, seed_value)
			var began := Time.get_ticks_usec()
			var result := sim.plan(start, targets, seed_value)
			total_msec += (Time.get_ticks_usec() - began) / 1000.0
			plans += 1
			tries += result["tries"]
			hops += result["hopped"].size()
			longest = maxf(longest, result["frames"].size() / ShellSim.HZ)
			var final: Array = result["frames"].back()
			var landed: Array[bool] = []
			for t in final:
				landed.append(ShellModel.is_open_up((t as Transform3D).basis))
			_check(landed == targets, "combo %s power %.1f landed %s" % [str(targets), power, str(landed)])
			for t in final:
				var p: Vector3 = (t as Transform3D).origin
				_check(BOARD.grow(0.01).has_point(Vector2(p.x, p.z)) and p.y < 0.2, "a shell came to rest off the board or in the air at %s" % str(p))
				_check(absf((t as Transform3D).basis.y.y) > 0.85, "a shell came to rest on its edge (up %.2f)" % (t as Transform3D).basis.y.y)
			if k == 2:
				natural.append(result["tries"])
	var average := total_msec / plans
	print("%d plans: avg %.1f ms, avg %.1f tries, %d hop fallbacks, longest throw %.2f s" % [plans, average, float(tries) / plans, hops, longest])
	_check(average < BUDGET_MSEC, "planning took %.1f ms on average (budget %.0f ms)" % [average, BUDGET_MSEC])
	_check(hops <= plans / 10, "too many hop fallbacks: %d of %d plans" % [hops, plans])
	_check(longest < 3.5, "a throw lasted %.2f s" % longest)
