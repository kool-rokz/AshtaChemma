class_name BoardData
extends Resource

## The global position of the center of each square, ordered by ID.
@export var square_coordinates: Array[Vector2]

## The sequence of tile INDICES that Player 1 (Red/Bottom) follows.
## Example: [22, 23, 24, ... 12]
@export var p1_path: Array[int]

## The sequence of tile INDICES that Player 2 (Blue/Top) follows.
@export var p2_path: Array[int]

## The index of the square that is the "Home/Center".
@export var home_index: int = 12

## Safe zones where pieces cannot be cut (Optional, for future use)
@export var safe_squares: Array[int]
