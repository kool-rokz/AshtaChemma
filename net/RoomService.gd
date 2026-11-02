class_name RoomService
extends Node

## Gives a hosted game a short room code that friends can join with, for NetSession.
## Today the Cloudflare quick tunnel (Tunnel, desktop only); a relay or a console's
## matchmaking would be another subclass, returned by Platform.room_service().

signal status_changed(text: String)
## live = true once a real connection got through; false if it couldn't be confirmed yet.
signal opened(room_code: String, live: bool)
signal failed(reason: String)

## Start giving the server on `port` a code. Emits opened(code, live) or failed(reason).
func open(_port: int) -> void:
	failed.emit("Room codes aren't available here.")

func close() -> void:
	pass
