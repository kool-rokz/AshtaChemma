class_name WebSocketTransport
extends Transport

## Players connect over WebSocket: the host listens on a port (desktop builds), others
## join by address ("192.168.1.5:9080"), URL, or a Tunnel room code (wss://).

const DEFAULT_PORT := 9080
## Seconds a WebSocket handshake may take (a fresh tunnel can be slow).
const HANDSHAKE_TIMEOUT := 15.0

## Browsers can't accept connections.
func can_host() -> bool:
	return not Platform.is_web()

func open_server(multiplayer: MultiplayerAPI, port: int) -> Error:
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

func open_client(multiplayer: MultiplayerAPI, target: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = HANDSHAKE_TIMEOUT
	var err := peer.create_client(target)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

## "192.168.1.5:9080" -> "ws://192.168.1.5:9080"; a bare host gets the default port;
## a room code -> its tunnel's wss:// URL; ws:// and wss:// URLs pass through.
func to_target(address: String) -> String:
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

## A whole invite ("Join my game! Room code: x-y-z") or a link ("...index.html?room=x-y-z")
## gives the room code; anything else is kept.
func find_address(text: String) -> String:
	var t := text.strip_edges()
	if " " in t or "room=" in t:
		for word in t.replace("\n", " ").replace("\t", " ").split(" ", false):
			var candidate: String = word.get_slice("room=", 1) if "room=" in word else word
			candidate = candidate.get_slice("&", 0).trim_prefix("(").trim_suffix(")").trim_suffix(",").trim_suffix(".")
			if Tunnel.is_room_code(candidate):
				return candidate
	return t
