# game_manager/GameManager.gd

class_name GameManager
extends Node

signal turn_changed(player_id: int)
signal roll_result(value: int)
signal shells_thrown(shells: Array[bool])
## The current turn's throws: pool = still usable, exhausted = discarded this turn,
## selected = index into pool driving highlights/preview (-1 = none).
signal throw_pool_changed(pool: Array[int], exhausted: Array[int], selected: int)
signal valid_moves_highlighted(pawns: Array[Pawn])
## Throws discarded because no pawn could use any of them.
signal throws_exhausted(player_id: int, values: Array[int])
## Three 4/8 throws in a row: the whole pool is lost.
signal turn_forfeited(player_id: int, values: Array[int])
signal pawn_moved(pawn: Pawn, from_tile: int, to_tile: int, steps: int)
signal pawn_captured(attacker: Pawn, victim: Pawn)
signal inner_ring_unlocked(player_id: int)
signal pawn_reached_home(pawn: Pawn, pawns_home: int)
signal bonus_turn(player_id: int, reason: String)
## Emitted when the hovered move preview changes; empty Dictionary = cleared.
## Keys: pawn, tiles (Array[int]), end (TileHighlighter.PreviewEnd), victim (Pawn or null).
signal move_preview_changed(info: Dictionary)
signal game_over(winner_id: int)

enum GameState {
	TURN_START,
	WAITING_FOR_ROLL,
	SELECTING_PIECE,
	MOVING
}

var current_state: GameState = GameState.TURN_START

# --- DATA & REFS ---
@export_group("References")
@export var board: Board
@export var hud: HUD
## Parent node for the per-player pawn containers spawned at runtime.
@export var pawns_root: Node2D

@export_group("Cowry Shells")
## Chance a single shell lands open side up. 0.5 = fair shells.
@export_range(0.0, 1.0, 0.01) var open_up_probability: float = 0.5
## 0 = random each game; any other value replays the same throws (useful for tests).
@export var rng_seed: int = 0

const PAWN_SCENE_PATH := "res://pawn/Pawn.tscn"
## Throws of 4 (chamma) and 8 (ashta) earn another throw before moving.
const BONUS_THROWS: Array[int] = [4, 8]
## Throwing a bonus value this many times in a row forfeits the whole pool.
const MAX_BONUS_CHAIN := 3
## Pause so players can read "exhausted"/"forfeited" before the turn passes.
const TURN_PASS_DELAY := 1.2

## Swap for a physics-based thrower later; scoring stays in CowryThrower.score().
var cowry_thrower: CowryThrower

## Set from hud.roll_button; kept as a field so tests can press it.
var roll_button: Button

## One {"name", "color_name"} entry per player (from GameConfig).
var players: Array[Dictionary] = []
## Board side each player sits at (see BoardData.get_seat_path).
var player_seats: Array[int] = []
## One Node2D of Pawns per player, index = team_id.
var pawn_containers: Array[Node] = []

var current_player_index: int = 0
## The throw value being applied (the selected pool entry); used by move validation.
var current_roll: int = 0
## Path steps 0..15 are the outer ring; 16+ is the inner spiral ending at home.
const OUTER_RING_STEPS := 16
## Visual layout for several pawns sharing a tile (tile is 64px).
const STACK_SPREAD := 14.0
const STACK_SCALE := 0.55
const CROWD_SPREAD := 19.0
const CROWD_SCALE := 0.4

var player_has_killed: Array[bool] = []

# --- THROW POOL (per turn) ---
var throw_pool: Array[int] = []
var exhausted_throws: Array[int] = []
var selected_throw: int = -1
var _bonus_chain: int = 0
## A capture earns one more throw once the current pool is spent.
var _extra_throw_pending: bool = false
var _game_finished: bool = false

var _hovered_pawn: Pawn = null
var _hovered_tile: int = -1

# --- OPTIMIZED STATE MANAGEMENT ---
func set_state(new_state: GameState) -> void:
	current_state = new_state

	match new_state:
		GameState.TURN_START:
			throw_pool.clear()
			exhausted_throws.clear()
			selected_throw = -1
			_bonus_chain = 0
			_extra_throw_pending = false
			_clear_highlights()
			_update_board_markers()
			turn_changed.emit(current_player_index)
			_emit_pool()
			set_state(GameState.WAITING_FOR_ROLL)

		GameState.WAITING_FOR_ROLL:
			roll_button.disabled = false

		GameState.SELECTING_PIECE:
			roll_button.disabled = true

		GameState.MOVING:
			roll_button.disabled = true


# --- READY & INITIALIZATION ---
func _ready() -> void:
	# 1. Safety Check
	if not board or not hud or not pawns_root:
		push_error("GameManager: Missing references!")
		return

	if not cowry_thrower:
		cowry_thrower = RandomCowryThrower.new(open_up_probability, rng_seed)

	_spawn_players(GameConfig.get_players())

	# 2. Wire input
	roll_button = hud.roll_button
	roll_button.pressed.connect(request_roll_dice)
	roll_button.disabled = true
	board.tile_hovered.connect(_on_tile_hovered)
	hud.bind(self)

	# 3. Start game safely
	await get_tree().process_frame
	start_game()

## Every player's pawns start stacked on their homebase (their side's entry square).
func _spawn_players(config: Array[Dictionary]) -> void:
	players = config
	player_seats.assign(GameConfig.seats_for(players.size()))
	player_has_killed.resize(players.size())
	player_has_killed.fill(false)

	var pawn_scene: PackedScene = load(PAWN_SCENE_PATH)
	var homebases: Array[Dictionary] = []
	for i in players.size():
		var container := Node2D.new()
		container.name = "P%d_Pawns" % (i + 1)
		pawns_root.add_child(container)
		pawn_containers.append(container)

		var homebase := get_homebase_tile(i)
		homebases.append({"tile": homebase, "color": get_player_color(i)})
		for j in GameConfig.PAWNS_PER_PLAYER:
			var pawn: Pawn = pawn_scene.instantiate()
			pawn.name = "Pawn%d" % (j + 1)
			pawn.team_id = i
			pawn.team_color = get_player_color(i)
			container.add_child(pawn)
			pawn.current_tile_index = homebase
			pawn.hovered.connect(_on_pawn_hovered)
			pawn.unhovered.connect(_on_pawn_unhovered)
		_layout_tile(homebase)
	board.highlighter.set_homebases(homebases)

# --- GAME LOGIC ---
func start_game() -> void:
	print("--- GAME START (%d players) ---" % players.size())
	current_player_index = 0
	player_has_killed.fill(false)
	_game_finished = false
	set_state(GameState.TURN_START)

func get_player_name(player_id: int) -> String:
	return players[player_id]["name"]

func get_player_color(player_id: int) -> Color:
	return GameConfig.color_of(players[player_id])

## A player's homebase: the first square of their path (a safe square on their side).
func get_homebase_tile(player_id: int) -> int:
	return board.board_data.get_seat_path(player_seats[player_id])[0]

## Player whose homebase is `tile_index`, or -1.
func get_homebase_owner(tile_index: int) -> int:
	for i in players.size():
		if get_homebase_tile(i) == tile_index:
			return i
	return -1

func count_pawns_home(player_id: int) -> int:
	var home := 0
	for p in pawn_containers[player_id].get_children():
		if p is Pawn and p.current_tile_index == board.board_data.home_index:
			home += 1
	return home

func get_pawns_at_tile(tile_index: int) -> Array[Pawn]:
	var result: Array[Pawn] = []
	for container in pawn_containers:
		for child in container.get_children():
			if child is Pawn and child.current_tile_index == tile_index:
				result.append(child)
	return result

# --- INPUT HANDLERS ---
func request_roll_dice() -> void:
	if current_state != GameState.WAITING_FOR_ROLL:
		push_warning("Roll ignored: Wrong state.")
		return
	_execute_roll()

## Choose which pooled throw to spend next (from the HUD chips).
func select_throw(index: int) -> void:
	if current_state != GameState.SELECTING_PIECE:
		return
	if index < 0 or index >= throw_pool.size() or not _is_throw_usable(throw_pool[index]):
		return
	selected_throw = index
	_apply_selection()

func request_select_pawn(pawn: Pawn) -> void:
	if current_state != GameState.SELECTING_PIECE:
		return

	if pawn.team_id != current_player_index:
		push_warning("Selection ignored: Wrong team.")
		return

	if not _validate_move(pawn):
		push_warning("Selection ignored: Invalid move.")
		return

	_execute_move(pawn)

# --- ROLL LOGIC ---
## Throws accumulate: 4 or 8 adds to the pool and throws again; anything else
## closes the pool and the player spends it. Three 4/8s in a row forfeit everything.
func _execute_roll() -> void:
	var shells := cowry_thrower.throw()
	var value := CowryThrower.score(shells)
	current_roll = value
	throw_pool.append(value)
	shells_thrown.emit(shells)
	roll_result.emit(value)

	if value in BONUS_THROWS:
		_bonus_chain += 1
		if _bonus_chain >= MAX_BONUS_CHAIN:
			var lost := throw_pool.duplicate()
			exhausted_throws.append_array(lost)
			throw_pool.clear()
			_emit_pool()
			turn_forfeited.emit(current_player_index, lost)
			await _pass_turn_after_pause()
			return
		_emit_pool()
		set_state(GameState.WAITING_FOR_ROLL) # throw again before moving
		return

	_bonus_chain = 0
	_continue_spending()

## After the pool changes: pick a usable throw, or exhaust the rest and move on.
func _continue_spending() -> void:
	if not throw_pool.is_empty() and not _any_throw_usable():
		var values := throw_pool.duplicate()
		exhausted_throws.append_array(values)
		throw_pool.clear()
		selected_throw = -1
		_emit_pool()
		throws_exhausted.emit(current_player_index, values)
		# Fall through to the empty-pool handling below

	if throw_pool.is_empty():
		_clear_highlights()
		if _extra_throw_pending:
			_extra_throw_pending = false
			_bonus_chain = 0
			_emit_pool()
			bonus_turn.emit(current_player_index, "captured a pawn")
			set_state(GameState.WAITING_FOR_ROLL)
		else:
			await _pass_turn_after_pause()
		return

	if selected_throw < 0 or selected_throw >= throw_pool.size() or not _is_throw_usable(throw_pool[selected_throw]):
		selected_throw = _first_usable_throw()
	set_state(GameState.SELECTING_PIECE)
	_apply_selection()

func _apply_selection() -> void:
	current_roll = throw_pool[selected_throw]
	var movable := _get_movable_pawns(current_roll)
	for p in pawn_containers[current_player_index].get_children():
		if p is Pawn:
			p.set_highlighted(movable.has(p))
	valid_moves_highlighted.emit(movable)
	_emit_pool()
	_refresh_preview()

func _is_throw_usable(value: int) -> bool:
	return not _get_movable_pawns(value).is_empty()

func _any_throw_usable() -> bool:
	for value in throw_pool:
		if _is_throw_usable(value):
			return true
	return false

func _first_usable_throw() -> int:
	for i in throw_pool.size():
		if _is_throw_usable(throw_pool[i]):
			return i
	return -1

func _emit_pool() -> void:
	throw_pool_changed.emit(throw_pool, exhausted_throws, selected_throw)

# --- MOVE LOGIC ---
func _execute_move(pawn: Pawn) -> void:
	set_state(GameState.MOVING)
	_clear_preview()
	_clear_highlights()

	var steps: int = throw_pool[selected_throw]
	throw_pool.remove_at(selected_throw)
	current_roll = steps
	_emit_pool()

	var move_path = _calculate_path_coordinates(pawn, steps)
	var final_index = _calculate_final_index(pawn, steps)
	var from_index = pawn.current_tile_index

	pawn.current_tile_index = final_index

	# Animate (full size while travelling; stack layout re-applies on arrival)
	pawn.scale = Vector2.ONE
	_layout_tile(from_index)
	await pawn.move_along_path(move_path)

	pawn_moved.emit(pawn, from_index, final_index, steps)

	# Combat Check: the captured pawn goes back to its homebase
	if not board.is_safe(final_index):
		var occupant = _get_pawn_at_tile_excluding(final_index, pawn)
		if occupant != null and occupant.team_id != pawn.team_id:
			var victim_home := get_homebase_tile(occupant.team_id)
			occupant.current_tile_index = victim_home
			_layout_tile(victim_home)
			pawn_captured.emit(pawn, occupant)
			_extra_throw_pending = true
			if not player_has_killed[pawn.team_id]:
				player_has_killed[pawn.team_id] = true
				inner_ring_unlocked.emit(pawn.team_id)
				_update_board_markers()

	if final_index == board.board_data.home_index:
		pawn_reached_home.emit(pawn, count_pawns_home(pawn.team_id))

	_layout_tile(final_index)

	# Traditional rule: the last pawn home wins at once; leftover throws don't matter.
	if _check_win_condition(current_player_index):
		_game_finished = true
		_clear_highlights()
		print("GAME OVER! %s wins!" % get_player_name(current_player_index))
		game_over.emit(current_player_index)
		return

	_continue_spending()

## Arranges every pawn on `tile_index` so stacked pawns (homebases, safe squares, home)
## stay visible and clickable: one pawn sits centred at full size, several
## are shrunk and spread in a small circle around the tile centre.
func _layout_tile(tile_index: int) -> void:
	if tile_index < 0:
		return
	var occupants := get_pawns_at_tile(tile_index)

	var center := board.get_square_position(tile_index)
	if occupants.size() == 1:
		occupants[0].global_position = center
		occupants[0].scale = Vector2.ONE
		return
	var crowded := occupants.size() > 4
	for i in occupants.size():
		var angle := TAU * i / occupants.size() - PI / 4.0
		occupants[i].global_position = center + Vector2.from_angle(angle) * (CROWD_SPREAD if crowded else STACK_SPREAD)
		occupants[i].scale = Vector2.ONE * (CROWD_SCALE if crowded else STACK_SCALE)

# --- TURN ENDING ---
func _pass_turn_after_pause() -> void:
	set_state(GameState.MOVING) # lock input while players read what happened
	await get_tree().create_timer(TURN_PASS_DELAY).timeout
	if _game_finished:
		return
	current_player_index = (current_player_index + 1) % players.size()
	set_state(GameState.TURN_START)

func _check_win_condition(player_id: int) -> bool:
	return count_pawns_home(player_id) == pawn_containers[player_id].get_child_count()

func _clear_highlights() -> void:
	for container in pawn_containers:
		for p in container.get_children():
			if p is Pawn:
				p.set_highlighted(false)

## Homebase glow + inner-ring entry arrow for whoever is playing now.
func _update_board_markers() -> void:
	var path := board.board_data.get_seat_path(player_seats[current_player_index])
	board.highlighter.set_active_player(
		get_homebase_tile(current_player_index),
		path[OUTER_RING_STEPS - 1],
		path[OUTER_RING_STEPS],
		get_player_color(current_player_index),
		player_has_killed[current_player_index])

# --- MOVE PREVIEW (hover) ---
## What moving `pawn` by the selected throw would do, or {} if it isn't a legal choice now.
func get_move_preview(pawn: Pawn) -> Dictionary:
	if pawn == null or current_state != GameState.SELECTING_PIECE:
		return {}
	if pawn.team_id != current_player_index or not pawn.is_highlighted:
		return {}
	var path := _get_path(pawn)
	var tiles: Array[int] = []
	for step in _get_step_sequence(pawn, current_roll):
		tiles.append(path[step])
	if tiles.is_empty():
		return {}

	var final_tile: int = tiles.back()
	var victim: Pawn = null
	if not board.is_safe(final_tile):
		var occupant = _get_pawn_at_tile_excluding(final_tile, pawn)
		if occupant != null and occupant.team_id != pawn.team_id:
			victim = occupant

	var end := TileHighlighter.PreviewEnd.NORMAL
	if final_tile == board.board_data.home_index:
		end = TileHighlighter.PreviewEnd.HOME
	elif victim:
		end = TileHighlighter.PreviewEnd.CAPTURE
	elif board.is_safe(final_tile):
		end = TileHighlighter.PreviewEnd.SAFE
	return {"pawn": pawn, "tiles": tiles, "end": end, "victim": victim}

func _on_pawn_hovered(pawn: Pawn) -> void:
	_hovered_pawn = pawn
	_refresh_preview()

func _on_pawn_unhovered(pawn: Pawn) -> void:
	if _hovered_pawn == pawn:
		_hovered_pawn = null
		_refresh_preview()

func _on_tile_hovered(tile_index: int) -> void:
	_hovered_tile = tile_index
	_refresh_preview()

## Preview for the hovered pawn, else for a movable pawn of the current player on the hovered tile.
func _refresh_preview() -> void:
	var info := get_move_preview(_hovered_pawn)
	if info.is_empty() and _hovered_tile >= 0:
		for p in get_pawns_at_tile(_hovered_tile):
			info = get_move_preview(p)
			if not info.is_empty():
				break
	if info.is_empty():
		_clear_preview()
		return
	board.highlighter.show_move_preview(info["tiles"], info["end"])
	move_preview_changed.emit(info)

func _clear_preview() -> void:
	board.highlighter.clear_move_preview()
	move_preview_changed.emit({})

# --- HELPERS (Optimized) ---
func _get_movable_pawns(roll: int) -> Array[Pawn]:
	var valid: Array[Pawn] = []
	var container = pawn_containers[current_player_index]

	# Fast check: empty container?
	if not container or container.get_child_count() == 0:
		push_warning("No pawns for Player %d." % current_player_index)
		return []

	for child in container.get_children():
		if child is Pawn and _validate_move(child, roll):
			valid.append(child)
	return valid

func _get_path(pawn: Pawn) -> Array[int]:
	return board.board_data.get_seat_path(player_seats[pawn.team_id])

## Returns every path step the pawn passes through for `steps` moves, ending on the
## destination, or an empty array if the move is impossible (already home, or it
## overshoots home: an exact throw is required).
## Unlock Rule: until its player has killed, a pawn keeps circling the outer ring
## (step OUTER_RING_STEPS - 1 wraps back to step 0, its homebase) instead of turning inward.
func _get_step_sequence(pawn: Pawn, steps: int) -> Array[int]:
	var path := _get_path(pawn)
	var current_idx := path.find(pawn.current_tile_index)
	if current_idx == path.size() - 1:
		return [] # Already home
	var locked: bool = not player_has_killed[pawn.team_id]
	var sequence: Array[int] = []

	for i in range(1, steps + 1):
		var next_idx := current_idx + i
		if locked:
			next_idx %= OUTER_RING_STEPS
		elif next_idx >= path.size():
			return [] # Exact roll required to reach home
		sequence.append(next_idx)
	return sequence

func _validate_move(pawn: Pawn, steps: int = current_roll) -> bool:
	var sequence := _get_step_sequence(pawn, steps)
	if sequence.is_empty():
		return false

	var target_tile: int = _get_path(pawn)[sequence.back()]

	# Occupancy / Stacking Rule
	if not board.is_safe(target_tile):
		var occupant = _get_pawn_at_tile_excluding(target_tile, pawn)
		if occupant != null and occupant.team_id == pawn.team_id:
			return false # Cannot stack own pieces on non-safe tiles

	return true

func _calculate_path_coordinates(pawn: Pawn, steps: int) -> Array[Vector2]:
	var coords: Array[Vector2] = []
	var path := _get_path(pawn)
	for idx in _get_step_sequence(pawn, steps):
		coords.append(board.get_square_position(path[idx]))
	return coords

func _calculate_final_index(pawn: Pawn, steps: int) -> int:
	var sequence := _get_step_sequence(pawn, steps)
	if sequence.is_empty():
		return pawn.current_tile_index
	return _get_path(pawn)[sequence.back()]

func _get_pawn_at_tile_excluding(tile_index: int, exclude_pawn: Pawn = null) -> Pawn:
	for container in pawn_containers:
		for child in container.get_children():
			if child is Pawn and child != exclude_pawn and child.current_tile_index == tile_index:
				return child
	return null
