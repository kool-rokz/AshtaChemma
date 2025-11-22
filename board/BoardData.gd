class_name BoardData
extends Resource

## The global position of the center of each square, ordered by ID (0 to 24).
## We use an Array of Vector2 so we can support non-grid shapes (like the cross) easily.
@export var square_coordinates: Array[Vector2]

## The path pieces must follow. Each integer refers to an index in 'square_coordinates'.
## Player 1 might follow path [0, 1, 2...] while Player 2 follows [6, 7, 8...]
@export var p1_path: Array[int]
@export var p2_path: Array[int]

## The index of the square that is the "Home/Center".
@export var home_index: int = 12
