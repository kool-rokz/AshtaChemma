class_name Board
extends Node2D

## scalable: We inject the data resource here.
## This allows us to swap board layouts (5x5 vs 7x7) without changing this script.
@export var board_data: BoardData

# We will emit this when the board is ready so the Game Manager knows
# it can start placing pieces.
signal board_ready

## Mouse moved onto a different tile (-1 = off the board).
signal tile_hovered(tile_index: int)

var highlighter: TileHighlighter
var _hovered_tile: int = -1

func _ready() -> void:
	if not board_data:
		push_error("Board: No BoardData resource assigned!")
		return

	highlighter = TileHighlighter.new()
	highlighter.name = "TileHighlighter"
	highlighter.board = self
	add_child(highlighter)

	board_ready.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var tile := get_tile_at(get_global_mouse_position())
		if tile != _hovered_tile:
			_hovered_tile = tile
			highlighter.hovered_tile = tile
			tile_hovered.emit(tile)

## Returns the global position for a piece to move to.
func get_square_position(index: int) -> Vector2:
	if index >= 0 and index < board_data.square_coordinates.size():
		# The resource data is in board-local space; convert to global
		return to_global(board_data.square_coordinates[index])

	push_warning("Board: Requested invalid square index %d" % index)
	return Vector2.ZERO

func get_tile_size() -> float:
	return board_data.square_coordinates[1].x - board_data.square_coordinates[0].x

## Board width/height in local pixels.
func get_extent() -> float:
	return get_tile_size() * board_data.get_grid_size()

## Tile index under a global position, or -1 if outside the board.
func get_tile_at(global_pos: Vector2) -> int:
	var local := to_local(global_pos)
	var extent := get_extent()
	if local.x < 0 or local.y < 0 or local.x >= extent or local.y >= extent:
		return -1
	var tile_size := get_tile_size()
	var n := board_data.get_grid_size()
	return int(local.x / tile_size) + int(local.y / tile_size) * n

func is_safe(tile_index: int) -> bool:
	return tile_index in board_data.safe_squares
