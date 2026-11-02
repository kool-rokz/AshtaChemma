class_name Transport
extends RefCounted

## How players' games connect, for NetSession. NetSession only uses Godot's
## MultiplayerAPI once a peer is open, so another transport (WebRTC, a relay server, a
## console's online service) is a new subclass returned by Platform.transport().
## Addresses are whatever the player typed or pasted; each transport reads its own kind.

## Can this platform accept connections (host a game)?
func can_host() -> bool:
	return false

## Host: start listening; sets multiplayer.multiplayer_peer on success.
func open_server(_multiplayer: MultiplayerAPI, _port: int) -> Error:
	return ERR_UNAVAILABLE

## Client: connect to `target` (from to_target()); sets multiplayer.multiplayer_peer.
func open_client(_multiplayer: MultiplayerAPI, _target: String) -> Error:
	return ERR_UNAVAILABLE

## What a player typed -> something open_client() can connect to ("" = nothing usable).
func to_target(_address: String) -> String:
	return ""

## The address inside pasted text (a whole invite message or link), else the text.
func find_address(text: String) -> String:
	return text.strip_edges()
