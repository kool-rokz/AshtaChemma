extends SceneTree

## Verifies the rotated seat paths used for 3-4 players.
## Run: godot --headless --path . -s res://tests/BoardPathTest.gd

var failures := 0

func _init() -> void:
	var data: BoardData = load("res://board/data/board_layout_standard.tres")

	_check(data.get_seat_path(0) == data.p1_path, "seat 0 must equal p1_path")
	_check(data.get_seat_path(2) == data.p2_path, "seat 2 (rotation) must equal hand-authored p2_path")

	var entries := []
	for seat in 4:
		var path := data.get_seat_path(seat)
		entries.append(path[0])
		_check(path.size() == 25, "seat %d path length %d" % [seat, path.size()])
		_check(_unique(path) == 25, "seat %d path must visit all 25 tiles once" % seat)
		_check(path.back() == data.home_index, "seat %d path must end at home" % seat)
		_check(path[0] in data.safe_squares, "seat %d must enter on a safe square" % seat)
		for i in range(1, path.size()):
			_check(_adjacent(path[i - 1], path[i]), "seat %d step %d→%d not adjacent" % [seat, path[i - 1], path[i]])
		print("seat %d: entry %d, outer ring %s" % [seat, path[0], path.slice(0, 16)])
	_check(_unique(entries) == 4, "each seat needs its own entry square")

	if failures == 0:
		print("✅ BOARD PATH TESTS PASSED")
		quit(0)
	else:
		print("❌ BOARD PATH TESTS FAILED: %d check(s)" % failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

func _unique(values: Array) -> int:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen.size()

func _adjacent(a: int, b: int) -> bool:
	return absi(a % 5 - b % 5) + absi(a / 5 - b / 5) == 1
