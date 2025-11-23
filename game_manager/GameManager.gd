class_name GameManager
extends Node

signal turn_changed(player_id: int)
signal roll_result(value: int)
signal valid_moves_highlighted(pawns: Array[Pawn])
signal game_over(winner_id: int)

enum GameState { TURN_START, WAITING_FOR_ROLL, SELECTING_PIECE, MOVING }
var current_state: GameState = GameState.TURN_START

# --- DATA & REFS ---
@export_group("References")
@export var board: Board
## Drag your UI Button here in the Inspector
@export var roll_button: Button 
## Drag P1_Pawns (Node2D) and P2_Pawns (Node2D) here. Order matters! (Index 0 = P1, Index 1 = P2)
@export var pawn_containers: Array[Node] 

var current_player_index: int = 0 
var current_roll: int = 0
const VALID_ROLLS = [1, 2, 3, 4, 8] 

func _ready() -> void:
# 1. Safety Check
	if not board or not roll_button or pawn_containers.size() < 2:
		push_error("GameManager: Missing references! Check Inspector.")
		return
		
	# 2. Wire the button
	roll_button.pressed.connect(request_roll_dice)
	roll_button.disabled = true # <--- FIX: Lock button immediately so you can't click it too early
	print("GameManager: Roll Button connected successfully.")

	# 3. START GAME SAFELY
	# Instead of awaiting a custom signal, we wait for the end of the current frame.
	# This ensures all nodes (Board, Pawns) have finished their _ready() calls.
	await get_tree().process_frame
	start_game()

func start_game() -> void:
	print("--- GAME START ---")
	current_player_index = 0
	_change_state(GameState.TURN_START)

func _change_state(new_state: GameState) -> void:
	current_state = new_state
	
	match current_state:
		GameState.TURN_START:
			print("State: TURN_START | Player %d" % current_player_index)
			turn_changed.emit(current_player_index)
			# Disable button while we set up? No, we need it for the next state.
			_change_state(GameState.WAITING_FOR_ROLL)
			
		GameState.WAITING_FOR_ROLL:
			print("State: WAITING_FOR_ROLL | Waiting for input...")
			roll_button.disabled = false # Unlock button
			
		GameState.SELECTING_PIECE:
			print("State: SELECTING_PIECE | Click a highlighted pawn.")
			roll_button.disabled = true # Lock button
			
		GameState.MOVING:
			print("State: MOVING | Animating...")
			roll_button.disabled = true

# --- INPUT ---

func request_roll_dice() -> void:
	# Verification: Prevent rolling if we aren't waiting for it
	if current_state != GameState.WAITING_FOR_ROLL:
		print("Ignored Roll Request: Wrong State (%s)" % GameState.keys()[current_state])
		return
	
	_execute_roll()

func request_select_pawn(pawn: Pawn) -> void:
	if current_state != GameState.SELECTING_PIECE:
		return
	
	if pawn.team_id != current_player_index:
		print("Ignored Selection: Wrong Team")
		return

	# Double check move validity
	if not _validate_move(pawn):
		print("Ignored Selection: Invalid Move")
		return
	
	_execute_move(pawn)

# --- LOGIC ---

func _execute_roll() -> void:
	current_roll = VALID_ROLLS.pick_random()
	print(">>> ROLLED: %d <<<" % current_roll)
	roll_result.emit(current_roll)
	
	var movable_pawns = _get_movable_pawns(current_roll)
	
	if movable_pawns.is_empty():
		print("No valid moves! Skipping turn...")
		# Small delay so user sees the roll before turn switches
		await get_tree().create_timer(1.0).timeout
		_end_turn(false)
	else:
		# HIGHLIGHT LOGIC
		valid_moves_highlighted.emit(movable_pawns)
		# Highlight visually for prototype (Optional)
		for p in movable_pawns:
			p.modulate = Color.GREEN # temporary debug highlight
			
		_change_state(GameState.SELECTING_PIECE)

func _execute_move(pawn: Pawn) -> void:
	_change_state(GameState.MOVING)
	
	# Reset debug highlight
	for p in pawn_containers[current_player_index].get_children():
		p.modulate = Color.WHITE 
		# Reset to team color (simplified re-set)
		p.set_team(p.team_id)

	var move_path = _calculate_path_coordinates(pawn, current_roll)
	var final_index = _calculate_final_index(pawn, current_roll)
	
	# Update logical index
	pawn.current_tile_index = final_index
	
	# Animate
	await pawn.move_along_path(move_path)
	
	# Check Landing
	var bonus = (current_roll == 4 or current_roll == 8)
	# TODO: Add landing on enemy logic here
	
	_end_turn(bonus)

func _end_turn(bonus: bool) -> void:
	if bonus:
		print("Bonus Turn! Player %d goes again." % current_player_index)
	else:
		current_player_index = 1 - current_player_index
		
	_change_state(GameState.TURN_START)

# --- HELPERS ---

func _get_movable_pawns(_roll: int) -> Array[Pawn]:
	var valid: Array[Pawn] = []
	var container = pawn_containers[current_player_index]
	
	if container.get_child_count() == 0:
		push_error("No pawns found for Player %d! Did you add them to the container?" % current_player_index)
		return []
		
	for child in container.get_children():
		if child is Pawn:
			if _validate_move(child):
				valid.append(child)
	return valid

func _validate_move(pawn: Pawn) -> bool:
	# Prototype Logic: 
	# 1. Get the correct path
	var path = board.board_data.p1_path if pawn.team_id == 0 else board.board_data.p2_path
	
	# 2. Find current position in that path
	# Note: If pawn is off-board (-1), 'find' returns -1. 
	# -1 + roll is a valid index, so pieces CAN enter the board.
	var current_idx_in_path = path.find(pawn.current_tile_index)
	var target_idx_in_path = current_idx_in_path + current_roll
	
	# 3. Check if target is beyond the end of the path
	if target_idx_in_path >= path.size():
		return false
		
	return true

func _calculate_path_coordinates(pawn: Pawn, steps: int) -> Array[Vector2]:
	var coords: Array[Vector2] = []
	var path = board.board_data.p1_path if pawn.team_id == 0 else board.board_data.p2_path
	
	var current_idx = path.find(pawn.current_tile_index)
	
	for i in range(1, steps + 1):
		var next_idx = current_idx + i
		if next_idx < path.size():
			var board_index = path[next_idx]
			coords.append(board.get_square_position(board_index))
			
	return coords

func _calculate_final_index(pawn: Pawn, steps: int) -> int:
	var path = board.board_data.p1_path if pawn.team_id == 0 else board.board_data.p2_path
	var idx = path.find(pawn.current_tile_index) + steps
	if idx < path.size():
		return path[idx]
	return pawn.current_tile_index
