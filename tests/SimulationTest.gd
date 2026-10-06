extends Node
class_name SimulationTest

## Must be the full game scene: GameManager alone has no board, button or pawns wired.
const GAME_SCENE_PATH = "res://MainGame.tscn"

var game_instance: GameManager
var match_running: bool = false
var turn_count: int = 0
var max_turns: int = 2000 # Safety limit to prevent infinite loops (like a stalemate)
## --cards: draft random hands and play a random legal card (random targets) half the time.
var use_cards: bool = false
var card_manager: CardManager
var roll_button: Button

func _ready() -> void:
	print("========================================")
	print("  STARTING AUTOMATED TEST SIMULATION ")
	print("========================================")
	
	_run_simulation()

func _run_simulation() -> void:
	# 0. Player count from the command line: godot ... -- --players=3
	var player_count := GameConfig.MIN_PLAYERS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="):
			player_count = clampi(int(arg.get_slice("=", 1)), GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS)
		elif arg == "--cards":
			use_cards = true
	print("Players: %d%s" % [player_count, " (with cards)" if use_cards else ""])
	
	# 1. Load and Instantiate the Main Game Scene
	var packed_scene = load(GAME_SCENE_PATH)
	if not packed_scene:
		push_error("TEST FAILED: Could not load %s" % GAME_SCENE_PATH)
		get_tree().quit(1)
		return

	var main_scene: Node = packed_scene.instantiate()
	MatchSetup.make(GameConfig.default_players(player_count), use_cards).apply_to(main_scene)
	roll_button = (main_scene.get_node("HUD") as HUD).roll_button
	if use_cards:
		card_manager = main_scene.get_node("CardManager")
		card_manager.auto_draft = true
	add_child(main_scene)
	game_instance = main_scene.get_node("GameManager") as GameManager
	if not game_instance:
		push_error("TEST FAILED: MainGame.tscn has no GameManager node")
		get_tree().quit(1)
		return
	
	# 2. Hook into the newly implemented win condition signal
	game_instance.game_over.connect(_on_game_over)
	
	match_running = true
	turn_count = 0
	
	# Wait a frame to ensure the game has run its _ready() function
	await get_tree().process_frame
	
	# 3. Main Simulation Loop
	while match_running and turn_count < max_turns:
		# A small delay so state transitions and tweens have time to process
		# You can adjust this to 0.0 if you want lightning-fast logic tests, 
		# but tweens (like move_along_path) might need actual time to resolve properly.
		await get_tree().create_timer(0.05).timeout 
		
		# Act based on the Game's current state
		match game_instance.current_state:
			GameManager.GameState.WAITING_FOR_ROLL:
				if not _simulate_card():
					_simulate_roll()
			GameManager.GameState.PLAYING_CARD:
				if use_cards and card_manager.is_targeting():
					card_manager.controller.choose_target(card_manager.get_target_candidates().pick_random())
			GameManager.GameState.SELECTING_PIECE:
				_simulate_piece_selection()
				
	if turn_count >= max_turns:
		push_error("TEST FAILED: Simulation hit turn limit! Possible infinite loop or stalemate.")
		_print_board_state()
		get_tree().quit(1)

func _print_board_state() -> void:
	print("has_killed: ", game_instance.player_has_killed)
	for i in game_instance.pawn_containers.size():
		for p in game_instance.pawn_containers[i].get_children():
			if p is Pawn:
				var path: Array[int] = game_instance._get_path(p)
				print("P%d %s: tile %d (path step %d)" % [i + 1, p.name, p.current_tile_index, path.find(p.current_tile_index)])

func _simulate_roll() -> void:
	# Emulate a UI click on the roll button
	if not roll_button.disabled:
		turn_count += 1
		# Directly emitting 'pressed' simulates a button click perfectly
		roll_button.pressed.emit()
		
## Half the time, play a random playable card. Returns true if one was started.
func _simulate_card() -> bool:
	if not use_cards or not card_manager.can_play_now() or randf() < 0.5:
		return false
	var player := game_instance.current_player_index
	var playable := card_manager.get_playable_cards(player)
	if playable.is_empty():
		return false
	return card_manager.controller.play_card(card_manager.hands[player][playable.pick_random()].id)

func _simulate_piece_selection() -> void:
	# The pawns the rules allow for the selected throw (the ones the board highlights)
	var movable_pawns := game_instance.get_movable_pawns(game_instance.current_roll)
	if movable_pawns.is_empty():
		return # Shouldn't happen in this state, but safe to check
		
	# Randomly pick a valid pawn (Simulates a chaotic AI or random player)
	var chosen_pawn = movable_pawns.pick_random()
	
	# Simulate a Mouse Click directly into the Pawn's input handler.
	# This bypasses the Physics2D server picking raycasts, making it 100% reliable for headless/fast tests.
	var mock_event = InputEventMouseButton.new()
	mock_event.button_index = MOUSE_BUTTON_LEFT
	mock_event.pressed = true
	
	# Call the pawn's internal input event handler exactly as Godot's CollisionObject2D would.
	chosen_pawn._on_input_event(get_viewport(), mock_event, 0)
	
func _on_game_over(winner_id: int) -> void:
	match_running = false
	print("\n========================================")
	print("       SIMULATION CONCLUDED ")
	print("========================================")
	print("Winner: %s (player index %d)" % [game_instance.get_player_name(winner_id), winner_id])
	print("Total Actions Simulated: %d" % turn_count)
	if use_cards:
		print("Cards played: %d" % card_manager.cards_played)
	
	# Validation Step: Double check the state of the board matches a win state.
	var is_valid_win = true
	var home_index = game_instance.board.board_data.home_index
	
	for p in game_instance.pawn_containers[winner_id].get_children():
		if p is Pawn and p.current_tile_index != home_index:
			is_valid_win = false
			print("Validation Error: Pawn %s is at %d, not Home (%d)" % [p.name, p.current_tile_index, home_index])
			
	if is_valid_win:
		print("✅ TEST PASSED: Win condition mathematically validated.")
		get_tree().quit(0) # Exit with success code
	else:
		push_error("❌ TEST FAILED: Game ended but not all pawns are at home!")
		get_tree().quit(1) # Exit with error code
