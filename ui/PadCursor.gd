class_name PadCursor
extends Node

## Board choices without a pointer (keyboard, gamepad, Joy-Con): steps through what
## this screen may pick right now (the ringed pawns, or a card's target squares) with
## pick_prev / pick_next, and picks with pick_confirm. It reports exactly like a pointer
## does (Pawn.point / press, Board.point_at / press_tile), so the move preview, the
## board view and MatchController treat it the same as a mouse. Created by the HUD.
## A view only: what can be picked comes from the highlights other views already set.

var _gm: GameManager
var _focus_pawn: Pawn
var _focus_tile: int = -1

func bind(gm: GameManager) -> void:
	_gm = gm
	gm.movable_pawns_changed.connect(func(_pawns): _refocus.call_deferred())
	gm.board.highlighter.changed.connect(_on_highlights_changed)
	var input := GameInput.find(get_tree())
	if input:
		input.changed.connect(func(_device): _refocus.call_deferred())

## What may be picked now: highlighted pawns (movable, or a card's pawn targets), else
## a card's target squares. Pawns in board order, so stepping is predictable.
func _choices() -> Array:
	var pawns: Array = _gm.get_all_pawns().filter(func(p: Pawn): return p.is_highlighted)
	if not pawns.is_empty():
		pawns.sort_custom(func(a: Pawn, b: Pawn): return a.current_tile_index < b.current_tile_index \
			or (a.current_tile_index == b.current_tile_index and a.get_instance_id() < b.get_instance_id()))
		return pawns
	var tiles: Array = _gm.board.highlighter.state()["target_tiles"]
	tiles.sort()
	return tiles

func _focused() -> Variant:
	return _focus_pawn if _focus_pawn else (_focus_tile if _focus_tile >= 0 else null)

func _on_highlights_changed() -> void:
	# A card's targets appearing or going: keep the focus on something still pickable
	var current: Variant = _focused()
	if current != null and not _choices().has(current):
		_refocus.call_deferred()
	elif current == null and GameInput.is_focus_driven() and not _choices().is_empty():
		_refocus.call_deferred()

## Pad/keyboard players get the first choice focused (and previewed) straight away.
func _refocus() -> void:
	var choices := _choices()
	var current: Variant = _focused()
	if not GameInput.is_focus_driven() or choices.is_empty():
		_set_focus(null)
	elif current == null or not choices.has(current):
		_set_focus(choices[0])

func _set_focus(choice: Variant) -> void:
	if _focus_pawn and is_instance_valid(_focus_pawn):
		_focus_pawn.point(false)
	_focus_pawn = choice as Pawn if choice is Pawn else null
	_focus_tile = int(choice) if choice is int else -1
	if _focus_pawn:
		_focus_pawn.point(true)
		_gm.board.point_at(_focus_pawn.current_tile_index)
	else:
		_gm.board.point_at(_focus_tile)

func _unhandled_input(event: InputEvent) -> void:
	if _gm == null:
		return
	var step := 0
	if event.is_action_pressed("pick_next", true):
		step = 1
	elif event.is_action_pressed("pick_prev", true):
		step = -1
	elif event.is_action_pressed("pick_confirm"):
		var current: Variant = _focused()
		if current == null:
			return
		get_viewport().set_input_as_handled()
		if current is Pawn:
			(current as Pawn).press()
		else:
			_gm.board.press_tile(int(current))
		_refocus.call_deferred()
		return
	if step == 0:
		return
	var choices := _choices()
	if choices.is_empty():
		return
	get_viewport().set_input_as_handled()
	var at := choices.find(_focused())
	_set_focus(choices[wrapi(at + step, 0, choices.size()) if at >= 0 else 0])
