extends SceneTree

## The parts of net/Tunnel.gd that don't need cloudflared: room-code parsing, and the
## "is the room reachable yet?" check run against a real local WebSocket server (it
## must succeed) and a dead port (it must give up within its timeout, without errors).
## Run: godot --headless --path . -s res://tests/TunnelTest.gd

const PORT := 19341
const DEAD_PORT := 19342

var failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

func _run() -> void:
	_check(Tunnel.is_room_code("brave-lemon-kite-maple"), "a four-word code is a room code")
	_check(not Tunnel.is_room_code("DESKTOP-AB12"), "a PC name is not a room code")
	_check(not Tunnel.is_room_code("192.168.1.5:9080"), "an address is not a room code")
	_check(Tunnel.code_to_url(" Brave-Lemon-Kite-Maple ") == "wss://brave-lemon-kite-maple.trycloudflare.com", "codes become tunnel URLs")
	var ws := WebSocketTransport.new()
	_check(ws.to_target("192.168.1.5") == "ws://192.168.1.5:%d" % WebSocketTransport.DEFAULT_PORT, "a bare address gets the default port")
	_check(ws.to_target("brave-lemon-kite-maple") == "wss://brave-lemon-kite-maple.trycloudflare.com", "the transport turns room codes into tunnel URLs")
	_check(ws.find_address("Join my game! Room code: brave-lemon-kite-maple.") == "brave-lemon-kite-maple", "an invite message gives its room code")
	_check(ws.find_address("https://x.itch.io/game?room=brave-lemon-kite-maple&y=1") == "brave-lemon-kite-maple", "an invite link gives its room code")
	_check(ws.to_target("") == "", "nothing typed is no address")

	var server := WebSocketMultiplayerPeer.new()
	_check(server.create_server(PORT) == OK, "local test server should start")
	get_multiplayer().multiplayer_peer = server # polled by the tree from now on
	await process_frame # the tree accepts nodes once it's running
	var tunnel := Tunnel.new()
	root.add_child(tunnel)

	var began := Time.get_ticks_msec()
	var live: bool = await tunnel._wait_until_reachable("http://127.0.0.1:%d" % PORT, tunnel._generation, 5.0)
	_check(live, "a running server should be reachable")
	print("reachable: %s in %d ms" % [live, Time.get_ticks_msec() - began])

	began = Time.get_ticks_msec()
	var dead: bool = await tunnel._wait_until_reachable("http://127.0.0.1:%d" % DEAD_PORT, tunnel._generation, 3.0)
	var took := Time.get_ticks_msec() - began
	_check(not dead, "a dead port should not count as reachable")
	_check(took < 3000 + int(Tunnel.REACH_RETRY_DELAY * 1000) + 500, "giving up should respect the timeout (took %d ms)" % took)
	print("dead port: %s after %d ms" % [dead, took])

	get_multiplayer().multiplayer_peer = null
	server.close()
	tunnel.free()
	if failures == 0:
		print("✅ TUNNEL TESTS PASSED")
		quit(0)
	else:
		print("❌ TUNNEL TESTS FAILED: %d check(s)" % failures)
		quit(1)
