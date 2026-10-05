extends Node

## Card layer scenarios: every starter card, the per-turn window and limit,
## cancelling, modifier expiry, and a card move that wins the game.
## Run: godot --headless --path . --time-scale 20 res://tests/CardsTest.tscn

const GAME_SCENE_PATH = "res://MainGame.tscn"

var failures := 0
var gm: GameManager
var cm: CardManager
var _events: Array[String] = []

func _ready() -> void:
	await _scenario_sprint_captures()
	await _scenario_loaded_shells_chains()
	await _scenario_aegis_blocks_capture_then_expires()
	await _scenario_stall_skips_next_player()
	await _scenario_sanctuary_tile()
	await _scenario_banish_targets_normal_squares_only()
	await _scenario_switcheroo_two_targets()
	await _scenario_master_key_and_turn_limit()
	await _scenario_window_closes_after_throw()
	await _scenario_cancel_keeps_card()
	await _scenario_card_move_wins()
	await _scenario_lucky_charm_and_tailwind()
	await _scenario_cards_off_removes_system()

	if failures == 0:
		print("✅ CARD TESTS PASSED")
		get_tree().quit(0)
	else:
		print("❌ CARD TESTS FAILED: %d check(s)" % failures)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

# --- harness ---
func _new_game(throws: Array[int], hand_ids: Array = [], cards_on := true) -> void:
	if gm:
		gm.get_parent().queue_free()
		await get_tree().process_frame
	GameConfig.players = GameConfig.default_players(2)
	GameConfig.cards_enabled = cards_on
	var main: Node = load(GAME_SCENE_PATH).instantiate()
	gm = main.get_node("GameManager")
	gm.cowry_thrower = ScriptedCowryThrower.new(throws)
	cm = main.get_node("CardManager")
	cm.auto_draft = true
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_events.clear()
	gm.game_over.connect(func(p): _events.append("game_over %d" % p))
	gm.turn_skipped.connect(func(p): _events.append("skipped %d" % p))
	gm.turn_changed.connect(func(p): _events.append("turn %d" % p))
	if not cards_on:
		return
	cm.card_rejected.connect(func(_p, _c, reason): _events.append("rejected " + reason))
	var cards: Array = []
	for id in hand_ids:
		var card := cm.find_card(id)
		_check(card != null, "card %s should be in the library" % id)
		cards.append(card)
	cm.set_hand(0, cards)

func _pawns(player: int) -> Array:
	return gm.pawn_containers[player].get_children()

func _path(player: int) -> Array[int]:
	return gm.board.board_data.get_seat_path(gm.player_seats[player])

## Puts `player`'s first pawns at the given steps of their own path.
func _place(player: int, steps: Array) -> void:
	var path := _path(player)
	var pawns := _pawns(player)
	for i in steps.size():
		pawns[i].current_tile_index = path[steps[i]]
	for t in 25:
		gm._layout_tile(t)

## Puts a pawn on a specific tile.
func _put(pawn: Pawn, tile: int) -> void:
	pawn.current_tile_index = tile
	for t in 25:
		gm._layout_tile(t)

func _wait_state(state: GameManager.GameState, timeout := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000 / Engine.time_scale)
	while gm.current_state != state and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	return gm.current_state == state

func _play(hand_index: int, targets: Array = []) -> bool:
	if not cm.request_play(hand_index):
		return false
	for t in targets:
		if not cm.choose_target(t):
			print("  (target %s not offered; candidates %s)" % [str(t), str(cm.get_target_candidates())])
			cm.cancel_targeting()
			return false
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	return true

# --- scenarios ---
func _scenario_sprint_captures() -> void:
	print("scenario: Sprint moves 2 and its capture counts (unlock + extra throw)")
	await _new_game([], [&"sprint"])
	var victim: Pawn = _pawns(1)[0]
	_put(victim, _path(0)[2])
	var mover: Pawn = _pawns(0)[0]
	_check(await _play(0, [mover]), "Sprint should be playable on a homebase pawn")
	_check(mover.current_tile_index == _path(0)[2], "pawn should be 2 steps along")
	_check(victim.current_tile_index == gm.get_homebase_tile(1), "victim returns to its homebase")
	_check(gm.is_unlocked(0), "card capture unlocks the inner ring")
	_check(gm._extra_throw_pending, "card capture earns the extra throw after the pool")
	_check(gm.current_player_index == 0 and gm.current_state == GameManager.GameState.WAITING_FOR_ROLL, "still player 1's turn, waiting to throw")
	_check(cm.hands[0].is_empty() and cm.cards_played == 1, "card leaves the hand")

func _scenario_loaded_shells_chains() -> void:
	print("scenario: Loaded Shells forces a 4, which chains a bonus throw")
	await _new_game([2], [&"loaded_shells"])
	_check(await _play(0), "Loaded Shells should play")
	gm.request_roll_dice()
	await get_tree().process_frame
	_check(gm.throw_pool == [4] and gm.current_state == GameManager.GameState.WAITING_FOR_ROLL, "forced 4 should chain, pool %s" % str(gm.throw_pool))
	gm.request_roll_dice()
	await get_tree().process_frame
	_check(gm.throw_pool == [4, 2], "next throw comes from the shells again, pool %s" % str(gm.throw_pool))

func _scenario_aegis_blocks_capture_then_expires() -> void:
	print("scenario: Aegis shields a pawn for 2 of its owner's turns")
	await _new_game([], [&"aegis"])
	var shielded: Pawn = _pawns(0)[0]
	_place(0, [3])
	var attacker: Pawn = _pawns(1)[0]
	var attack_step := _path(1).find(shielded.current_tile_index)
	_put(attacker, _path(1)[attack_step - 1])
	gm.player_has_killed[1] = true
	_check(gm.can_move_pawn(attacker, 1), "sanity: attacker can capture before Aegis")
	_check(await _play(0, [shielded]), "Aegis should play")
	_check(not gm.can_move_pawn(attacker, 1), "shielded pawn can't be captured (square blocked)")
	_check(shielded.status_color.a > 0.0, "shielded pawn shows a ring")
	gm.turn_changed.emit(0) # owner's next turn: 1 left
	_check(not gm.can_move_pawn(attacker, 1), "still shielded after one owner turn")
	gm.turn_changed.emit(0) # owner's second turn: expires
	_check(gm.can_move_pawn(attacker, 1), "shield expires after 2 owner turns")
	_check(cm.active_modifiers.is_empty() and shielded.status_color.a == 0.0, "modifier and ring removed")

func _scenario_stall_skips_next_player() -> void:
	print("scenario: Stall skips the next player, then wears off")
	await _new_game([2], [&"stall"])
	_check(await _play(0), "Stall should play (target picked automatically)")
	gm.request_roll_dice()
	await get_tree().process_frame
	gm.request_select_pawn(_pawns(0)[0])
	await get_tree().create_timer(0.3).timeout # move + pass delay (time-scaled)
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check("skipped 1" in _events, "player 2 should be skipped, got %s" % str(_events))
	_check(gm.current_player_index == 0, "player 1 throws again")
	_check(cm.active_modifiers.is_empty(), "Stall wears off at its owner's next turn")

func _scenario_sanctuary_tile() -> void:
	print("scenario: Sanctuary makes a normal square safe for 1 round")
	await _new_game([], [&"sanctuary"])
	var tile := _path(0)[3]
	_check(not gm.board.is_safe(tile), "sanity: normal square")
	_check(await _play(0, [tile]), "Sanctuary should play on a normal square")
	_check(gm.board.is_safe(tile), "square is safe while active")
	_check(gm.board.highlighter._marked_tiles.has(tile), "square is tinted")
	gm.turn_changed.emit(0)
	_check(not gm.board.is_safe(tile), "safe status expires")

func _scenario_banish_targets_normal_squares_only() -> void:
	print("scenario: Banish only offers pawns on normal squares; not a kill")
	await _new_game([], [&"banish"])
	_check(cm.get_block_reason(0, 0) != "", "no enemy on a normal square -> unplayable")
	var exposed: Pawn = _pawns(1)[0]
	var safe: Pawn = _pawns(1)[1]
	_put(exposed, _path(0)[3])
	_put(safe, _path(0)[4])
	_check(cm.request_play(0), "Banish playable now")
	var candidates := cm.get_target_candidates()
	_check(exposed in candidates and not safe in candidates, "only the exposed pawn is offered, got %d" % candidates.size())
	cm.choose_target(exposed)
	await _wait_state(GameManager.GameState.WAITING_FOR_ROLL)
	_check(exposed.current_tile_index == gm.get_homebase_tile(1), "banished pawn at its homebase")
	_check(not gm.is_unlocked(0) and not gm._extra_throw_pending, "banish is not a capture")

func _scenario_switcheroo_two_targets() -> void:
	print("scenario: Switcheroo picks two pawns and swaps them")
	await _new_game([], [&"switcheroo"])
	var mine: Pawn = _pawns(0)[0]
	var theirs: Pawn = _pawns(1)[0]
	_put(mine, _path(0)[5])
	_put(theirs, _path(0)[7])
	_check(await _play(0, [mine, theirs]), "Switcheroo should play")
	_check(mine.current_tile_index == _path(0)[7] and theirs.current_tile_index == _path(0)[5], "pawns swapped")

func _scenario_master_key_and_turn_limit() -> void:
	print("scenario: Master Key unlocks; a second card the same turn is refused")
	await _new_game([], [&"master_key", &"sprint"])
	_check(await _play(0), "Master Key should play")
	_check(gm.is_unlocked(0), "inner ring unlocked")
	_check(not cm.request_play(0), "second card this turn refused")
	_check(_events.any(func(e): return e.begins_with("rejected Card limit")), "rejection says why, got %s" % str(_events))

func _scenario_window_closes_after_throw() -> void:
	print("scenario: cards can't be played after throwing")
	await _new_game([2], [&"sprint"])
	gm.request_roll_dice()
	await get_tree().process_frame
	_check(not cm.request_play(0), "no cards after the first throw")
	_check(cm.hands[0].size() == 1, "card stays in hand")

func _scenario_cancel_keeps_card() -> void:
	print("scenario: cancelling a target pick keeps the card and the turn")
	await _new_game([], [&"sprint"])
	_check(cm.request_play(0) and cm.is_targeting(), "targeting started")
	_check(gm.current_state == GameManager.GameState.PLAYING_CARD and gm.roll_button.disabled, "throw locked while picking")
	cm.cancel_targeting()
	_check(gm.current_state == GameManager.GameState.WAITING_FOR_ROLL and not gm.roll_button.disabled, "back to waiting")
	_check(cm.hands[0].size() == 1 and cm.can_play_now(), "card still in hand and playable")

func _scenario_card_move_wins() -> void:
	print("scenario: a card move that brings the last pawn home wins")
	await _new_game([], [&"sprint"])
	gm.player_has_killed[0] = true
	_place(0, [24, 24, 24, 22])
	_check(cm.request_play(0), "Sprint playable")
	_check(cm.get_target_candidates() == [_pawns(0)[3]], "only the last pawn can move 2")
	cm.choose_target(_pawns(0)[3])
	var end := Time.get_ticks_msec() + 2000
	while not gm.is_game_finished() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	_check("game_over 0" in _events, "player 1 wins, got %s" % str(_events))

func _scenario_lucky_charm_and_tailwind() -> void:
	print("scenario: Lucky Charm changes only its owner's odds; Tailwind adds a step")
	await _new_game([], [&"lucky_charm"])
	_check(await _play(0), "Lucky Charm should play")
	_check(is_equal_approx(gm.rules.modify(&"open_up_probability", 0.5, {"player": 0}), 0.75), "owner's odds 0.75")
	_check(is_equal_approx(gm.rules.modify(&"open_up_probability", 0.5, {"player": 1}), 0.5), "opponent unaffected")
	await _new_game([], [&"tailwind"])
	_check(await _play(0), "Tailwind should play")
	_check(gm._get_step_sequence(_pawns(0)[0], 1).size() == 2, "a 1 moves 2")
	_check(gm._get_step_sequence(_pawns(1)[0], 1).size() == 1, "opponent unaffected")

func _scenario_cards_off_removes_system() -> void:
	print("scenario: cards off -> no CardManager, plain rules")
	await _new_game([], [], false)
	_check(not is_instance_valid(cm) or cm.is_queued_for_deletion(), "CardManager removed")
	_check(not gm.rules is ModifierHooks and not gm.board.rules is ModifierHooks, "default rule hooks")
	_check(gm.current_state == GameManager.GameState.WAITING_FOR_ROLL, "game starts normally")
	GameConfig.cards_enabled = false
