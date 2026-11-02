class_name ThrowGesture
extends RefCounted

## How a player threw the shells: where the hand was, how hard and which way it let go,
## how much it shook, and which way up each shell lay in the hand at that moment.
## Travels inside the THROW intent and event as plain data (to_dict / from_dict).
## The look of a throw comes from it on every screen; the rules only use it for the
## lobby's "skill throws" keep chance (see GameManager.generate_shells).

const SHELL_COUNT := 4
## Where a hand may be, on the board plane in board units (one square = 1, the board's
## centre at 0,0, +y towards the bottom seat), the same on every screen whichever side
## it's viewed from. The board itself is -2.5..2.5; the rest is the mud around it.
const AREA := Rect2(-4.5, -4.5, 9, 9)

## A click (and bots): a default gentle toss from the player's own spot, never any keep chance.
var quick: bool = true
## Hand position at release on the board plane (see AREA).
var origin: Vector2 = Vector2.ZERO
## Release direction on the board plane (unit length) and strength 0..1.
var direction: Vector2 = Vector2.ZERO
var power: float = 0.35
## How much the shells were shaken before release, 0..1.
var shaken: float = 0.0
## Per shell: true = lying open side up in the hand at release.
var faces: Array[bool] = [false, false, false, false]
## Visual variety (spin, spread). The same seed gives the same look everywhere.
var seed_value: int = 0

static func quick_toss() -> ThrowGesture:
	return ThrowGesture.new()

func to_dict() -> Dictionary:
	return {"quick": quick, "origin": [origin.x, origin.y], "direction": [direction.x, direction.y],
		"power": power, "shaken": shaken, "faces": Array(faces), "seed": seed_value}

## Accepts anything (it may come from another player): every field is checked and
## clamped, and anything malformed falls back to a quick toss's value.
static func from_dict(d: Variant) -> ThrowGesture:
	var g := ThrowGesture.new()
	if not d is Dictionary:
		return g
	g.quick = d.get("quick", true) == true
	g.origin = _vec(d.get("origin"), Vector2.ZERO).clamp(AREA.position, AREA.end)
	var dir := _vec(d.get("direction"), Vector2.ZERO)
	g.direction = dir.normalized() if dir.length() > 0.001 else Vector2.ZERO
	g.power = clampf(_num(d.get("power"), 0.35), 0.0, 1.0)
	g.shaken = clampf(_num(d.get("shaken"), 0.0), 0.0, 1.0)
	var faces_in: Variant = d.get("faces")
	if faces_in is Array and faces_in.size() == SHELL_COUNT:
		for i in SHELL_COUNT:
			g.faces[i] = faces_in[i] == true
	var seed_in: Variant = d.get("seed")
	g.seed_value = int(seed_in) if seed_in is int or seed_in is float else 0
	return g

static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(_num(value[0], fallback.x), _num(value[1], fallback.y))
	return fallback
