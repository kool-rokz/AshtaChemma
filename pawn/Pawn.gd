class_name Pawn
extends Area2D

signal hovered(pawn: Pawn)
signal unhovered(pawn: Pawn)
signal clicked(pawn: Pawn)

## Index of the owning player (0..player count - 1).
@export var team_id: int = 0

## Tint applied to the (white) pawn sprite.
@export var team_color: Color = Color.WHITE

## The logical index of the square this pawn currently occupies (0-24).
var current_tile_index: int = -1

## Pulsing ring: a choice for this screen's player (a legal move, or a card target).
var is_highlighted: bool = false

## White so it reads against every team colour (including green).
const HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0)
const HIGHLIGHT_RADIUS := 30.0
const STATUS_RADIUS := 24.0

## Ring showing a lasting effect on this pawn (e.g. a shield); alpha 0 = none.
var status_color: Color = Color(0, 0, 0, 0)

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# Connect the built-in input event signal to ourselves
	input_event.connect(_on_input_event)
	mouse_entered.connect(func(): hovered.emit(self))
	mouse_exited.connect(func(): unhovered.emit(self))

	# Dynamically resize the collision shape to match the sprite size
	# This fixes issues where the default CircleShape2D radius (10px) is too small to click easily.
	var shape_node = $CollisionShape2D
	if shape_node and sprite.texture:
		var radius = max(sprite.texture.get_width(), sprite.texture.get_height()) / 2.0
		var new_shape = CircleShape2D.new()
		new_shape.radius = radius
		shape_node.shape = new_shape

	set_team(team_id, team_color)
	set_process(false)

func set_highlighted(on: bool) -> void:
	is_highlighted = on
	set_process(on) # _process only drives the pulse animation
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func set_status_color(color: Color) -> void:
	if color == status_color:
		return
	status_color = color
	queue_redraw()

func _draw() -> void:
	if status_color.a > 0.0:
		draw_arc(Vector2.ZERO, STATUS_RADIUS, 0.0, TAU, 40, status_color, 5.0, true)
	if not is_highlighted:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
	var color := HIGHLIGHT_COLOR
	color.a = lerpf(0.45, 1.0, pulse)
	draw_arc(Vector2.ZERO, HIGHLIGHT_RADIUS, 0.0, TAU, 48, color, 4.0, true)

func set_team(new_team_id: int, color: Color) -> void:
	team_id = new_team_id
	team_color = color
	if sprite:
		sprite.modulate = color


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
	
	# Block the caller until the whole sequence is done
	await tween.finished

# Clicks are only reported; MatchController decides what they mean (move or card target)
func _on_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
