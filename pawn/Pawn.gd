class_name Pawn
extends Area2D

signal pawn_clicked(pawn_instance: Pawn)
signal movement_finished

## 0 for Player 1, 1 for Player 2.
@export var team_id: int = 0

## The logical index of the square this pawn currently occupies (0-24).
var current_tile_index: int = -1

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# Connect the built-in input event signal to ourselves
	input_event.connect(_on_input_event)

func set_team(new_team_id: int) -> void:
	team_id = new_team_id
	if team_id == 0:
		sprite.modulate = Color.TOMATO # Reddish
	else:
		sprite.modulate = Color.CORNFLOWER_BLUE # Blueish


func place_at(position_vec: Vector2, tile_index: int) -> void:
	global_position = position_vec
	current_tile_index = tile_index


func move_along_path(path_coordinates: Array[Vector2]) -> void:
	if path_coordinates.is_empty():
		return
	
	# Create a Tween to animate the position property
	var tween = create_tween()
	
	for target_pos in path_coordinates:
		# Tween to the next square over 0.3 seconds
		tween.tween_property(self, "global_position", target_pos, 0.3)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		
		# Optional: Add a tiny "jump" effect (scale up and down)
		tween.parallel().tween_property(sprite, "scale", Vector2(1.2, 1.2), 0.15)
		tween.parallel().tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.15).set_delay(0.15)
	
	# When the whole sequence is done, emit a signal
	tween.finished.connect(func(): movement_finished.emit())

# Handle clicks
func _on_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Scalable: Find the manager and request selection
		var manager = get_tree().current_scene.find_child("GameManager")
		if manager:
			manager.request_select_pawn(self)
