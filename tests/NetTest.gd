extends Node

## Online play over a real localhost WebSocket, all in one process: a host and
## clients each get their own MultiplayerAPI branch (like separate machines).
## Checks: joining and seats, out-of-turn intents rejected by the host, clients
## can't see other players' cards, and every copy stays in sync through a full
## bot-played match (turn-start fingerprints and final state).
## Run: godot --headless --path . --time-scale 30 res://tests/NetTest.tscn

const GAME_SCENE_PATH = "res://MainGame.tscn"
const MAX_ACTIONS := 4000

var failures := 0
var _bot := RandomNumberGenerator.new()

func _ready() -> void:
	await _run(3, true, 19181, 7)
	await _run(2, false, 19182, 8)
	if failures == 0:
		print("✅ NET TESTS PASSED")
		get_tree().quit(0)
	else:
		print("❌ NET TESTS FAILED: %d check(s)" % failures)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

## One "machine": its own multiplayer branch with a NetSession, later a match.
func _make_machine(label: String, seed_value: int) -> Dictionary:
	var root := Node.new()
	root.name = label
	add_child(root)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), root.get_path())
	var net := NetSession.new()
	net.name = NetSession.NODE_NAME
	root.add_child(net)
	var machine := {"label": label, "root": root, "net": net, "seed": seed_value, "hashes": []}
	net.scene_loader = func(_config): _load_match(machine)
	return machine

func _load_match(machine: Dictionary) -> void:
	var main: Node = load(GAME_SCENE_PATH).instantiate()
	main.get_node("GameManager").rng_seed = machine["seed"]
	var cm: CardManager = main.get_node("CardManager")
	cm.auto_draft = true
	var rules: CardRulesConfig = cm.rules_config.duplicate()
	rules.rng_seed = machine["seed"]
	cm.rules_config = rules
	var ctrl: MatchController = main.get_node("MatchController")
	ctrl.net = machine["net"]
	machine["root"].add_child(main)
	machine["gm"] = main.get_node("GameManager")
	machine["ctrl"] = ctrl
	machine["gm"].turn_changed.connect(func(_p): machine["hashes"].append(ctrl.get_state_hash()))

func _wait(condition: Callable, seconds: float, what: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			_check(false, "timed out waiting for " + what)
			return false
		await get_tree().process_frame
	return true

func _run(players: int, cards: bool, port: int, seed_value: int) -> void:
	print("net: %d players, cards %s" % [players, "on" if cards else "off"])
	_bot.seed = seed_value
	var machines: Array = [_make_machine("Host", seed_value)]
	for i in players - 1:
		machines.append(_make_machine("Client%d" % (i + 1), seed_value + 100 * (i + 1)))
	var host: Dictionary = machines[0]
	_check(host["net"].host("Hana", port) == OK, "host should listen on port %d" % port)
	for i in range(1, players):
		# Everyone asks for the host's name: the host makes them unique
		_check(machines[i]["net"].join("ws://127.0.0.1:%d" % port, "Hana") == OK, "client %d should connect" % i)
	if not await _wait(func(): return host["net"].roster.size() == players and machines.all(func(m): return m["net"].local_seat >= 0), 10.0, "everyone to join"):
		return _teardown(machines)
	_check(range(players).all(func(i): return machines[i]["net"].local_seat == i), "seats follow join order")
	var names: Array = host["net"].roster.map(func(e): return e["name"])
	_check(names[0] == "Hana" and names[1] == "Hana 2" and (players < 3 or names[2] == "Hana 3"), "duplicate names get a number, got %s" % str(names))

	# Lobby: the host's setting and a client's colour change reach everyone
	host["net"].set_setting("cards", not cards)
	host["net"].set_setting("cards", cards)
	var taken: String = host["net"].roster[0]["color_name"]
	machines[1]["net"].request_color(taken) # taken by the host: refused
	machines[1]["net"].request_color("Green") # free with 2-3 players
	var lobby_synced := func(): return machines.all(func(m): return m["net"].settings.get("cards") == cards \
		and m["net"].roster.size() == players and m["net"].roster[1]["color_name"] == "Green")
	await _wait(lobby_synced, 5.0, "lobby settings and colours to reach everyone")
	_check(host["net"].roster[0]["color_name"] == taken, "a taken colour can't be requested")

	host["net"].start_match()
	if not await _wait(func(): return machines.all(func(m): return m.has("gm") and m["gm"].current_state == GameManager.GameState.WAITING_FOR_ROLL), 10.0, "every copy to start"):
		return _teardown(machines)

	if cards:
		var client_cm: CardManager = machines[1]["ctrl"].card_manager
		_check(client_cm.hands[1].all(func(c): return c != null), "a client sees its own cards")
		_check(client_cm.hands[0].all(func(c): return c == null) and client_cm.hands[0].size() == 5, "a client can't see the host's cards")
		_check(host["ctrl"].card_manager.hands[1].all(func(c): return c != null), "the host knows every hand (it's the referee)")

	# Out of turn: seat 1 tries to throw on seat 0's turn
	var rejections: Array = []
	machines[1]["net"].intent_rejected.connect(func(_intent, reason): rejections.append(reason))
	machines[1]["ctrl"].throw_shells()
	await _wait(func(): return not rejections.is_empty(), 5.0, "the host to reject an out-of-turn throw")
	_check(rejections.size() == 1 and rejections[0] == "Not your turn.", "out-of-turn throw rejected, got %s" % str(rejections))
	_check(host["ctrl"].applied_seq == machines[1]["ctrl"].applied_seq, "a rejected intent creates no event")

	# Full match: whoever's turn it is acts on their own copy, once it has caught up
	var actions := 0
	var host_gm: GameManager = host["gm"]
	while not host_gm.is_game_finished() and actions < MAX_ACTIONS:
		await get_tree().create_timer(0.05).timeout
		var actor: Dictionary = machines[host_gm.current_player_index]
		var caught_up: bool = actor["ctrl"].applied_seq == host["ctrl"].next_seq - 1
		if caught_up and (actor["gm"].is_settled() or actor["gm"].current_state == GameManager.GameState.PLAYING_CARD):
			actions += 1
			_bot_step(actor["gm"], actor["ctrl"])
	_check(host_gm.is_game_finished(), "match should finish")
	await _wait(func(): return machines.all(func(m): return m["ctrl"].applied_seq == host["ctrl"].applied_seq and m["gm"].is_game_finished()), 10.0, "clients to apply the last events")

	var final_hash: String = host["ctrl"].get_state_hash()
	for m in machines:
		_check(m["ctrl"].get_state_hash() == final_hash, "%s final state differs" % m["label"])
		_check(m["hashes"] == host["hashes"], "%s turn-start fingerprints differ (%d vs %d turns)" % [m["label"], m["hashes"].size(), host["hashes"].size()])
	print("   %d events, %d turns, %d bot actions, final %s" % [host["ctrl"].applied_seq + 1, host["hashes"].size(), actions, final_hash])
	await _teardown(machines)

func _teardown(machines: Array) -> void:
	for m in machines:
		m["net"].leave()
		m["root"].queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _bot_step(gm: GameManager, ctrl: MatchController) -> void:
	RandomBot.step(gm, ctrl, _bot)
