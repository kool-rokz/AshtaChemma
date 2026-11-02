extends SceneTree

## GameManager.get_near_misses: an opponent's pawn one step short of or past the mover
## (along the mover's own path), on a square where it could have been captured.
## Run: godot --headless --path . -s res://tests/NearMissTest.gd

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
	var gm: GameManager = main.get_node("GameManager")
	var board := gm.board
	var mover: Pawn = gm.pawn_containers[0].get_child(0)
	var other: Pawn = gm.pawn_containers[1].get_child(0)
	var path := gm.board.board_data.get_seat_path(gm.player_seats[0])
	# three plain (not safe) squares in a row on the outer ring
	var k := -1
	for i in range(1, GameManager.OUTER_RING_STEPS - 2):
		if not (board.is_safe(path[i]) or board.is_safe(path[i + 1]) or board.is_safe(path[i + 2])):
			k = i
			break
	_check(k >= 0, "the outer ring has three plain squares in a row")
	gm.player_has_killed[0] = true

	mover.current_tile_index = path[k + 1]
	other.current_tile_index = path[k + 2]
	_check(gm.get_near_misses(mover) == ([other] as Array[Pawn]), "one step short of an opponent is a near miss")
	other.current_tile_index = path[k]
	_check(gm.get_near_misses(mover) == ([other] as Array[Pawn]), "one step past an opponent is a near miss")
	other.current_tile_index = gm.get_homebase_tile(1)
	_check(gm.get_near_misses(mover).is_empty(), "a pawn far away is no near miss")
	# a safe square next to the mover: it couldn't have been captured there
	var s := -1
	for i in range(1, GameManager.OUTER_RING_STEPS - 1):
		if board.is_safe(path[i + 1]) and not board.is_safe(path[i]):
			s = i
			break
	if s >= 0:
		mover.current_tile_index = path[s]
		other.current_tile_index = path[s + 1]
		_check(gm.get_near_misses(mover).is_empty(), "an opponent on a safe square is no near miss")
	# own pawns never count
	var mate: Pawn = gm.pawn_containers[0].get_child(1)
	mover.current_tile_index = path[k + 1]
	other.current_tile_index = gm.get_homebase_tile(1)
	mate.current_tile_index = path[k + 2]
	_check(gm.get_near_misses(mover).is_empty(), "a teammate next to the mover is no near miss")

	main.queue_free()
	await process_frame
	if failures == 0:
		print("✅ NEAR MISS TESTS PASSED")
		quit(0)
	else:
		print("❌ NEAR MISS TESTS FAILED: %d check(s)" % failures)
		quit(1)
