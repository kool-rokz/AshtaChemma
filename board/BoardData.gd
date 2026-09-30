class_name BoardData
extends Resource

## The global position of the center of each square, ordered by ID.
@export var square_coordinates: Array[Vector2]

## The sequence of tile INDICES that the bottom seat follows.
## Example: [22, 23, 24, ... 12]
## Every other seat's path is this one rotated around the centre (see get_seat_path).
@export var p1_path: Array[int]

## The sequence of tile INDICES that the top seat follows.
## Kept for reference; equals get_seat_path(2) (verified by tests/BoardPathTest.gd).
@export var p2_path: Array[int]

## The index of the square that is the "Home/Center".
@export var home_index: int = 12

## Safe zones where pieces cannot be cut (Optional, for future use)
@export var safe_squares: Array[int]

var _seat_path_cache: Dictionary = {}

## Grid width/height (board is square).
func get_grid_size() -> int:
	return int(round(sqrt(square_coordinates.size())))

## Path for a board side: 0 = bottom (p1_path), 1 = right, 2 = top, 3 = left.
## Each seat is p1_path turned one more quarter turn, which keeps everyone moving
## counter-clockwise on the outer ring and clockwise on the inner ring.
func get_seat_path(seat: int) -> Array[int]:
	if _seat_path_cache.has(seat):
		return _seat_path_cache[seat]
	var n := get_grid_size()
	var path: Array[int] = []
	for tile in p1_path:
		var cell := Vector2i(tile % n, tile / n)
		for i in seat % 4:
			cell = rotate_cell(cell, n)
		path.append(cell.x + cell.y * n)
	_seat_path_cache[seat] = path
	return path

## Quarter turn that carries the bottom side to the right side: (x, y) -> (y, n-1-x).
static func rotate_cell(cell: Vector2i, n: int) -> Vector2i:
	return Vector2i(cell.y, n - 1 - cell.x)
