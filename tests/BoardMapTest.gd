extends SceneTree

## The 3D board's view of the 2D model: every 2D square centre maps onto its 3D square
## (BoardView3D.map_point vs BoardWorld.square_position), and throw gestures from other
## players are clamped to the board-plane area (ThrowGesture.AREA).
## Run: godot --headless --path . -s res://tests/BoardMapTest.gd

var failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

func _run() -> void:
	var main: Node = load("res://MainGame.tscn").instantiate()
	MatchSetup.make(GameConfig.default_players(2)).apply_to(main)
	root.add_child(main)
	await process_frame
	var board: Board = main.get_node("Board")
	var worst := 0.0
	for i in board.board_data.square_coordinates.size():
		var mapped := BoardView3D.map_point(board, board.get_square_position(i))
		worst = maxf(worst, mapped.distance_to(BoardWorld.square_position(i)))
	_check(worst < 0.001, "2D squares land on their 3D squares (worst miss %.4f)" % worst)
	print("board map: worst miss %.5f units over %d squares" % [worst, board.board_data.square_coordinates.size()])

	var wild := ThrowGesture.from_dict({"quick": false, "origin": [99.0, -99.0], "direction": [3.0, 4.0], "power": 7.0})
	_check(wild.origin == Vector2(ThrowGesture.AREA.end.x, ThrowGesture.AREA.position.y), "a gesture's origin is clamped to the board area, got %s" % wild.origin)
	_check(is_equal_approx(wild.direction.length(), 1.0) and wild.power == 1.0, "direction normalised and power clamped")
	var junk := ThrowGesture.from_dict({"origin": "x", "faces": [1, 2]})
	_check(junk.quick and junk.origin == Vector2.ZERO, "malformed gestures fall back to a quick toss")

	main.queue_free()
	await process_frame
	if failures == 0:
		print("✅ BOARD MAP TESTS PASSED")
		quit(0)
	else:
		print("❌ BOARD MAP TESTS FAILED: %d check(s)" % failures)
		quit(1)
