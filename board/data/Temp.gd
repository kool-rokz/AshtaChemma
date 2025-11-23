#extends Node2D
#
#@onready var board = $Board
#@onready var pawn = $Pawn
#
#func _ready():
	## Wait for board to generate
	#await get_tree().create_timer(0.5).timeout
	#
	## Test Move: Get coordinates for squares 0, 1, 2, 3
	#var path_points: Array[Vector2] = []
	#path_points.append(board.get_square_position(0))
	#path_points.append(board.get_square_position(1))
	#path_points.append(board.get_square_position(2))
	#
	#pawn.move_along_path(path_points)
