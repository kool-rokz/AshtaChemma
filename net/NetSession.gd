class_name NetSession
extends Node

## The online connection, alive from the menu through the match (it sits under the
## scene-tree root, so scene changes don't free it). Uses Godot's high-level
## multiplayer, so the transport is swappable: WebSocket today, WebRTC later.
##
## Host (peer 1) is the authority and plays seat 0. Messages:
##   client -> host   hello(name, token)       join / reclaim a seat
##   host -> client   welcome(seat, token)     your seat + reconnect token
##   host -> all      roster(list)             who's in the room
##   host -> all      start(config)            load the match
##   client -> host   intent(dict)             a PlayerIntent (host checks the sender's seat)
##   host -> each     event(dict)              numbered event (redacted per seat: no peeking at hands)
##   host -> one      private(dict)            e.g. your draft offer
##   host -> one      rejected(intent, reason)
## Messages that arrive before the match scene is ready are buffered.

signal roster_changed(roster: Array)
signal joined(seat: int)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal match_starting(config: Dictionary)
signal intent_rejected(intent: Dictionary, reason: String)

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT := 9080
const NODE_NAME := "NetSession"

var role: Role = Role.NONE
var local_seat: int = -1
var local_name: String = ""
## Host: [{seat, name, color_name, peer, token, connected}]. Clients get it without tokens.
var roster: Array = []
var match_config: Dictionary = {}
var in_match: bool = false
## Developer: keep the first offered cards instead of showing the draft screen (--bot).
var auto_draft: bool = false
## How the match scene is loaded once the host starts (tests load it in place).
var scene_loader: Callable

var _controller: MatchController
var _pending_events: Array = []
var _pending_private: Array = []
var _token: String = ""
var _rng := RandomNumberGenerator.new()

## The session under the scene-tree root, if any.
static func find(tree: SceneTree) -> NetSession:
	return tree.root.get_node_or_null(NODE_NAME) as NetSession

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
	multiplayer.connection_failed.connect(func(): _fail("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_online() -> bool:
	return role != Role.NONE

func is_host() -> bool:
	return role == Role.HOST

# --- HOSTING / JOINING ---
func host(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
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
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	local_name = player_name
	_token = token
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	local_seat = -1
	roster = []
	in_match = false
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
	_rpc_hello.rpc_id(1, local_name, _token)

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
	_rpc_roster.rpc(public_roster())
	roster_changed.emit(public_roster())

# --- LOBBY ---
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(player_name: String, token: String) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var entry: Dictionary = {}
	for existing in roster:
		if token != "" and existing["token"] == token:
			entry = existing # reclaiming a seat
	if entry.is_empty():
		if in_match:
			_rpc_refused.rpc_id(peer_id, "The match has already started.")
			return
		if roster.size() >= GameConfig.MAX_PLAYERS:
			_rpc_refused.rpc_id(peer_id, "The room is full.")
			return
		entry = {"seat": roster.size(), "name": player_name.strip_edges().left(16),
			"color_name": _free_color(), "token": _new_token()}
		if entry["name"] == "":
			entry["name"] = "Player %d" % (entry["seat"] + 1)
		roster.append(entry)
	entry["peer"] = peer_id
	entry["connected"] = true
	_rpc_welcome.rpc_id(peer_id, entry["seat"], entry["token"])
	_broadcast_roster()
	if in_match:
		pass # rejoin mid-match: snapshot sync arrives in phase 5

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(seat: int, token: String) -> void:
	local_seat = seat
	_token = token
	joined.emit(seat)

@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: String) -> void:
	_fail(reason)

@rpc("authority", "call_remote", "reliable")
func _rpc_roster(list: Array) -> void:
	roster = list
	roster_changed.emit(roster)

# --- MATCH START ---
## Host: everyone loads the match with the current roster.
func start_match(cards_enabled: bool) -> void:
	if not is_host() or roster.size() < GameConfig.MIN_PLAYERS:
		return
	var players: Array = roster.map(func(entry): return {"name": entry["name"], "color_name": entry["color_name"]})
	var config := {"players": players, "cards": cards_enabled}
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
	if seat < 0:
		return
	_controller.submit_remote(PlayerIntent.from_dict(intent), seat)

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

func _peer_of_seat(seat: int) -> int:
	for entry in roster:
		if entry["seat"] == seat and entry["connected"]:
			return entry["peer"]
	return 0
