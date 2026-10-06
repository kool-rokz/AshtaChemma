class_name MatchController
extends Node

## The single entry point for player actions.
##   UI / clicks / bots ──submit(PlayerIntent)──► authority validates it with the real
##   rules, adds random results (shell throws), numbers it as an event
##   ──► every copy of the game applies events in order (apply_event), through the
##   normal GameManager / CardManager code.
## OFFLINE: this copy is the authority and all seats are local.
## REPLICA: applies events from an authority and never decides anything itself
##   (online clients will work like this; tests use it to prove copies stay in sync).
## Randomness lives only on the authority: draft offers here, throws via
## GameManager.generate_shells(). Everything else is deterministic.

## Authority: a new event exists (broadcast this to the other copies).
signal event_created(event: Dictionary)
## Any copy: an event has been applied.
signal event_applied(event: Dictionary)
signal intent_rejected(intent: PlayerIntent, reason: String)

enum Mode { OFFLINE, REPLICA }

@export var game: GameManager
## Optional: freed when cards are off.
@export var card_manager: CardManager
@export var mode: Mode = Mode.OFFLINE

## Authority: number of the next event.
var next_seq: int = 0
## Last event this copy applied (-1 = none).
var applied_seq: int = -1

var _queue: Array[Dictionary] = []
var _processing: bool = false
## Authority: each player's private draft offer (CardData), to check their picks.
var _offers: Dictionary = {}
var _drafted: Dictionary = {}
## A click on a pawn also reaches the tile under it; ignore the echo after a pick.
var _last_pick_msec: int = -1000

const PICK_ECHO_MSEC := 150
## Game seconds an event may wait for this copy to be ready (animations, turn pause).
const READY_TIMEOUT := 30.0

func _ready() -> void:
	if card_manager and (card_manager.is_queued_for_deletion() or not GameConfig.cards_enabled):
		card_manager = null
	if card_manager:
		card_manager.controller = self
		game.pre_game_tasks.append(run_draft)
	game.roll_button.pressed.connect(throw_shells)
	game.hud.throw_chip_pressed.connect(select_throw)
	game.board.tile_clicked.connect(_on_tile_clicked)
	for pawn in game.get_all_pawns():
		pawn.clicked.connect(_on_pawn_clicked)

func _unhandled_input(event: InputEvent) -> void:
	if not _cards() or not card_manager.is_targeting():
		return
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if right_click or event.is_action_pressed("ui_cancel"):
		cancel_card()
		get_viewport().set_input_as_handled()

func _cards() -> bool:
	return card_manager != null

func is_authority() -> bool:
	return mode == Mode.OFFLINE

# --- INPUT → INTENTS (the acting player is whoever's turn it is; online: this seat) ---
func throw_shells() -> bool:
	return submit(PlayerIntent.throw_shells(game.current_player_index))

func select_throw(index: int) -> bool:
	return submit(PlayerIntent.select_throw(game.current_player_index, index))

func move_pawn(pawn: Pawn) -> bool:
	return submit(PlayerIntent.move_pawn(game.current_player_index, game.get_pawn_ref(pawn)))

func play_card(card_id: StringName) -> bool:
	return submit(PlayerIntent.play_card(game.current_player_index, card_id))

func choose_target(target: Variant) -> bool:
	if not _cards() or not card_manager.is_targeting():
		return false
	return submit(PlayerIntent.choose_target(game.current_player_index, card_manager.target_to_ref(target)))

func cancel_card() -> bool:
	return submit(PlayerIntent.cancel_card(game.current_player_index))

func _on_pawn_clicked(pawn: Pawn) -> void:
	if Time.get_ticks_msec() - _last_pick_msec < PICK_ECHO_MSEC:
		return
	if _cards() and card_manager.is_targeting():
		if card_manager.get_current_target_spec().is_pawn() and choose_target(pawn):
			_last_pick_msec = Time.get_ticks_msec()
		return
	if game.current_state == GameManager.GameState.SELECTING_PIECE:
		move_pawn(pawn)

func _on_tile_clicked(tile: int) -> void:
	if not _cards() or not card_manager.is_targeting():
		return
	if Time.get_ticks_msec() - _last_pick_msec < PICK_ECHO_MSEC:
		return
	if card_manager.get_current_target_spec().kind == CardTarget.Kind.TILE and choose_target(tile):
		_last_pick_msec = Time.get_ticks_msec()

# --- AUTHORITY ---
## Validate an intent and, if allowed, turn it into the next event. Returns true if accepted.
func submit(intent: PlayerIntent) -> bool:
	if not is_authority():
		return false # online clients will send the intent to the host here
	var reason := _validate(intent)
	if reason != "":
		_reject(intent, reason)
		return false
	var event := {"seq": next_seq, "intent": intent.to_dict()}
	next_seq += 1
	if intent.kind == PlayerIntent.Kind.THROW:
		event["shells"] = Array(game.generate_shells())
	event_created.emit(event)
	_enqueue(event)
	return true

## Why `intent` isn't allowed right now ("" = allowed). Uses the real game rules.
func _validate(intent: PlayerIntent) -> String:
	if game.is_game_finished():
		return "The game is over."
	if not _queue.is_empty():
		return "Busy."
	if intent.kind == PlayerIntent.Kind.DRAFT_PICKS:
		return _validate_draft(intent)
	if intent.player != game.current_player_index:
		return "Not your turn."
	var state := game.current_state
	match intent.kind:
		PlayerIntent.Kind.THROW:
			if state != GameManager.GameState.WAITING_FOR_ROLL:
				return "You can't throw now."
		PlayerIntent.Kind.SELECT_THROW:
			if state != GameManager.GameState.SELECTING_PIECE:
				return "Not choosing a move."
			if intent.index < 0 or intent.index >= game.throw_pool.size() or not game._is_throw_usable(game.throw_pool[intent.index]):
				return "No pawn can use that throw."
		PlayerIntent.Kind.MOVE_PAWN:
			if state != GameManager.GameState.SELECTING_PIECE:
				return "Not choosing a move."
			var pawn := game.get_pawn_by_ref(intent.pawn)
			if pawn == null or pawn.team_id != intent.player:
				return "That's not your pawn."
			if not game.can_move_pawn(pawn, game.current_roll):
				return "That pawn can't move by %d." % game.current_roll
		PlayerIntent.Kind.PLAY_CARD:
			if not _cards():
				return "Cards are off."
			var index := card_manager.find_hand_index(intent.player, intent.card_id)
			if index < 0:
				return "That card isn't in your hand."
			var block := card_manager.get_block_reason(intent.player, index)
			if block != "":
				card_manager.card_rejected.emit(intent.player, card_manager.hands[intent.player][index], block)
				return block
		PlayerIntent.Kind.CHOOSE_TARGET:
			if not _cards() or not card_manager.is_targeting():
				return "No card is waiting for a target."
			if not card_manager.ref_to_target(intent.target) in card_manager.get_target_candidates():
				return "Not a valid target."
		PlayerIntent.Kind.CANCEL_CARD:
			if not _cards() or not card_manager.is_targeting():
				return "No card to cancel."
	return ""

func _validate_draft(intent: PlayerIntent) -> String:
	if not _cards() or not _offers.has(intent.player):
		return "No draft offer for this player."
	if _drafted.has(intent.player):
		return "Already drafted."
	var offer_ids: Array = _offers[intent.player].map(func(c): return c.id)
	var keep := card_manager.get_keep_count(offer_ids.size())
	if intent.card_ids.size() != keep:
		return "Pick exactly %d cards." % keep
	for id in intent.card_ids:
		if not id in offer_ids or intent.card_ids.count(id) > 1:
			return "Card %s wasn't offered." % id
	return ""

func _reject(intent: PlayerIntent, reason: String) -> void:
	intent_rejected.emit(intent, reason)

## Pre-game (awaited by GameManager): each player keeps cards from a private offer.
## The authority deals offers; replicas just wait for the picks to arrive as events.
func run_draft() -> void:
	if not is_authority():
		while _drafted.size() < game.players.size():
			await get_tree().process_frame
		return
	for player in game.players.size():
		var offer := card_manager.make_offer()
		_offers[player] = offer
		var picks: Array
		if card_manager.auto_draft:
			picks = offer.slice(0, card_manager.get_keep_count(offer.size()))
		else:
			picks = await card_manager.pick_cards_on_screen(player, offer)
		submit(PlayerIntent.draft_picks(player, picks.map(func(c): return c.id)))
	if not card_manager.auto_draft:
		await card_manager.show_start_cover()

# --- EVERY COPY: apply events in order ---
## Feed an event from the authority (replicas, and later the network).
func apply_event(event: Dictionary) -> void:
	_enqueue(event)

func _enqueue(event: Dictionary) -> void:
	_queue.append(event)
	if not _processing:
		_process_queue()

func _process_queue() -> void:
	_processing = true
	while not _queue.is_empty():
		var event: Dictionary = _queue.front()
		var seq := int(event["seq"])
		if seq != applied_seq + 1:
			push_error("MatchController: event %d arrived, expected %d" % [seq, applied_seq + 1])
		var intent := PlayerIntent.from_dict(event["intent"])
		await _wait_until_ready(intent)
		_execute(intent, event)
		_queue.pop_front()
		applied_seq = seq
		event_applied.emit(event)
	_processing = false

## The state an intent needs, e.g. a move waits until the previous animation is done.
func _is_ready_for(intent: PlayerIntent) -> bool:
	var state := game.current_state
	match intent.kind:
		PlayerIntent.Kind.THROW, PlayerIntent.Kind.PLAY_CARD:
			return state == GameManager.GameState.WAITING_FOR_ROLL
		PlayerIntent.Kind.SELECT_THROW, PlayerIntent.Kind.MOVE_PAWN:
			return state == GameManager.GameState.SELECTING_PIECE
		PlayerIntent.Kind.CHOOSE_TARGET, PlayerIntent.Kind.CANCEL_CARD:
			return _cards() and card_manager.is_targeting()
	return true

func _wait_until_ready(intent: PlayerIntent) -> void:
	if _is_ready_for(intent):
		return # applies immediately (same frame), like a direct call
	var deadline := Time.get_ticks_msec() + int(READY_TIMEOUT * 1000.0 / Engine.time_scale)
	while not _is_ready_for(intent) and not game.is_game_finished():
		if Time.get_ticks_msec() > deadline:
			push_error("MatchController: out of sync, %s can't apply in state %s" % [intent, GameManager.GameState.keys()[game.current_state]])
			return
		await get_tree().process_frame

func _execute(intent: PlayerIntent, event: Dictionary) -> void:
	if intent.kind != PlayerIntent.Kind.DRAFT_PICKS and intent.player != game.current_player_index:
		push_error("MatchController: out of sync, %s on player %d's turn" % [intent, game.current_player_index])
	match intent.kind:
		PlayerIntent.Kind.THROW:
			var shells: Array[bool] = []
			shells.assign(Array(event.get("shells", [])).map(func(v): return bool(v)))
			game.apply_throw(shells)
		PlayerIntent.Kind.SELECT_THROW:
			game.select_throw(intent.index)
		PlayerIntent.Kind.MOVE_PAWN:
			game.request_select_pawn(game.get_pawn_by_ref(intent.pawn))
		PlayerIntent.Kind.PLAY_CARD:
			card_manager.request_play_card(intent.card_id)
		PlayerIntent.Kind.CHOOSE_TARGET:
			card_manager.choose_target(card_manager.ref_to_target(intent.target))
		PlayerIntent.Kind.CANCEL_CARD:
			card_manager.cancel_targeting()
		PlayerIntent.Kind.DRAFT_PICKS:
			card_manager.set_hand_by_ids(intent.player, intent.card_ids)
			_drafted[intent.player] = true

# --- SNAPSHOT ---
## Whole match state (game + cards + event number). Take it while game.is_settled().
func get_snapshot() -> Dictionary:
	return {
		"seq": applied_seq,
		"game": game.to_snapshot(),
		"cards": card_manager.to_snapshot() if _cards() else {},
	}

func load_snapshot(snap: Dictionary) -> void:
	applied_seq = int(snap["seq"])
	next_seq = applied_seq + 1
	if _cards():
		card_manager.load_snapshot(snap["cards"])
	game.load_snapshot(snap["game"])

## Fingerprint of the match state; equal on every copy that's in sync.
func get_state_hash() -> String:
	var snap := get_snapshot()
	snap.erase("seq")
	return GameManager.hash_snapshot(snap)
