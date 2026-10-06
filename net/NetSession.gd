class_name NetSession
extends Node

## The online connection, alive from the menu through the match (it sits under the
## scene-tree root, so scene changes don't free it). Uses Godot's high-level
## multiplayer, so the transport is swappable: WebSocket today, WebRTC later.
##
## Host (peer 1) is the authority and plays seat 0. Messages:
##   client -> host   hello(name, token, ver)  join (ver = GameConfig.PROTOCOL_VERSION)
##   host -> client   welcome(seat, token)     your seat + reconnect token
##   host -> all      roster(list, settings)   who's in the room + room settings (cards on/off)
##   client -> host   request_color(name)      switch to a free pawn colour
##   host -> all      start(config)            load the match
##   client -> host   intent(dict)             a PlayerIntent (host checks the sender's seat)
##   host -> each     event(dict)              numbered event (redacted per seat: no peeking at hands)
##   host -> one      private(dict)            e.g. your draft offer
##   host -> one      rejected(intent, reason)
## Messages that arrive before the match scene is ready are buffered.
## Transport: only _open_server() / _open_client() know it's WebSocket; everything else
## uses Godot's MultiplayerAPI, so WebRTC (or anything else) is a swap of those two.

signal roster_changed(roster: Array)
## Room settings changed (host's choices, e.g. {"cards": true}).
signal settings_changed(settings: Dictionary)
signal joined(seat: int)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal match_starting(config: Dictionary)
signal intent_rejected(intent: Dictionary, reason: String)
## Host: room code progress ("Getting a room code..."), the code itself, or why there isn't one.
signal room_status(text: String)
## live = false: Cloudflare hasn't confirmed it yet (slow); it usually works a minute later.
signal room_code_ready(code: String, live: bool)
signal room_code_failed(reason: String)
## Client: a join attempt failed and is being retried (new room codes take a moment to go live).
signal join_retrying(attempt: int)

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT := 9080
const NODE_NAME := "NetSession"
## Join attempts before giving up (a just-created room code can take a few seconds to resolve).
const JOIN_ATTEMPTS := 6
const JOIN_RETRY_DELAY := 3.0
## Godot's default (3 s) is too short for a first connection through a new tunnel
## (TLS + Cloudflare routing) or slow Wi-Fi.
const HANDSHAKE_TIMEOUT := 15.0
const DEFAULT_SETTINGS := {"cards": true}

var role: Role = Role.NONE
var local_seat: int = -1
var local_name: String = ""
## Host: [{seat, name, color_name, peer, token, connected}]. Clients get it without tokens.
var roster: Array = []
var match_config: Dictionary = {}
## Room settings chosen by the host and shown to everyone in the lobby.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var in_match: bool = false
## How the match scene is loaded once the host starts (tests load it in place).
var scene_loader: Callable

var _controller: MatchController
var _pending_events: Array = []
var _pending_private: Array = []
var _token: String = ""
var _tunnel: Tunnel
var _join_url: String = ""
var _join_attempt: int = 0
## Bumped by join()/leave(), so a pending retry from an abandoned join never fires.
var _join_generation: int = 0
## Host: the current room code ("" until the tunnel is open).
var room_code: String = ""
var _rng := RandomNumberGenerator.new()

## The session under the scene-tree root, if any.
static func find(tree: SceneTree) -> NetSession:
	return tree.root.get_node_or_null(NODE_NAME) as NetSession

## What a player typed -> a WebSocket URL: "192.168.1.5:9080" -> "ws://192.168.1.5:9080";
## a bare host gets the default port; ws:// and wss:// URLs pass through. "" if empty.
static func address_to_url(address: String) -> String:
	var text := address.strip_edges()
	if text == "":
		return ""
	if text.begins_with("ws://") or text.begins_with("wss://"):
		return text
	if text.begins_with("https://"):
		return "wss://" + text.trim_prefix("https://").trim_suffix("/")
	if text.begins_with("http://"):
		return "ws://" + text.trim_prefix("http://").trim_suffix("/")
	if Tunnel.is_room_code(text):
		return Tunnel.code_to_url(text)
	if text.ends_with(Tunnel.DOMAIN):
		return "wss://" + text
	if not ":" in text:
		text += ":%d" % DEFAULT_PORT
	return "ws://" + text

## The session under the root, created on first use.
static func ensure(tree: SceneTree) -> NetSession:
	var session := find(tree)
	if session == null:
		session = NetSession.new()
		session.name = NODE_NAME
		tree.root.add_child(session)
	return session

func _ready() -> void:
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_online() -> bool:
	return role != Role.NONE

func is_host() -> bool:
	return role == Role.HOST

# --- HOSTING / JOINING ---
func host(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var err := _open_server(port)
	if err != OK:
		return err
	role = Role.HOST
	local_seat = 0
	local_name = player_name
	roster = [{"seat": 0, "name": player_name, "color_name": _free_color(), "peer": 1,
		"token": _new_token(), "connected": true}]
	_token = roster[0]["token"]
	roster_changed.emit(public_roster())
	return OK

## url like "ws://127.0.0.1:9080" or "wss://<code>.trycloudflare.com".
## token reclaims a previous seat in this room.
func join(url: String, player_name: String, token: String = "") -> Error:
	leave()
	_join_generation += 1
	_join_url = url
	_join_attempt = 1
	local_name = player_name
	_token = token
	return _connect_client()

func _connect_client() -> Error:
	var err := _open_client(_join_url)
	if err != OK:
		return err
	role = Role.CLIENT
	return OK

# --- TRANSPORT (the only WebSocket-specific code) ---
func _open_server(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = HANDSHAKE_TIMEOUT
	var err := peer.create_server(port)
	if err != OK:
		return err
	# Star network: clients only talk to the host, and don't need to hear about each other
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	return OK

func _open_client(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = HANDSHAKE_TIMEOUT
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func _on_connection_failed() -> void:
	if role == Role.CLIENT and local_seat < 0 and _join_attempt < JOIN_ATTEMPTS:
		_join_attempt += 1
		join_retrying.emit(_join_attempt)
		var generation := _join_generation
		await get_tree().create_timer(JOIN_RETRY_DELAY).timeout
		if generation == _join_generation and role == Role.CLIENT and local_seat < 0:
			_connect_client()
		return
	_fail("Couldn't reach the host. Check the room code, and that the host is still in the lobby.")

# --- ROOM CODE (host) ---
## Host: open a Cloudflare quick tunnel so friends anywhere (and browsers) can join with a code.
func open_room_code(port: int = DEFAULT_PORT) -> void:
	if not is_host():
		return
	if not Tunnel.is_supported():
		room_code_failed.emit("Room codes need the Windows build.")
		return
	if _tunnel == null:
		_tunnel = Tunnel.new()
		_tunnel.name = "Tunnel"
		add_child(_tunnel)
		_tunnel.status_changed.connect(func(text): room_status.emit(text))
		_tunnel.opened.connect(func(code, live):
			room_code = code
			room_code_ready.emit(code, live))
		_tunnel.failed.connect(func(reason): room_code_failed.emit(reason))
	room_code = ""
	_tunnel.open(port)

func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if _tunnel:
		_tunnel.close()
	room_code = ""
	_join_generation += 1
	role = Role.NONE
	local_seat = -1
	roster = []
	in_match = false
	settings = DEFAULT_SETTINGS.duplicate()
	_controller = null
	_pending_events.clear()
	_pending_private.clear()

func get_token() -> String:
	return _token

## Roster without secrets, as sent to clients.
func public_roster() -> Array:
	return roster.map(func(entry): return {"seat": entry["seat"], "name": entry["name"],
		"color_name": entry["color_name"], "connected": entry["connected"]})

func _new_token() -> String:
	return "%08x%08x" % [_rng.randi(), _rng.randi()]

## Two players can't share a name: "Ana" becomes "Ana 2", "Ana 3"...
func _unique_name(wanted: String) -> String:
	var taken := func(n: String): return roster.any(func(e): return e["name"].to_lower() == n.to_lower())
	if not taken.call(wanted):
		return wanted
	var i := 2
	while taken.call("%s %d" % [wanted, i]):
		i += 1
	return "%s %d" % [wanted, i]

func _free_color() -> String:
	for color_name in GameConfig.COLORS:
		if not roster.any(func(entry): return entry["color_name"] == color_name):
			return color_name
	return GameConfig.COLORS.keys()[0]

func _fail(reason: String) -> void:
	connection_failed.emit(reason)
	leave()

# --- CONNECTION EVENTS ---
func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, local_name, _token, GameConfig.PROTOCOL_VERSION)

func _on_server_disconnected() -> void:
	disconnected.emit("The host left.")
	leave()

func _on_peer_connected(_peer_id: int) -> void:
	pass # wait for hello

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	for entry in roster.duplicate():
		if entry["peer"] == peer_id:
			entry["connected"] = false
			entry["peer"] = 0
			if not in_match:
				roster.erase(entry) # seats are only held once the match has started
	if not in_match:
		_renumber_seats()
	_broadcast_roster()

## Lobby only: keep seats 0..n-1 after someone leaves, and tell moved players.
func _renumber_seats() -> void:
	for i in roster.size():
		if roster[i]["seat"] != i:
			roster[i]["seat"] = i
			if roster[i]["peer"] > 1:
				_rpc_welcome.rpc_id(roster[i]["peer"], i, roster[i]["token"])

func _broadcast_roster() -> void:
	_rpc_roster.rpc(public_roster(), settings)
	roster_changed.emit(public_roster())

## The roster entry for the seat this copy plays.
func local_entry() -> Dictionary:
	for entry in roster:
		if entry["seat"] == local_seat:
			return entry
	return {}

## Host: change a room setting and tell everyone.
func set_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	settings[key] = value
	settings_changed.emit(settings)
	_broadcast_roster()

## Switch this player's pawn colour (only to one nobody else has).
func request_color(color_name: String) -> void:
	if is_host():
		_set_color(local_seat, color_name)
	elif is_online():
		_rpc_request_color.rpc_id(1, color_name)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_color(color_name: String) -> void:
	var seat := _seat_of_peer(multiplayer.get_remote_sender_id())
	if is_host() and seat >= 0:
		_set_color(seat, color_name)

func _set_color(seat: int, color_name: String) -> void:
	if in_match or not GameConfig.COLORS.has(color_name):
		return
	if roster.any(func(e): return e["seat"] != seat and e["color_name"] == color_name):
		return # taken
	for entry in roster:
		if entry["seat"] == seat:
			entry["color_name"] = color_name
	_broadcast_roster()

# --- LOBBY ---
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(player_name: String, token: String, protocol: int) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if protocol != GameConfig.PROTOCOL_VERSION:
		_rpc_refused.rpc_id(peer_id, "Your game version doesn't match the host's. Both players need the latest build.")
		return
	var existing_seat := _seat_of_peer(peer_id)
	if existing_seat >= 0:
		_rpc_welcome.rpc_id(peer_id, existing_seat, _token_of_seat(existing_seat)) # repeated hello: same seat
		return
	var entry: Dictionary = {}
	for existing in roster:
		if token != "" and existing["token"] == token:
			entry = existing # reclaiming a seat
	if in_match:
		# Rejoining a running match needs a state sync (phase 5); until then, refuse cleanly
		_rpc_refused.rpc_id(peer_id, "This match is already in progress." if entry.is_empty() \
			else "Rejoining a match in progress isn't supported yet.")
		return
	if entry.is_empty():
		if roster.size() >= GameConfig.MAX_PLAYERS:
			_rpc_refused.rpc_id(peer_id, "The room is full.")
			return
		entry = {"seat": roster.size(), "name": player_name.strip_edges().left(GameConfig.NAME_MAX_LENGTH),
			"color_name": _free_color(), "token": _new_token()}
		if entry["name"] == "":
			entry["name"] = "Player %d" % (entry["seat"] + 1)
		entry["name"] = _unique_name(entry["name"])
		roster.append(entry)
	entry["peer"] = peer_id
	entry["connected"] = true
	_rpc_welcome.rpc_id(peer_id, entry["seat"], entry["token"])
	_broadcast_roster()

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(seat: int, token: String) -> void:
	local_seat = seat
	_token = token
	joined.emit(seat)

@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: String) -> void:
	_fail(reason)

@rpc("authority", "call_remote", "reliable")
func _rpc_roster(list: Array, room_settings: Dictionary) -> void:
	roster = list
	if room_settings != settings:
		settings = room_settings
		settings_changed.emit(settings)
	roster_changed.emit(roster)

# --- MATCH START ---
## Host: everyone loads the match with the current roster and room settings.
func start_match() -> void:
	if not is_host() or roster.size() < GameConfig.MIN_PLAYERS:
		return
	var players: Array = roster.map(func(entry): return {"name": entry["name"], "color_name": entry["color_name"]})
	var config := {"players": players, "cards": bool(settings.get("cards", true))}
	_rpc_start.rpc(config)
	_begin_match(config)

@rpc("authority", "call_remote", "reliable")
func _rpc_start(config: Dictionary) -> void:
	_begin_match(config)

func _begin_match(config: Dictionary) -> void:
	match_config = config
	in_match = true
	var players: Array[Dictionary] = []
	for p in config["players"]:
		players.append({"name": p["name"], "color_name": p["color_name"]})
	GameConfig.players = players
	GameConfig.cards_enabled = bool(config["cards"])
	match_starting.emit(config)
	if scene_loader.is_valid():
		scene_loader.call(config)
	else:
		get_tree().change_scene_to_file("res://MainGame.tscn")

## Called by the match's MatchController once it's ready; flushes buffered messages.
func register_controller(controller: MatchController) -> void:
	_controller = controller
	for data in _pending_private:
		controller.receive_private(data)
	_pending_private.clear()
	for event in _pending_events:
		controller.apply_event(event)
	_pending_events.clear()

# --- MATCH TRAFFIC ---
## Client: send an intent to the host.
func send_intent(intent: Dictionary) -> void:
	_rpc_intent.rpc_id(1, intent)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(intent: Dictionary) -> void:
	if not is_host() or _controller == null:
		return
	var seat := _seat_of_peer(multiplayer.get_remote_sender_id())
	var parsed := PlayerIntent.from_dict(intent)
	if seat < 0 or parsed == null:
		return # unknown sender or malformed message: ignore
	_controller.submit_remote(parsed, seat)

## Host: send each connected client its own view of a new event.
func broadcast_event(event: Dictionary) -> void:
	for entry in roster:
		if entry["seat"] != local_seat and entry["connected"]:
			_rpc_event.rpc_id(entry["peer"], _controller.event_for_seat(event, entry["seat"]))

@rpc("authority", "call_remote", "reliable")
func _rpc_event(event: Dictionary) -> void:
	if _controller:
		_controller.apply_event(event)
	else:
		_pending_events.append(event)

## Host: private data for one seat (e.g. a draft offer).
func send_private(seat: int, data: Dictionary) -> void:
	var peer := _peer_of_seat(seat)
	if peer > 0:
		_rpc_private.rpc_id(peer, data)

@rpc("authority", "call_remote", "reliable")
func _rpc_private(data: Dictionary) -> void:
	if _controller:
		_controller.receive_private(data)
	else:
		_pending_private.append(data)

func send_rejected(seat: int, intent: Dictionary, reason: String) -> void:
	var peer := _peer_of_seat(seat)
	if peer > 0:
		_rpc_rejected.rpc_id(peer, intent, reason)

@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(intent: Dictionary, reason: String) -> void:
	intent_rejected.emit(intent, reason)

func _seat_of_peer(peer_id: int) -> int:
	for entry in roster:
		if entry.get("peer", 0) == peer_id:
			return entry["seat"]
	return -1

func _token_of_seat(seat: int) -> String:
	for entry in roster:
		if entry["seat"] == seat:
			return entry.get("token", "")
	return ""

func _peer_of_seat(seat: int) -> int:
	for entry in roster:
		if entry["seat"] == seat and entry["connected"]:
			return entry["peer"]
	return 0
