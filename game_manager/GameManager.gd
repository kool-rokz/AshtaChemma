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
## A pawn was returned to its homebase by something other than a capture (e.g. a command).
signal pawn_sent_home(pawn: Pawn, from_tile: int)
signal pawns_swapped(a: Pawn, b: Pawn)
## The "skip_turn" rule hook made this player miss their turn.
signal turn_skipped(player_id: int)
signal inner_ring_unlocked(player_id: int)
signal pawn_reached_home(pawn: Pawn, pawns_home: int)
signal bonus_turn(player_id: int, reason: String)
## Emitted when the hovered move preview changes; empty Dictionary = cleared.
## Keys: pawn, tiles (Array[int]), end (TileHighlighter.PreviewEnd), victim (Pawn or null).
signal move_preview_changed(info: Dictionary)
## Every GameCommand applied through apply_command(), after it took effect.
signal command_applied(command: GameCommand)
## State was replaced by load_snapshot() (rejoin); UIs should redraw from scratch.
signal snapshot_loaded
signal game_over(winner_id: int)

enum GameState {
	TURN_START,
	WAITING_FOR_ROLL,
	SELECTING_PIECE,
	MOVING,
	## An outside system (e.g. cards) is resolving actions before the throw; input locked.
	PLAYING_CARD,
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

## Rule queries (see RuleHooks). The default changes nothing; an outside system
## (the card system) installs its own via set_rules().
var rules: RuleHooks = RuleHooks.new()
## Awaited in order before the first turn (e.g. the card draft).
var pre_game_tasks: Array[Callable] = []

## Set from hud.roll_button; kept as a field so tests can press it.
var roll_button: Button

## One {"name", "color_name"} entry per player (from GameConfig).
var players: Array[Dictionary] = []
## Board side each player sits at (see BoardData.get_seat_path).
var player_seats: Array[int] = []
## One Node2D of Pawns per player, index = team_id.
var pawn_containers: Array[Node] = []

var current_player_index: int = 0
## Online: the seat this copy plays (set by MatchController). -1 = offline, every seat local.
## Only affects what this screen offers (Throw button, highlights), never the rules.
var local_seat: int = -1
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
## Values the next throws will land on, instead of throwing the shells.
var _forced_throws: Array[int] = []
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
			_forced_throws.clear()
			_clear_highlights()
			_update_board_markers()
			turn_changed.emit(current_player_index)
			_emit_pool()
			set_state(GameState.WAITING_FOR_ROLL)

		GameState.WAITING_FOR_ROLL:
			roll_button.disabled = not is_local_turn()

		GameState.SELECTING_PIECE, GameState.MOVING, GameState.PLAYING_CARD:
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

	# 2. Wire input (MatchController turns button presses and clicks into intents)
	roll_button = hud.roll_button
	roll_button.disabled = true
	board.tile_hovered.connect(_on_tile_hovered)
	board.rules = rules
	hud.bind(self)

	# 3. Start game safely (after any setup other systems registered, like a draft)
	await get_tree().process_frame
	for task in pre_game_tasks:
		await task.call()
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

## Replace the rule hooks (for both this manager and the board's safe-square check).
func set_rules(new_rules: RuleHooks) -> void:
	rules = new_rules
	board.rules = new_rules

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

func get_all_pawns() -> Array[Pawn]:
	var result: Array[Pawn] = []
	for container in pawn_containers:
		for child in container.get_children():
			if child is Pawn:
				result.append(child)
	return result

## Stable id for a pawn: [player, index within that player's pawns].
func get_pawn_ref(pawn: Pawn) -> Array:
	return [pawn.team_id, pawn.get_index()]

func get_pawn_by_ref(ref: Array) -> Pawn:
	if ref.size() != 2 or ref[0] < 0 or ref[0] >= pawn_containers.size():
		return null
	var container: Node = pawn_containers[ref[0]]
	if ref[1] < 0 or ref[1] >= container.get_child_count():
		return null
	return container.get_child(ref[1]) as Pawn

## Is it this screen's turn to act (always true offline)?
func is_local_turn() -> bool:
	return local_seat < 0 or local_seat == current_player_index

## True when waiting for player input (not animating or between turns).
func is_settled() -> bool:
	return _game_finished or current_state in [GameState.WAITING_FOR_ROLL, GameState.SELECTING_PIECE]

# --- SNAPSHOT (rejoin, autosave, desync checks) ---
## Full game state as plain data. Only meaningful while settled (see is_settled).
func to_snapshot() -> Dictionary:
	var pawn_tiles: Array = []
	for container in pawn_containers:
		var tiles: Array = []
		for p in container.get_children():
			tiles.append(p.current_tile_index)
		pawn_tiles.append(tiles)
	return {
		"current_player": current_player_index,
		"state": GameState.keys()[current_state],
		"unlocked": Array(player_has_killed),
		"pawns": pawn_tiles,
		"pool": Array(throw_pool),
		"exhausted": Array(exhausted_throws),
		"selected": selected_throw,
		"bonus_chain": _bonus_chain,
		"extra_throw_pending": _extra_throw_pending,
		"forced_throws": Array(_forced_throws),
		"finished": _game_finished,
	}

## Restores a snapshot taken by to_snapshot() on another copy of this match.
func load_snapshot(snap: Dictionary) -> void:
	current_player_index = int(snap["current_player"])
	player_has_killed.assign(Array(snap["unlocked"]).map(func(v): return bool(v)))
	var pawn_tiles: Array = snap["pawns"]
	for i in pawn_containers.size():
		for j in pawn_containers[i].get_child_count():
			pawn_containers[i].get_child(j).current_tile_index = int(pawn_tiles[i][j])
	throw_pool.assign(Array(snap["pool"]).map(func(v): return int(v)))
	exhausted_throws.assign(Array(snap["exhausted"]).map(func(v): return int(v)))
	selected_throw = int(snap["selected"])
	_bonus_chain = int(snap["bonus_chain"])
	_extra_throw_pending = bool(snap["extra_throw_pending"])
	_forced_throws.assign(Array(snap["forced_throws"]).map(func(v): return int(v)))
	_game_finished = bool(snap["finished"])

	var n := board.board_data.get_grid_size()
	for tile in n * n:
		_layout_tile(tile)
	_clear_highlights()
	_update_board_markers()
	snapshot_loaded.emit()
	if _game_finished:
		return
	if GameState.get(snap["state"], -1) == GameState.SELECTING_PIECE and not throw_pool.is_empty():
		set_state(GameState.SELECTING_PIECE)
		_apply_selection()
	else:
		_emit_pool()
		set_state(GameState.WAITING_FOR_ROLL)

## Short fingerprint of a snapshot; equal on every copy that's in sync.
static func hash_snapshot(snap: Dictionary) -> String:
	return JSON.stringify(snap, "", true).sha256_text().left(16)

## How far along its own path a pawn is (0 = homebase, 24 = home).
func get_path_step(pawn: Pawn) -> int:
	return _get_path(pawn).find(pawn.current_tile_index)

func is_outer_ring_tile(tile_index: int) -> bool:
	var step := board.board_data.get_seat_path(0).find(tile_index)
	return step >= 0 and step < OUTER_RING_STEPS

func is_unlocked(player_id: int) -> bool:
	return player_has_killed[player_id]

func is_game_finished() -> bool:
	return _game_finished

## Read-only legality check, also for moves that don't use a throw (commands).
func can_move_pawn(pawn: Pawn, steps: int, obey_rules: bool = true) -> bool:
	return _validate_move(pawn, steps, obey_rules)

# --- INPUT HANDLERS ---
## Throw now (offline/tests): generate + apply in one go.
func request_roll_dice() -> void:
	if current_state != GameState.WAITING_FOR_ROLL:
		push_warning("Roll ignored: Wrong state.")
		return
	_execute_roll(generate_shells())

## Authority only: how the next throw lands. A pending forced throw wins;
## otherwise the shells are thrown with the (rule-hooked) odds.
func generate_shells() -> Array[bool]:
	if not _forced_throws.is_empty():
		return CowryThrower.shells_for(_forced_throws.front())
	var odds: float = rules.modify(&"open_up_probability", open_up_probability, {"player": current_player_index})
	cowry_thrower.open_up_probability = clampf(odds, 0.0, 1.0)
	return cowry_thrower.throw()

## Every copy of the game: apply a throw decided by the authority.
func apply_throw(shells: Array[bool]) -> void:
	if current_state != GameState.WAITING_FOR_ROLL:
		push_warning("Throw ignored: Wrong state.")
		return
	_execute_roll(shells)

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

# --- COMMANDS (actions from outside the turn flow, e.g. cards) ---
## Lock input before the throw so another system can apply commands.
## Only allowed while the current player is waiting to throw.
func begin_card_play() -> bool:
	if current_state != GameState.WAITING_FOR_ROLL or _game_finished:
		return false
	_clear_preview()
	set_state(GameState.PLAYING_CARD)
	return true

## Hand control back to the current player (they still have to throw).
func end_card_play() -> void:
	if _game_finished or current_state != GameState.PLAYING_CARD:
		return
	_update_board_markers()
	_emit_pool()
	set_state(GameState.WAITING_FOR_ROLL)

## The single entry point for changing game state from outside. Every command
## runs the same code the normal turn flow uses (paths, captures, unlocks, win).
func apply_command(command: GameCommand) -> void:
	if _game_finished:
		return
	match command.kind:
		GameCommand.Kind.MOVE_PAWN:
			if not _validate_move(command.pawn, command.value, command.obey_rules):
				push_warning("Command ignored: %s can't move %d." % [command.pawn.name, command.value])
				return
			await _move_pawn(command.pawn, command.value, command.obey_rules)
			_finish_if_won(command.pawn.team_id)
		GameCommand.Kind.SEND_HOME:
			_send_pawn_home(command.pawn)
		GameCommand.Kind.SWAP_PAWNS:
			_swap_pawns(command.pawn, command.other_pawn)
		GameCommand.Kind.FORCE_THROW:
			_forced_throws.append(command.value)
		GameCommand.Kind.ADD_THROW:
			throw_pool.append(command.value)
			_emit_pool()
		GameCommand.Kind.GRANT_EXTRA_THROW:
			_extra_throw_pending = true
		GameCommand.Kind.UNLOCK_INNER:
			_unlock_inner_ring(command.player)
	command_applied.emit(command)

# --- ROLL LOGIC ---
## Throws accumulate: 4 or 8 adds to the pool and throws again; anything else
## closes the pool and the player spends it. Three 4/8s in a row forfeit everything.
func _execute_roll(shells: Array[bool]) -> void:
	if not _forced_throws.is_empty():
		# Same on every copy: the forced value is game state, not randomness
		shells = CowryThrower.shells_for(_forced_throws.pop_front())
	var value: int = rules.modify(&"throw_value", CowryThrower.score(shells), {"player": current_player_index})
	if value != CowryThrower.score(shells):
		shells = CowryThrower.shells_for(value)
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
			p.set_highlighted(movable.has(p) and is_local_turn())
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

	await _move_pawn(pawn, steps)

	# Traditional rule: the last pawn home wins at once; leftover throws don't matter.
	if _finish_if_won(pawn.team_id):
		return

	_continue_spending()

## Shared by thrown moves and commands: animate along the path, then resolve the landing.
func _move_pawn(pawn: Pawn, steps: int, obey_rules: bool = true) -> void:
	var path := _get_path(pawn)
	var sequence := _get_step_sequence(pawn, steps, obey_rules)
	if sequence.is_empty():
		return
	var move_path: Array[Vector2] = []
	for idx in sequence:
		move_path.append(board.get_square_position(path[idx]))
	var final_index: int = path[sequence.back()]
	var from_index := pawn.current_tile_index

	pawn.current_tile_index = final_index

	# Animate (full size while travelling; stack layout re-applies on arrival)
	pawn.scale = Vector2.ONE
	_layout_tile(from_index)
	await pawn.move_along_path(move_path)

	pawn_moved.emit(pawn, from_index, final_index, sequence.size())
	_resolve_landing(pawn, final_index)

## Capture (the victim goes back to its homebase, unlocking the inner ring and
## earning an extra throw), reaching home, and the stack layout.
func _resolve_landing(pawn: Pawn, final_index: int) -> void:
	if not board.is_safe(final_index):
		var occupant = _get_pawn_at_tile_excluding(final_index, pawn)
		if occupant != null and occupant.team_id != pawn.team_id and _can_capture(pawn, occupant, final_index):
			var victim_home := get_homebase_tile(occupant.team_id)
			occupant.current_tile_index = victim_home
			_layout_tile(victim_home)
			pawn_captured.emit(pawn, occupant)
			_extra_throw_pending = true
			_unlock_inner_ring(pawn.team_id)

	if final_index == board.board_data.home_index:
		pawn_reached_home.emit(pawn, count_pawns_home(pawn.team_id))

	_layout_tile(final_index)

func _can_capture(attacker: Pawn, victim: Pawn, tile_index: int) -> bool:
	return rules.modify(&"can_capture", true, {
		"player": attacker.team_id, "pawn": victim, "victim_player": victim.team_id, "tile": tile_index})

func _unlock_inner_ring(player_id: int) -> void:
	if player_has_killed[player_id]:
		return
	player_has_killed[player_id] = true
	inner_ring_unlocked.emit(player_id)
	_update_board_markers()

func _send_pawn_home(pawn: Pawn) -> void:
	var from_index := pawn.current_tile_index
	var homebase := get_homebase_tile(pawn.team_id)
	if from_index == homebase:
		return
	pawn.current_tile_index = homebase
	_layout_tile(from_index)
	_layout_tile(homebase)
	pawn_sent_home.emit(pawn, from_index)

func _swap_pawns(a: Pawn, b: Pawn) -> void:
	var tile_a := a.current_tile_index
	a.current_tile_index = b.current_tile_index
	b.current_tile_index = tile_a
	_layout_tile(a.current_tile_index)
	_layout_tile(b.current_tile_index)
	pawns_swapped.emit(a, b)

## Ends the game if `player_id` has every pawn home. Returns true if it did.
func _finish_if_won(player_id: int) -> bool:
	if not _check_win_condition(player_id):
		return false
	_game_finished = true
	_clear_highlights()
	print("GAME OVER! %s wins!" % get_player_name(player_id))
	game_over.emit(player_id)
	return true

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
	current_player_index = _next_player_after(current_player_index)
	set_state(GameState.TURN_START)

## The next player in seat order, skipping anyone the "skip_turn" rule says sits out.
func _next_player_after(player_id: int) -> int:
	var next := player_id
	for i in players.size():
		next = (next + 1) % players.size()
		if not rules.modify(&"skip_turn", false, {"player": next}):
			return next
		turn_skipped.emit(next)
	return (player_id + 1) % players.size()

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
		if occupant != null and occupant.team_id != pawn.team_id and _can_capture(pawn, occupant, final_tile):
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
## obey_rules = false lets a command move a locked pawn inward anyway.
func _get_step_sequence(pawn: Pawn, steps: int, obey_rules: bool = true) -> Array[int]:
	steps = rules.modify(&"move_steps", steps, {"player": pawn.team_id, "pawn": pawn})
	if steps <= 0:
		return []
	var path := _get_path(pawn)
	var current_idx := path.find(pawn.current_tile_index)
	if current_idx == path.size() - 1:
		return [] # Already home
	var locked: bool = obey_rules and not player_has_killed[pawn.team_id]
	var sequence: Array[int] = []

	for i in range(1, steps + 1):
		var next_idx := current_idx + i
		if locked:
			next_idx %= OUTER_RING_STEPS
		elif next_idx >= path.size():
			return [] # Exact roll required to reach home
		sequence.append(next_idx)
	return sequence

func _validate_move(pawn: Pawn, steps: int = current_roll, obey_rules: bool = true) -> bool:
	var sequence := _get_step_sequence(pawn, steps, obey_rules)
	if sequence.is_empty():
		return false

	var target_tile: int = _get_path(pawn)[sequence.back()]

	# Occupancy / Stacking Rule
	if not board.is_safe(target_tile):
		var occupant = _get_pawn_at_tile_excluding(target_tile, pawn)
		if occupant != null:
			if occupant.team_id == pawn.team_id and obey_rules:
				return false # Cannot stack own pieces on non-safe tiles
			if occupant.team_id != pawn.team_id and not _can_capture(pawn, occupant, target_tile):
				return false # Protected pawn: can't be captured, so the square is blocked

	return true

func _get_pawn_at_tile_excluding(tile_index: int, exclude_pawn: Pawn = null) -> Pawn:
	for container in pawn_containers:
		for child in container.get_children():
			if child is Pawn and child != exclude_pawn and child.current_tile_index == tile_index:
				return child
	return null
