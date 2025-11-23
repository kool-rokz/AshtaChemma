@tool
extends Node

## Automates the creation of Board Coordinates AND Movement Paths.
## Currently configured for a standard 5x5 Ashta Chamma spiral.

@export_group("Configuration")
@export var target_resource: BoardData
@export var tile_size := Vector2(64, 64)
@export var grid_origin := Vector2(32, 32)
@export var rows_cols := Vector2i(5, 5)

@export_group("Actions")
@export var generate_all_data: bool = false:
	set(value):
		if value:
			_run_generation()
			generate_all_data = false

func _run_generation() -> void:
	if not target_resource:
		push_error("No Target Resource assigned!")
		return
	
	print("--- Starting Board Data Generation ---")
	
	# 1. Generate Coordinates
	_generate_grid_coordinates()
	
	# 2. Generate Paths (Specific to 5x5 Ashta Chamma)
	if rows_cols == Vector2i(5,5):
		_generate_5x5_paths()
	else:
		push_warning("Path generation currently only supports 5x5. Coordinates generated, but paths skipped.")
	
	# 3. Save
	ResourceSaver.save(target_resource, target_resource.resource_path)
	print("--- Generation Complete. Resource Saved. ---")

func _generate_grid_coordinates() -> void:
	var new_coords: Array[Vector2] = []
	for y in range(rows_cols.y):
		for x in range(rows_cols.x):
			var x_pos = grid_origin.x + (x * tile_size.x)
			var y_pos = grid_origin.y + (y * tile_size.y)
			new_coords.append(Vector2(x_pos, y_pos))
	
	target_resource.square_coordinates = new_coords
	print("Generated %d grid coordinates." % new_coords.size())

func _generate_5x5_paths() -> void:
	# In a 5x5 grid, indices are 0-24. 
	# Center is 12.
	# We map (x,y) to index using: index = x + (y * 5)
	
	# --- PLAYER 1 (Starts Bottom Center, goes Right/Anti-Clockwise) ---
	# Outer Ring
	var p1: Array[int] = []
	p1.append_array(_get_indices_from_coords([
		[2,4], [3,4], [4,4], # Bottom Right Corner
		[4,3], [4,2], [4,1], [4,0], # Right Side up to Top Right
		[3,0], [2,0], [1,0], [0,0], # Top Side to Top Left
		[0,1], [0,2], [0,3], [0,4], # Left Side to Bottom Left
		[1,4] # Bottom Left to Start
	]))
	# Inner Ring (Enters from bottom [2,4] -> [2,3])
	# Clockwise inside
	p1.append_array(_get_indices_from_coords([
		[1,3], [1,2], [1,1], # Left Inner
		[2,1], [3,1], # Top Inner
		[3,2], [3,3], # Right Inner
		[2,3]  # Bottom Inner (Entrance to Home)
	]))
	# Home
	p1.append(12)
	
	# --- PLAYER 2 (Starts Top Center, goes Left/Anti-Clockwise) ---
	# Note: In Ashta Chamma, everyone moves Anti-Clockwise on outer, Clockwise on inner.
	# They just start at different spots.
	var p2: Array[int] = []
	p2.append_array(_get_indices_from_coords([
		[2,0], [1,0], [0,0], # Top Side to Top Left
		[0,1], [0,2], [0,3], [0,4], # Left Side to Bottom Left
		[1,4], [2,4], [3,4], [4,4], # Bottom Side to Bottom Right
		[4,3], [4,2], [4,1], [4,0], # Right Side to Top Right
		[3,0] # Top Right to Start
	]))
	# Inner Ring (Enters from top [2,0] -> [2,1])
	p2.append_array(_get_indices_from_coords([
		[3,1], # Top Inner Right
		[3,2], [3,3], # Right Inner
		[2,3], # Bottom Inner
		[1,3], [1,2], [1,1], # Left Inner
		[2,1] # Top Inner (Entrance to Home)
	]))
	# Home
	p2.append(12)

	target_resource.p1_path = p1
	target_resource.p2_path = p2
	target_resource.home_index = 12
	
	# Define safe squares (Cross pattern usually)
	target_resource.safe_squares = _get_indices_from_coords([
		[2,0], [0,2], [2,2], [4,2], [2,4]
	])
	
	print("Generated P1 Path (%d steps) and P2 Path (%d steps)." % [p1.size(), p2.size()])

# Helper to convert simplified [x,y] coordinates to grid indices
func _get_indices_from_coords(coords: Array) -> Array[int]:
	var indices: Array[int] = []
	for c in coords:
		var idx = c[0] + (c[1] * rows_cols.x)
		indices.append(idx)
	return indices
