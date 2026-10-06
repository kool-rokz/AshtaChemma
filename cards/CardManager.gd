class_name CardManager
extends Node

## Owns everything about cards: the library, the draft, each player's hand, the
## per-turn limit, target picking, and active modifiers with their durations.
##
## It never edits game state directly. Two doors only:
##   - one-shot changes: effects build GameCommands -> GameManager.apply_command()
##   - lasting changes:  CardModifiers, answered through ModifierHooks when
##                       GameManager asks a rule question (GameManager.rules)
## It listens to GameManager's signals (turn_changed, roll_result, game_over) to
## open the play window and tick modifiers. GameManager never references cards.
##
## Unhook: untick "Play with cards" on the start screen (GameConfig.cards_enabled),
## or delete this node from MainGame.tscn.

signal hand_changed(player_id: int)
## A card left the hand and starts resolving. targets: Pawn / tile index / player id.
signal card_played(player_id: int, card: CardData, targets: Array)
signal card_resolved(player_id: int, card: CardData)
signal card_rejected(player_id: int, card: CardData, reason: String)
## Waiting for the player to pick `spec` from `candidates`.
signal targeting_started(player_id: int, card: CardData, spec: CardTarget, candidates: Array)
signal targeting_cancelled(player_id: int, card: CardData)
signal modifier_added(modifier: ActiveModifier)
signal modifier_expired(modifier: ActiveModifier)
## Opens at turn start, closes on the first throw.
signal play_window_changed(open: bool)

@export var game: GameManager
@export var rules_config: CardRulesConfig
## Skip the draft screens and keep the first offered cards (tests, simulations).
@export var auto_draft: bool = false

var library: Array[CardData] = []
## Per player: Array of CardData still in hand.
var hands: Array[Array] = []
var active_modifiers: Array[ActiveModifier] = []
## Total cards played this match (stats).
var cards_played: int = 0

var _played_this_turn: int = 0
var _window_open: bool = false
## While a card is being played: {player, card, hand_index, targets, candidates, resolving}
var _session: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _ui: CardHUD
## Set by MatchController; the card UI submits intents through it.
var controller: MatchController

func _ready() -> void:
	if not GameConfig.cards_enabled or game == null:
		queue_free()
		return
	if rules_config == null:
		rules_config = CardRulesConfig.new()
	library = CardLibrary.load_cards(rules_config.card_folder)
	if rules_config.rng_seed != 0:
		_rng.seed = rules_config.rng_seed
	else:
		_rng.randomize()
	for i in game.players.size():
		hands.append([])

	game.set_rules(ModifierHooks.new(self))
	game.turn_changed.connect(_on_turn_changed)
	game.roll_result.connect(_on_roll_result)
	game.game_over.connect(_on_game_over)

	_ui = CardHUD.new()
	_ui.name = "CardHUD"
	add_child(_ui)
	_ui.bind(self)

# --- DRAFT (run by MatchController, which decides who deals the offers) ---
## Cards a player keeps from their offer.
func get_keep_count(offer_size: int) -> int:
	return mini(rules_config.hand_size, offer_size)

## Authority only: a private weighted offer (no repeats; heavier cards show up more often).
func make_offer() -> Array:
	var pool := library.duplicate()
	var offer: Array = []
	while offer.size() < rules_config.offer_size and not pool.is_empty():
		var total := 0.0
		for card in pool:
			total += card.weight
		if total <= 0.0:
			break
		var roll := _rng.randf() * total
		for i in pool.size():
			roll -= pool[i].weight
			if roll <= 0.0 or i == pool.size() - 1:
				offer.append(pool[i])
				pool.remove_at(i)
				break
	return offer

## Lets a player pick from their offer on screen; returns the kept cards.
func pick_cards_on_screen(player: int, offer: Array) -> Array:
	return await _ui.run_draft(player, offer, get_keep_count(offer.size()))

## Hot-seat cover before the first turn.
func show_start_cover() -> void:
	await _ui.show_pass_cover(0, "Start the game")

## Replace a hand (draft result, tests, debugging).
func set_hand(player: int, cards: Array) -> void:
	hands[player] = cards.duplicate()
	hand_changed.emit(player)

func set_hand_by_ids(player: int, ids: Array) -> void:
	set_hand(player, ids.map(func(id): return find_card(id)))

func find_hand_index(player: int, card_id: StringName) -> int:
	for i in hands[player].size():
		if hands[player][i].id == card_id:
			return i
	return -1

func find_card(card_id: StringName) -> CardData:
	for card in library:
		if card.id == card_id:
			return card
	return null

# --- PLAYING ---
## Cards can be played by the current player before their first throw, up to cards_per_turn.
func can_play_now(player: int = -1) -> bool:
	if player < 0:
		player = game.current_player_index
	return _window_open and _session.is_empty() \
		and player == game.current_player_index \
		and _played_this_turn < rules_config.cards_per_turn \
		and game.current_state == GameManager.GameState.WAITING_FOR_ROLL \
		and not game.is_game_finished()

## Why a card can't be played right now ("" = it can).
func get_block_reason(player: int, hand_index: int) -> String:
	if game.is_game_finished():
		return "The game is over."
	if player != game.current_player_index:
		return "Not your turn."
	if not _window_open:
		return "Cards are played before your first throw."
	if _played_this_turn >= rules_config.cards_per_turn:
		return "Card limit for this turn reached."
	if not _session.is_empty() or game.current_state != GameManager.GameState.WAITING_FOR_ROLL:
		return "Busy."
	if not _has_valid_assignment(hands[player][hand_index], player, []):
		return "No valid target right now."
	return ""

func get_played_this_turn() -> int:
	return _played_this_turn

func is_play_window_open() -> bool:
	return _window_open

func get_playable_cards(player: int) -> Array[int]:
	var result: Array[int] = []
	for i in hands[player].size():
		if get_block_reason(player, i) == "":
			result.append(i)
	return result

## Start playing a card from the current player's hand. Returns false if not allowed.
func request_play(hand_index: int) -> bool:
	var player := game.current_player_index
	if hand_index < 0 or hand_index >= hands[player].size():
		return false
	var card: CardData = hands[player][hand_index]
	var reason := get_block_reason(player, hand_index)
	if reason != "":
		card_rejected.emit(player, card, reason)
		return false
	if not game.begin_card_play():
		card_rejected.emit(player, card, "Busy.")
		return false
	_session = {"player": player, "card": card, "hand_index": hand_index,
		"targets": [], "candidates": [], "resolving": false}
	_advance_targeting()
	return true

## Same, by card id (how intents name cards).
func request_play_card(card_id: StringName) -> bool:
	var index := find_hand_index(game.current_player_index, card_id)
	return index >= 0 and request_play(index)

func is_targeting() -> bool:
	return not _session.is_empty() and not _session["resolving"]

func get_target_candidates() -> Array:
	return _session.get("candidates", [])

func get_current_target_spec() -> CardTarget:
	if not is_targeting():
		return null
	var card: CardData = _session["card"]
	return card.targets[_session["targets"].size()]

## Pick a target for the card being played (from a click, a test or the simulation).
func choose_target(target: Variant) -> bool:
	if not is_targeting() or not target in _session["candidates"]:
		return false
	_session["targets"].append(target)
	_clear_target_highlights()
	_advance_targeting()
	return true

func cancel_targeting() -> void:
	if not is_targeting():
		return
	var player: int = _session["player"]
	var card: CardData = _session["card"]
	_session = {}
	_clear_target_highlights()
	game.end_card_play()
	targeting_cancelled.emit(player, card)

func _advance_targeting() -> void:
	var card: CardData = _session["card"]
	var player: int = _session["player"]
	var chosen: Array = _session["targets"]
	while chosen.size() < card.targets.size():
		var spec := card.targets[chosen.size()]
		if spec.kind == CardTarget.Kind.NEXT_OPPONENT:
			chosen.append(_next_opponent(player))
			continue
		var candidates := _valid_candidates(card, player, chosen)
		_session["candidates"] = candidates
		_show_target_highlights(spec, candidates)
		targeting_started.emit(player, card, spec, candidates)
		return
	_resolve()

func _resolve() -> void:
	_session["resolving"] = true
	_session["candidates"] = []
	var player: int = _session["player"]
	var card: CardData = _session["card"]
	var targets: Array = _session["targets"]
	hands[player].remove_at(_session["hand_index"])
	_played_this_turn += 1
	cards_played += 1
	hand_changed.emit(player)
	card_played.emit(player, card, targets)

	var ctx := _make_context(card, player, targets)
	for effect in card.effects:
		await effect.resolve(ctx)
		if game.is_game_finished():
			break

	_session = {}
	_refresh_markers()
	game.end_card_play()
	card_resolved.emit(player, card)

# --- TARGETS ---
func _make_context(card: CardData, player: int, targets: Array) -> CardContext:
	var ctx := CardContext.new()
	ctx.game = game
	ctx.card_manager = self
	ctx.card = card
	ctx.player = player
	ctx.targets = targets
	return ctx

func _next_opponent(player: int) -> int:
	return (player + 1) % game.players.size()

## Candidates for the next pick that still leave a way to finish the card.
func _valid_candidates(card: CardData, player: int, chosen: Array) -> Array:
	var spec := card.targets[chosen.size()]
	var result: Array = []
	for candidate in _raw_candidates(spec, player):
		if candidate in chosen:
			continue
		if _has_valid_assignment(card, player, chosen + [candidate]):
			result.append(candidate)
	return result

## True if `chosen` can be completed into a full, legal set of targets.
func _has_valid_assignment(card: CardData, player: int, chosen: Array) -> bool:
	var ctx := _make_context(card, player, chosen)
	for effect in card.effects:
		if not effect.can_apply(ctx):
			return false
	if chosen.size() == card.targets.size():
		return true
	var spec := card.targets[chosen.size()]
	if spec.kind == CardTarget.Kind.NEXT_OPPONENT:
		return _has_valid_assignment(card, player, chosen + [_next_opponent(player)])
	for candidate in _raw_candidates(spec, player):
		if not candidate in chosen and _has_valid_assignment(card, player, chosen + [candidate]):
			return true
	return false

## Everything the target's kind and filters allow, before effects have their say.
func _raw_candidates(spec: CardTarget, player: int) -> Array:
	var board := game.board
	var home := board.board_data.home_index
	var result: Array = []
	if spec.is_pawn():
		for pawn in game.get_all_pawns():
			var tile := pawn.current_tile_index
			if spec.kind == CardTarget.Kind.OWN_PAWN and pawn.team_id != player:
				continue
			if spec.kind == CardTarget.Kind.ENEMY_PAWN and pawn.team_id == player:
				continue
			if spec.exclude_finished and tile == home:
				continue
			if spec.exclude_homebase and tile == game.get_homebase_tile(pawn.team_id):
				continue
			if spec.exclude_safe and board.is_safe(tile):
				continue
			if spec.outer_ring_only and game.get_path_step(pawn) >= GameManager.OUTER_RING_STEPS:
				continue
			result.append(pawn)
	elif spec.kind == CardTarget.Kind.TILE:
		var n := board.board_data.get_grid_size()
		for tile in n * n:
			if spec.exclude_finished and tile == home:
				continue
			if spec.exclude_homebase and game.get_homebase_owner(tile) >= 0:
				continue
			if spec.exclude_safe and board.is_safe(tile):
				continue
			if spec.outer_ring_only and not game.is_outer_ring_tile(tile):
				continue
			if spec.empty_tiles_only and not game.get_pawns_at_tile(tile).is_empty():
				continue
			result.append(tile)
	return result

func _show_target_highlights(spec: CardTarget, candidates: Array) -> void:
	if spec.is_pawn():
		for pawn in candidates:
			pawn.set_highlighted(true)
	elif spec.kind == CardTarget.Kind.TILE:
		var tiles: Array[int] = []
		tiles.assign(candidates)
		game.board.highlighter.set_target_tiles(tiles)

func _clear_target_highlights() -> void:
	for pawn in game.get_all_pawns():
		pawn.set_highlighted(false)
	game.board.highlighter.set_target_tiles([])

## Target value (Pawn / tile / player) -> network-safe reference, and back.
func target_to_ref(target: Variant) -> Dictionary:
	if target is Pawn:
		return {"pawn": game.get_pawn_ref(target)}
	var spec := get_current_target_spec()
	if spec and spec.kind == CardTarget.Kind.TILE:
		return {"tile": target}
	return {"player": target}

func ref_to_target(ref: Dictionary) -> Variant:
	if ref.has("pawn"):
		return game.get_pawn_by_ref(ref["pawn"])
	if ref.has("tile"):
		return int(ref["tile"])
	return int(ref.get("player", -1))

# --- MODIFIERS ---
## Called by AddModifierEffect. TARGET_* scopes bind to card target `target_index`.
func add_modifier(data: CardModifier, ctx: CardContext, target_index: int) -> void:
	var active := ActiveModifier.new()
	active.data = data
	active.card = ctx.card
	active.owner = ctx.player
	active.turns_left = data.duration_turns
	for i in ctx.card.effects.size():
		var effect := ctx.card.effects[i]
		if effect is AddModifierEffect and effect.modifier == data:
			active.effect_index = i
	var target: Variant = ctx.target(target_index)
	if target is Pawn:
		active.target_pawn = target
		active.target_player = target.team_id
	elif target is int:
		if ctx.card.targets[target_index].kind == CardTarget.Kind.TILE:
			active.target_tile = target
		else:
			active.target_player = target
	active_modifiers.append(active)
	modifier_added.emit(active)
	_refresh_markers()

func get_modifiers_for_player(player: int) -> Array[ActiveModifier]:
	var result: Array[ActiveModifier] = []
	for active in active_modifiers:
		if active.target_player == player or (active.target_player < 0 and active.owner == player):
			result.append(active)
	return result

## Rings on affected pawns, tints on affected squares.
func _refresh_markers() -> void:
	var pawn_colors := {}
	var tiles := {}
	for active in active_modifiers:
		var color := active.data.marker_color
		if color.a <= 0.0:
			continue
		if active.target_pawn:
			pawn_colors[active.target_pawn] = color
		if active.target_tile >= 0:
			tiles[active.target_tile] = color
	for pawn in game.get_all_pawns():
		pawn.set_status_color(pawn_colors.get(pawn, Color(0, 0, 0, 0)))
	game.board.highlighter.set_marked_tiles(tiles)

# --- GAME EVENTS ---
## A player's turn starts: their modifiers count down, and their play window opens.
func _on_turn_changed(player: int) -> void:
	for active in active_modifiers.duplicate():
		if active.owner == player:
			active.turns_left -= 1
			if active.turns_left <= 0:
				active_modifiers.erase(active)
				modifier_expired.emit(active)
	_refresh_markers()
	_played_this_turn = 0
	_window_open = true
	play_window_changed.emit(true)

func _on_roll_result(_value: int) -> void:
	if _window_open:
		_window_open = false
		play_window_changed.emit(false)

func _on_game_over(_winner: int) -> void:
	_window_open = false
	if is_targeting():
		_session = {}
		_clear_target_highlights()
	play_window_changed.emit(false)

# --- SNAPSHOT (rejoin, autosave, desync checks) ---
## Card state as plain data. Taken between card plays (never mid-targeting).
func to_snapshot() -> Dictionary:
	var modifiers: Array = []
	for active in active_modifiers:
		modifiers.append({
			"card": String(active.card.id),
			"effect": active.effect_index,
			"owner": active.owner,
			"target_player": active.target_player,
			"target_pawn": game.get_pawn_ref(active.target_pawn) if active.target_pawn else [],
			"target_tile": active.target_tile,
			"turns_left": active.turns_left,
		})
	return {
		"hands": hands.map(func(hand): return hand.map(func(card): return String(card.id))),
		"played_this_turn": _played_this_turn,
		"window_open": _window_open,
		"cards_played": cards_played,
		"modifiers": modifiers,
	}

func load_snapshot(snap: Dictionary) -> void:
	_session = {}
	_clear_target_highlights()
	var saved_hands: Array = snap["hands"]
	for player in saved_hands.size():
		hands[player] = Array(saved_hands[player]).map(func(id): return find_card(StringName(id)))
	_played_this_turn = int(snap["played_this_turn"])
	_window_open = bool(snap["window_open"])
	cards_played = int(snap["cards_played"])
	active_modifiers.clear()
	for m in snap["modifiers"]:
		var card := find_card(StringName(m["card"]))
		var active := ActiveModifier.new()
		active.card = card
		active.effect_index = int(m["effect"])
		active.data = (card.effects[active.effect_index] as AddModifierEffect).modifier
		active.owner = int(m["owner"])
		active.target_player = int(m["target_player"])
		active.target_pawn = game.get_pawn_by_ref(Array(m["target_pawn"]).map(func(v): return int(v))) if not Array(m["target_pawn"]).is_empty() else null
		active.target_tile = int(m["target_tile"])
		active.turns_left = int(m["turns_left"])
		active_modifiers.append(active)
	_refresh_markers()
	for player in hands.size():
		hand_changed.emit(player)
	play_window_changed.emit(_window_open)
