extends Node

## Deterministic scenarios for the throw pool, exhaustion, forfeits and finishing.
## Run: godot --headless --path . --time-scale 20 res://tests/RulesTest.tscn

const GAME_SCENE_PATH = "res://MainGame.tscn"

var failures := 0
var gm: GameManager
var _events: Array[String] = []

func _ready() -> void:
	await _scenario_last_pawn_exhausts_4_4_3()
	await _scenario_last_pawn_finishes_with_4_4_1()
	await _scenario_triple_bonus_forfeits()
	await _scenario_pool_split_across_pawns()
	await _scenario_capture_extra_throw_after_pool()
	await _scenario_start_on_homebase()

	if failures == 0:
		print("✅ RULES TESTS PASSED")
		get_tree().quit(0)
	else:
		print("❌ RULES TESTS FAILED: %d check(s)" % failures)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

# --- harness ---
func _new_game(throws: Array[int]) -> void:
	if gm:
		gm.get_parent().queue_free()
		await get_tree().process_frame
	GameConfig.players = GameConfig.default_players(2)
	var main: Node = load(GAME_SCENE_PATH).instantiate()
	gm = main.get_node("GameManager")
	gm.cowry_thrower = ScriptedCowryThrower.new(throws)
	add_child(main)
	_events.clear()
	gm.throws_exhausted.connect(func(p, v): _events.append("exhausted %s" % str(v)))
	gm.turn_forfeited.connect(func(p, v): _events.append("forfeited %s" % str(v)))
	gm.game_over.connect(func(p): _events.append("game_over %d" % p))
	gm.bonus_turn.connect(func(p, r): _events.append("bonus %s" % r))
	gm.turn_changed.connect(func(p): _events.append("turn %d" % p))
	await get_tree().process_frame
	await get_tree().process_frame

func _pawns(player: int) -> Array:
	return gm.pawn_containers[player].get_children()

## Puts `player`'s pawns at the given path steps (tile placement + layout).
func _place(player: int, steps: Array) -> void:
	var path: Array[int] = gm.board.board_data.get_seat_path(gm.player_seats[player])
	var pawns := _pawns(player)
	for i in steps.size():
		pawns[i].current_tile_index = path[steps[i]]
	for t in path:
		gm._layout_tile(t)

func _roll() -> void:
	gm.request_roll_dice()
	await get_tree().process_frame

func _wait_state(state: GameManager.GameState, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000 / Engine.time_scale)
	while gm.current_state != state and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	return gm.current_state == state

# --- scenarios ---
func _scenario_last_pawn_exhausts_4_4_3() -> void:
	print("scenario: last pawn needs 1, throws 4,4,3")
	await _new_game([4, 4, 3])
	gm.player_has_killed[0] = true
	_place(0, [24, 24, 24, 23])
	await _roll(); await _roll(); await _roll()
	_check("exhausted [4, 4, 3]" in _events, "4,4,3 should be exhausted together, got %s" % str(_events))
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check(gm.current_player_index == 1, "turn should pass to player 2")
	_check(not _events.any(func(e): return e.begins_with("game_over")), "game must not end")

func _scenario_last_pawn_finishes_with_4_4_1() -> void:
	print("scenario: last pawn needs 1, throws 4,4,1 (traditional: finish with the 1)")
	await _new_game([4, 4, 1])
	gm.player_has_killed[0] = true
	_place(0, [24, 24, 24, 23])
	await _roll(); await _roll(); await _roll()
	_check(gm.current_state == GameManager.GameState.SELECTING_PIECE, "should be choosing a move")
	_check(gm.throw_pool == [4, 4, 1] and gm.current_roll == 1, "the 1 should be auto-selected (only usable throw), pool %s" % str(gm.throw_pool))
	gm.request_select_pawn(_pawns(0)[3])
	await get_tree().create_timer(1.0).timeout
	_check("game_over 0" in _events, "player 1 should win, got %s" % str(_events))

func _scenario_triple_bonus_forfeits() -> void:
	print("scenario: 4, 8, 4 in a row forfeits")
	await _new_game([4, 8, 4])
	await _roll(); await _roll()
	_check(gm.current_state == GameManager.GameState.WAITING_FOR_ROLL and gm.throw_pool == [4, 8], "4 and 8 should chain, pool %s" % str(gm.throw_pool))
	await _roll()
	_check("forfeited [4, 8, 4]" in _events, "third bonus throw should forfeit, got %s" % str(_events))
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check(gm.current_player_index == 1, "turn should pass after forfeit")

func _scenario_pool_split_across_pawns() -> void:
	print("scenario: 4,3 split across two pawns")
	await _new_game([4, 3])
	await _roll(); await _roll()
	_check(gm.throw_pool == [4, 3], "pool should hold 4 and 3, got %s" % str(gm.throw_pool))
	var path: Array[int] = gm.board.board_data.get_seat_path(0)
	gm.request_select_pawn(_pawns(0)[0]) # uses the selected throw (4)
	await _wait_state(GameManager.GameState.SELECTING_PIECE)
	_check(gm.throw_pool == [3], "4 should be spent, pool %s" % str(gm.throw_pool))
	gm.request_select_pawn(_pawns(0)[1])
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check(_pawns(0)[0].current_tile_index == path[4] and _pawns(0)[1].current_tile_index == path[3], "pawns should be at steps 4 and 3")
	_check(gm.current_player_index == 1, "turn passes once the pool is spent")

func _scenario_capture_extra_throw_after_pool() -> void:
	print("scenario: capture earns an extra throw after the pool is spent")
	await _new_game([2, 1, 3])
	var path0: Array[int] = gm.board.board_data.get_seat_path(0)
	# Put a player-2 pawn on player 1's step 2 (a normal square)
	_pawns(1)[0].current_tile_index = path0[2]
	gm._layout_tile(path0[2])
	await _roll()
	gm.request_select_pawn(_pawns(0)[0]) # 2 → captures
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check(gm.current_player_index == 0 and "bonus captured a pawn" in _events, "capturer should throw again, got %s" % str(_events))
	_check(_pawns(1)[0].current_tile_index == gm.get_homebase_tile(1), "captured pawn returns to its homebase")
	_check(gm.player_has_killed[0], "capture unlocks the inner ring")

func _scenario_start_on_homebase() -> void:
	print("scenario: pawns start on their homebase")
	await _new_game([])
	for player in 2:
		for p in _pawns(player):
			_check(p.current_tile_index == gm.get_homebase_tile(player), "player %d pawn should start on homebase" % player)
