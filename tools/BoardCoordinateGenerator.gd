@tool
extends Node

## A temporary tool script to generate grid coordinates for a BoardData resource.
## Instructions:
## 1. Assign your target BoardData.tres resource to the 'target_resource' field.
## 2. Adjust tile_size and grid_origin to match your visual board art.
## 3. Click the 'generate_trigger' checkbox in the Inspector to run the script.

@export_group("Configuration")
## The resource file you want to save data into.
@export var target_resource: BoardData

## How big is one square tile in pixels?
@export var tile_size := Vector2(64, 64)

## Where is the top-left corner of the very first square (index 0)?
## If your board sprite starts at (0,0), setting the origin to half a tile size
## will center the coordinate point in the square.
@export var grid_origin := Vector2(32, 32)

## How many rows and columns? (Standard Ashta Chamma is often 5x5 or 7x7)
@export var rows_cols := Vector2i(5, 5)

@export_group("Actions")
## Click this checkbox to execute the generation code. It will automatically uncheck.
@export var generate_trigger: bool = false:
	set(value):
		if value == true:
			_generate_coordinates()
			generate_trigger = false # Reset the checkbox

# This function runs only when you click the checkbox in the Inspector.
func _generate_coordinates() -> void:
	if target_resource == null:
		push_error("Generator Tool: No Target Resource assigned!")
		return

	print("Attempting to generate board coordinates...")
	
	var new_coords: Array[Vector2] = []
	
	# Standard double loop for grid generation
	# y is rows, x is columns
	for y in range(rows_cols.y):
		for x in range(rows_cols.x):
			# Calculate position based on origin + offset
			# This calculates the CENTER of each tile
			var x_pos = grid_origin.x + (x * tile_size.x)
			var y_pos = grid_origin.y + (y * tile_size.y)
			new_coords.append(Vector2(x_pos, y_pos))
			
	# Assign the generated array to the resource
	target_resource.square_coordinates = new_coords
	
	# Force Godot to save the resource file to disk so changes persist.
	# This is a crucial step for @tool scripts modifying resources.
	var error = ResourceSaver.save(target_resource, target_resource.resource_path)
	if error != OK:
		push_error("Failed to save resource! Error code: %s" % error)
		return
	
	print("Success! Generated %d coordinates into resource: %s" % [new_coords.size(), target_resource.resource_path])
	print("Indices 0-4 represent the top row, 5-9 the second row, etc.")
