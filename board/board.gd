class_name Board
extends Node2D

## scalable: We inject the data resource here. 
## This allows us to swap board layouts (5x5 vs 7x7) without changing this script.
@export var board_data: BoardData

# We will emit this when the board is ready so the Game Manager knows 
# it can start placing pieces.
signal board_ready

func _ready() -> void:
	if not board_data:
		push_error("Board: No BoardData resource assigned!")
		return
	
	board_ready.emit()

## Returns the global position for a piece to move to.
func get_square_position(index: int) -> Vector2:
	if index >= 0 and index < board_data.square_coordinates.size():
		# The resource data is local, so we might need to convert to global
		# if the board itself moves. For now, we assume local.
		print(board_data.square_coordinates[index],
		to_global(board_data.square_coordinates[index]))
		return to_global(board_data.square_coordinates[index])
	
	push_warning("Board: Requested invalid square index %d" % index)
	return Vector2.ZERO
