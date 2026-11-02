extends SceneTree

## The open card draft (GameConfig.DRAFT_OPEN): one face-up pool of hand_size + 1 cards
## per player, picks in snake order, every pick checked (whose pick, a card still there),
## dealing only by the authority, and every hand full at the end.
## Run: godot --headless --path . -s res://tests/OpenDraftTest.gd

var failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

func _run() -> void:
	for players in [2, 3, 4]:
		await _draft(players)
	if failures == 0:
		print("✅ OPEN DRAFT TESTS PASSED")
		quit(0)
	else:
		print("❌ OPEN DRAFT TESTS FAILED: %d check(s)" % failures)
		quit(1)

func _draft(players: int) -> void:
	var main: Node = load("res://MainGame.tscn").instantiate()
	MatchSetup.make(GameConfig.default_players(players), true, "off", GameConfig.DRAFT_OPEN).apply_to(main)
	root.add_child(main)
	var gm: GameManager = main.get_node("GameManager")
	var cm: CardManager = main.get_node("CardManager")
	var mc: MatchController = main.get_node("MatchController")
	var hand := cm.rules_config.hand_size
	for i in 600:
		if cm.is_open_draft_started():
			break
		await process_frame
	_check(cm.is_open_draft_started(), "%dp: the pool is dealt" % players)
	_check(cm.open_pool.size() == players * (hand + 1), "%dp: pool of %d cards, got %d" % [players, players * (hand + 1), cm.open_pool.size()])
	var copies := {}
	for card in cm.open_pool:
		copies[card.id] = copies.get(card.id, 0) + 1
	_check(copies.values().max() <= maxi(2, players), "%dp: no card has more copies than allowed" % players)
	_check(not mc.submit(PlayerIntent.draft_pool(["sprint"])), "%dp: the pool can't be dealt twice" % players)

	# snake order: 0 1 .. n-1, n-1 .. 1 0, ...
	var expected: Array[int] = []
	for lap in hand:
		for pos in players:
			expected.append(pos if lap % 2 == 0 else players - 1 - pos)
	var seen: Array[int] = []
	for pick in expected.size():
		var picker := cm.open_draft_picker()
		seen.append(picker)
		var wrong := (picker + 1) % players
		_check(not mc.submit(PlayerIntent.draft_take(wrong, cm.first_open_slot())), "%dp: pick %d by the wrong player is refused" % [players, pick])
		var slot := cm.first_open_slot()
		if pick > 0:
			var taken_slot := -1
			for i in cm.open_taken.size():
				if cm.open_taken[i] >= 0:
					taken_slot = i
					break
			_check(not mc.submit(PlayerIntent.draft_take(picker, taken_slot)), "%dp: a taken card can't be taken again" % players)
		_check(mc.submit(PlayerIntent.draft_take(picker, slot)), "%dp: pick %d by player %d is accepted" % [players, pick, picker])
		await process_frame
	_check(seen == expected, "%dp: picks go in snake order, got %s" % [players, seen])
	_check(cm.is_open_draft_done(), "%dp: the draft is done" % players)
	for p in players:
		_check(cm.hands[p].size() == hand, "%dp: player %d holds %d cards, got %d" % [players, p, hand, cm.hands[p].size()])
	_check(cm.open_taken.count(-1) == players, "%dp: one spare card per player is left" % players)
	for i in 300:
		if gm.current_state == GameManager.GameState.WAITING_FOR_ROLL:
			break
		await process_frame
	_check(gm.current_state == GameManager.GameState.WAITING_FOR_ROLL, "%dp: the game starts after the draft" % players)
	main.queue_free()
	await process_frame
