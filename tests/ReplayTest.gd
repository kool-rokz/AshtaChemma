extends Node

## Proves copies of a match stay identical, the basis for online play:
##   A (authority) plays a random game with a seeded bot;
##   B (replica, different RNG seeds) only receives A's events, sent through JSON
##   like the network will carry them. Their state fingerprints must match at every
##   turn start and at the end.
##   Mid-game, A's snapshot (also through JSON) is loaded into a fresh copy C,
##   which must fingerprint the same (rejoin / resume).
## Run: godot --headless --path . --time-scale 30 res://tests/ReplayTest.tscn

const GAME_SCENE_PATH = "res://MainGame.tscn"
const MAX_ACTIONS := 3000
const SNAPSHOT_AT_ACTION := 25

var failures := 0
var _bot := RandomNumberGenerator.new()

func _ready() -> void:
	await _run(2, false, 11)
	await _run(2, true, 22)
	await _run(3, true, 33)
	await _run(4, true, 44)
	if failures == 0:
		print("✅ REPLAY TESTS PASSED")
		get_tree().quit(0)
	else:
		print("❌ REPLAY TESTS FAILED: %d check(s)" % failures)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

## Network stand-in: everything crosses as JSON text.
static func _wire(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _spawn(players: int, cards: bool, replica: bool, seed_value: int, resume: Dictionary = {}) -> Node:
	var main: Node = load(GAME_SCENE_PATH).instantiate()
	var setup := MatchSetup.make(GameConfig.default_players(players), cards)
	setup.resume = resume
	setup.apply_to(main)
	main.get_node("GameManager").rng_seed = seed_value
	var cm: CardManager = main.get_node("CardManager")
	cm.auto_draft = true
	var rules: CardRulesConfig = cm.rules_config.duplicate()
	rules.rng_seed = seed_value
	cm.rules_config = rules
	if replica:
		main.get_node("MatchController").mode = MatchController.Mode.REPLICA
	add_child(main)
	return main

func _run(players: int, cards: bool, seed_value: int) -> void:
	print("replay: %d players, cards %s" % [players, "on" if cards else "off"])
	_bot.seed = seed_value
	var a := _spawn(players, cards, false, seed_value)
	var b := _spawn(players, cards, true, seed_value + 1000) # its own RNG must never matter
	var a_gm: GameManager = a.get_node("GameManager")
	var b_gm: GameManager = b.get_node("GameManager")
	var a_ctrl: MatchController = a.get_node("MatchController")
	var b_ctrl: MatchController = b.get_node("MatchController")
	a_ctrl.event_created.connect(func(event): b_ctrl.apply_event(_wire(event)))
	var a_hashes: Array[String] = []
	var b_hashes: Array[String] = []
	a_gm.turn_changed.connect(func(_p): a_hashes.append(a_ctrl.get_state_hash()))
	b_gm.turn_changed.connect(func(_p): b_hashes.append(b_ctrl.get_state_hash()))
	await get_tree().process_frame
	await get_tree().process_frame

	var actions := 0
	var snapshot_checked := false
	while not a_gm.is_game_finished() and actions < MAX_ACTIONS:
		await get_tree().create_timer(0.05).timeout
		actions += 1
		if not snapshot_checked and actions >= SNAPSHOT_AT_ACTION and a_gm.is_settled() \
				and a_gm.current_state == GameManager.GameState.WAITING_FOR_ROLL:
			snapshot_checked = true
			await _check_snapshot_resume(a_ctrl, players, cards, seed_value + 2000)
		_bot_step(a_gm, a_ctrl)
	_check(a_gm.is_game_finished(), "game should finish within %d bot actions" % MAX_ACTIONS)
	_check(snapshot_checked, "snapshot resume was exercised")

	# Let B catch up with A's last events
	var deadline := Time.get_ticks_msec() + 5000
	while (b_ctrl.applied_seq < a_ctrl.applied_seq or not b_gm.is_game_finished()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(b_ctrl.applied_seq == a_ctrl.applied_seq, "replica applied %d of %d events" % [b_ctrl.applied_seq + 1, a_ctrl.applied_seq + 1])
	_check(a_hashes.size() > 2 and a_hashes == b_hashes, "turn-start fingerprints differ (A %d turns, B %d turns, first mismatch at %d)" % [
		a_hashes.size(), b_hashes.size(), _first_mismatch(a_hashes, b_hashes)])
	_check(a_ctrl.get_state_hash() == b_ctrl.get_state_hash(), "final state differs")
	print("   %d events, %d turns, final %s" % [a_ctrl.applied_seq + 1, a_hashes.size(), a_ctrl.get_state_hash()])
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame

func _first_mismatch(x: Array[String], y: Array[String]) -> int:
	for i in mini(x.size(), y.size()):
		if x[i] != y[i]:
			return i
	return -1 if x.size() == y.size() else mini(x.size(), y.size())

## A fresh copy started from A's snapshot (the rejoin path, MatchSetup.resume) must
## match it exactly, without running a draft or a new game start.
func _check_snapshot_resume(a_ctrl: MatchController, players: int, cards: bool, seed_value: int) -> void:
	var snap := _wire(a_ctrl.get_snapshot())
	var c := _spawn(players, cards, false, seed_value, snap)
	var c_ctrl: MatchController = c.get_node("MatchController")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(c_ctrl.get_state_hash() == a_ctrl.get_state_hash(), "snapshot loaded into a fresh copy should match the original")
	_check(c_ctrl.applied_seq == a_ctrl.applied_seq, "resumed copy continues from the same event number")
	c.queue_free()

func _bot_step(gm: GameManager, ctrl: MatchController) -> void:
	RandomBot.step(gm, ctrl, _bot)
