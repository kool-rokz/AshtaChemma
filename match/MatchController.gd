class_name MatchController
extends Node

## The single entry point for player actions.
##   UI / clicks / bots ──submit(PlayerIntent)──► authority validates it with the real
##   rules, adds random results (shell throws), numbers it as an event
##   ──► every copy of the game applies events in order (apply_event), through the
##   normal GameManager / CardManager code.
## OFFLINE: this copy is the authority and all seats are local (tests, simulations).
## HOST:    authority for an online match; plays local_seat, takes the other seats'
##          intents from NetSession, broadcasts events (redacted per seat).
## CLIENT:  sends its seat's intents to the host and applies the host's events.
## REPLICA: applies events fed to it and decides nothing (sync tests).
## Randomness lives only on the authority: draft offers here, throws via
## GameManager.generate_shells(). Everything else is deterministic.
## Dropped players: the host keeps their seat, plays for them after a grace period
## (simple legal moves, never cards), and a returning player resumes from a snapshot
## (GameManager.setup.resume).

## Authority: a new event exists (broadcast this to the other copies).
signal event_created(event: Dictionary)
## Any copy: an event has been applied.
signal event_applied(event: Dictionary)
signal intent_rejected(intent: PlayerIntent, reason: String)

enum Mode { OFFLINE, HOST, CLIENT, REPLICA }

@export var game: GameManager
@export var hud: HUD
## Optional: freed when cards are off.
@export var card_manager: CardManager
@export var mode: Mode = Mode.OFFLINE
## Online connection (found automatically under the scene root; tests may set it).
var net: NetSession
## The seat this copy plays online (-1 = offline: whoever's turn it is).
var local_seat: int = -1

## Authority: number of the next event.
var next_seq: int = 0
## Last event this copy applied (-1 = none).
var applied_seq: int = -1

var _queue: Array[Dictionary] = []
var _processing: bool = false
## Authority: each player's private draft offer (CardData), to check their picks.
var _offers: Dictionary = {}
var _drafted: Dictionary = {}
## Client: this seat's private draft offer from the host.
var _my_offer: Array = []
## A click on a pawn also reaches the tile under it; ignore the echo after a pick.
var _last_pick_msec: int = -1000

const PICK_ECHO_MSEC := 150
## Game seconds an event may wait for this copy to be ready (animations, turn pause).
const READY_TIMEOUT := 30.0
## Host: game seconds a dropped player has to come back before the host plays their
## turns for them (the draft is shorter: it holds everyone up).
const ABSENT_TURN_GRACE := 20.0
const ABSENT_DRAFT_GRACE := 10.0
## Host: game seconds between stand-in actions, so the others can follow them.
const STAND_IN_PACE := 1.0

## Host: actions played for absent players (stats, tests).
var stand_in_actions: int = 0
## Host: seat -> game seconds since that player dropped.
var _away_time: Dictionary = {}
## Host: seats already announced as stood-in for during their current absence.
var _stood_in: Dictionary = {}
var _stand_in_cooldown: float = 0.0

func _ready() -> void:
	if net == null:
		net = NetSession.find(get_tree())
	if net and net.is_online():
		mode = Mode.HOST if net.is_host() else Mode.CLIENT
		local_seat = net.local_seat
	hud.set_local_seat(local_seat)
	if card_manager and (card_manager.is_queued_for_deletion() or not game.setup.cards_enabled):
		card_manager = null
	var resume := game.setup.resume
	if card_manager:
		card_manager.controller = self
		if resume.is_empty():
			game.pre_game_tasks.append(run_draft)
	hud.roll_button.pressed.connect(throw_shells)
	hud.throw_chip_pressed.connect(select_throw)
	game.board.tile_clicked.connect(_on_tile_clicked)
	for pawn in game.get_all_pawns():
		pawn.clicked.connect(_on_pawn_clicked)
	set_process(mode == Mode.HOST)
	if mode in [Mode.HOST, Mode.CLIENT]:
		net.roster_changed.connect(_on_roster_changed)
		net.disconnected.connect(_on_disconnected)
		net.reconnecting.connect(_on_reconnecting)
	if not resume.is_empty():
		_resume.call_deferred(resume) # once every node in the match is ready
	elif mode in [Mode.HOST, Mode.CLIENT]:
		net.register_controller(self) # delivers anything that arrived while loading

## Rejoin: continue from the host's snapshot, then apply what happened since.
func _resume(snap: Dictionary) -> void:
	load_snapshot(snap)
	if mode in [Mode.HOST, Mode.CLIENT]:
		net.register_controller(self)

func _unhandled_input(event: InputEvent) -> void:
	if not _cards() or not card_manager.is_targeting():
		return
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if right_click or event.is_action_pressed("ui_cancel"):
		cancel_card()
		get_viewport().set_input_as_handled()

func _on_disconnected(reason: String) -> void:
	hud.show_notice(reason)

func _on_reconnecting(attempt: int) -> void:
	hud.set_hint("Connection lost. Reconnecting (%d of %d)..." % [attempt, NetSession.RECONNECT_ATTEMPTS])
	if attempt == 1:
		hud.log_message("[color=#f0a54a]Connection to the host lost, reconnecting...[/color]")

## Online: mirror who's connected in the players panel.
func _on_roster_changed(roster: Array) -> void:
	for entry in roster:
		hud.set_player_connected(int(entry["seat"]), bool(entry["connected"]))

func _cards() -> bool:
	return card_manager != null

## The seat this copy acts for: its own online, whoever's turn it is offline.
func acting_seat() -> int:
	return local_seat if local_seat >= 0 else game.current_player_index

## Is it this copy's turn (always true offline)?
func is_local_turn() -> bool:
	return local_seat < 0 or local_seat == game.current_player_index

# --- INPUT → INTENTS ---
func throw_shells() -> bool:
	return submit(PlayerIntent.throw_shells(acting_seat()))

func select_throw(index: int) -> bool:
	return submit(PlayerIntent.select_throw(acting_seat(), index))

func move_pawn(pawn: Pawn) -> bool:
	return submit(PlayerIntent.move_pawn(acting_seat(), game.get_pawn_ref(pawn)))

func play_card(card_id: StringName) -> bool:
	return submit(PlayerIntent.play_card(acting_seat(), card_id))

func choose_target(target: Variant) -> bool:
	if not _cards() or not card_manager.is_targeting():
		return false
	return submit(PlayerIntent.choose_target(acting_seat(), card_manager.target_to_ref(target)))

func cancel_card() -> bool:
	return submit(PlayerIntent.cancel_card(acting_seat()))

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
## Validate an intent and, if allowed, turn it into the next event. Returns true if
## accepted (clients: true once sent; the host decides).
func submit(intent: PlayerIntent) -> bool:
	match mode:
		Mode.CLIENT:
			net.send_intent(intent.to_dict())
			return true
		Mode.REPLICA:
			return false
	return _authorize(intent, false)

## Host: an intent from another seat. The seat comes from the connection, never the message.
func submit_remote(intent: PlayerIntent, seat: int) -> bool:
	intent.player = seat
	return _authorize(intent, true)

func _authorize(intent: PlayerIntent, remote: bool) -> bool:
	var reason := _validate(intent)
	if reason != "":
		_reject(intent, reason)
		if remote:
			net.send_rejected(intent.player, intent.to_dict(), reason)
		return false
	var event := {"seq": next_seq, "intent": intent.to_dict()}
	next_seq += 1
	if intent.kind == PlayerIntent.Kind.THROW:
		event["shells"] = Array(game.generate_shells())
	event_created.emit(event)
	if mode == Mode.HOST:
		net.broadcast_event(event)
	_enqueue(event)
	return true

## What `seat` may see of an event: other players' draft picks become hidden cards.
func event_for_seat(event: Dictionary, seat: int) -> Dictionary:
	var intent: Dictionary = event["intent"]
	if intent.get("kind") == "DRAFT_PICKS" and int(intent["player"]) != seat:
		var redacted := event.duplicate(true)
		redacted["intent"]["cards"] = Array(intent["cards"]).map(func(_id): return CardManager.HIDDEN_CARD)
		return redacted
	return event

## Client: private data from the host (draft offer).
func receive_private(data: Dictionary) -> void:
	if data.has("offer") and _cards():
		_my_offer = Array(data["offer"]).map(func(id): return card_manager.find_card(StringName(id)))

## Why `intent` isn't allowed right now ("" = allowed). Uses the real game rules.
func _validate(intent: PlayerIntent) -> String:
	if not PlayerIntent.Kind.values().has(intent.kind):
		return "Unknown action."
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
			if intent.index < 0 or intent.index >= game.throw_pool.size() or not game.can_use_throw(game.throw_pool[intent.index]):
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
## Offline: one screen with pass-the-device covers. Online: everyone picks at once on
## their own screen; the host deals the offers and checks the picks.
func run_draft() -> void:
	match mode:
		Mode.OFFLINE:
			for player in game.players.size():
				var offer := card_manager.make_offer()
				_offers[player] = offer
				submit(PlayerIntent.draft_picks(player, await _pick(player, offer, true)))
			if not card_manager.auto_draft:
				await card_manager.show_start_cover()
		Mode.HOST:
			for seat in game.players.size():
				_offers[seat] = card_manager.make_offer()
				if seat != local_seat:
					net.send_private(seat, {"offer": _offers[seat].map(func(c): return String(c.id))})
			submit(PlayerIntent.draft_picks(local_seat, await _pick(local_seat, _offers[local_seat], false)))
		Mode.CLIENT:
			while _my_offer.is_empty():
				await get_tree().process_frame
			submit(PlayerIntent.draft_picks(local_seat, await _pick(local_seat, _my_offer, false)))
	if _drafted.size() < game.players.size():
		hud.set_hint("Waiting for the other players to pick their cards...")
	while _drafted.size() < game.players.size():
		await get_tree().process_frame

## Card ids kept from `offer`: the draft screen, or the first ones (auto draft).
func _pick(player: int, offer: Array, with_cover: bool) -> Array:
	var picks: Array
	if card_manager.auto_draft or DevFlags.auto_draft:
		picks = offer.slice(0, card_manager.get_keep_count(offer.size()))
	else:
		picks = await card_manager.pick_cards_on_screen(player, offer, with_cover)
	return picks.map(func(c): return c.id)

# --- HOST: STAND-IN FOR ABSENT PLAYERS ---
func _process(delta: float) -> void:
	for seat in game.players.size():
		if seat == local_seat or net.is_seat_present(seat):
			_away_time.erase(seat)
			_stood_in.erase(seat)
		else:
			_away_time[seat] = _away_time.get(seat, 0.0) + delta
	_stand_in_cooldown -= delta
	if _away_time.is_empty() or _stand_in_cooldown > 0.0 or not _queue.is_empty() or game.is_game_finished():
		return
	var intent := _stand_in_intent()
	if intent:
		_stand_in_cooldown = STAND_IN_PACE
		if not _stood_in.has(intent.player):
			_stood_in[intent.player] = true
			hud.log_message("Playing for %s while they're away." % hud.who(intent.player))
		stand_in_actions += 1
		submit_remote(intent, intent.player)

## The next action to play for an absent seat, or null if none is due.
func _stand_in_intent() -> PlayerIntent:
	# Draft: keep the first offered cards
	for seat in _away_time:
		if _offers.has(seat) and not _drafted.has(seat) and _away_time[seat] >= ABSENT_DRAFT_GRACE:
			var keep := card_manager.get_keep_count(_offers[seat].size())
			return PlayerIntent.draft_picks(seat, _offers[seat].slice(0, keep).map(func(c): return c.id))
	var seat := game.current_player_index
	if not _away_time.has(seat) or _away_time[seat] < ABSENT_TURN_GRACE:
		return null
	match game.current_state:
		GameManager.GameState.WAITING_FOR_ROLL:
			return PlayerIntent.throw_shells(seat)
		GameManager.GameState.SELECTING_PIECE:
			var movable := game.get_movable_pawns(game.current_roll)
			if not movable.is_empty():
				return PlayerIntent.move_pawn(seat, game.get_pawn_ref(movable[0]))
		GameManager.GameState.PLAYING_CARD:
			if _cards() and card_manager.is_targeting():
				return PlayerIntent.cancel_card(seat) # they dropped mid-card
	return null

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
		if intent == null:
			push_error("MatchController: malformed event %d skipped" % seq)
		else:
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
			card_manager.reveal_card(intent.player, intent.card_id) # hidden on other seats until now
			card_manager.request_play_card(intent.card_id)
		PlayerIntent.Kind.CHOOSE_TARGET:
			card_manager.choose_target(card_manager.ref_to_target(intent.target))
		PlayerIntent.Kind.CANCEL_CARD:
			card_manager.cancel_targeting()
		PlayerIntent.Kind.DRAFT_PICKS:
			card_manager.set_hand_by_ids(intent.player, intent.card_ids)
			_drafted[intent.player] = true

# --- SNAPSHOT ---
## Is now a moment a snapshot is complete (nothing animating or waiting to apply)?
func can_snapshot() -> bool:
	return _queue.is_empty() and (game.is_settled() or game.is_game_finished())

## Whole match state (game + cards + event number). Take it when can_snapshot().
## viewer: -1 = everything this copy knows; a seat = hide the other seats' hands;
## CardManager.PUBLIC_VIEW = hide every hand.
func get_snapshot(viewer: int = -1) -> Dictionary:
	return {
		"seq": applied_seq,
		"game": game.to_snapshot(),
		"cards": card_manager.to_snapshot(viewer) if _cards() else {},
	}

func load_snapshot(snap: Dictionary) -> void:
	applied_seq = int(snap["seq"])
	next_seq = applied_seq + 1
	if _cards():
		card_manager.load_snapshot(snap["cards"])
	game.load_snapshot(snap["game"])

## Fingerprint of the public match state (hands as counts); equal on every copy in sync.
func get_state_hash() -> String:
	var snap := get_snapshot(CardManager.PUBLIC_VIEW)
	snap.erase("seq")
	return GameManager.hash_snapshot(snap)
