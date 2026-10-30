class_name RandomBot
extends RefCounted

## Plays one random legal action for the seat `ctrl` acts for, through the controller
## (so online it goes to the host like a real click). Used by tests and the --bot dev flag.

## A shaken, hand-thrown gesture with random strength and faces (exercises "skill throws").
static func _random_gesture(rng: RandomNumberGenerator) -> ThrowGesture:
	var g := ThrowGesture.new()
	g.quick = false
	g.origin = Vector2(rng.randf_range(470, 790), rng.randf_range(207, 527))
	g.direction = Vector2.from_angle(rng.randf() * TAU)
	g.power = rng.randf()
	g.shaken = rng.randf()
	for i in 4:
		g.faces[i] = rng.randf() < 0.5
	g.seed_value = rng.randi()
	return g

static func step(gm: GameManager, ctrl: MatchController, rng: RandomNumberGenerator) -> void:
	var cm := ctrl.card_manager
	var seat := ctrl.acting_seat()
	match gm.current_state:
		GameManager.GameState.WAITING_FOR_ROLL:
			if cm and cm.can_play_now(seat) and rng.randf() < 0.5:
				var playable := cm.get_playable_cards(seat)
				if not playable.is_empty():
					ctrl.play_card(cm.hands[seat][playable[rng.randi() % playable.size()]].id)
					return
			ctrl.throw_shells(_random_gesture(rng) if rng.randf() < 0.4 else null)
		GameManager.GameState.PLAYING_CARD:
			if cm and cm.is_targeting():
				var candidates := cm.get_target_candidates()
				if rng.randf() < 0.1:
					ctrl.cancel_card()
				else:
					ctrl.choose_target(candidates[rng.randi() % candidates.size()])
		GameManager.GameState.SELECTING_PIECE:
			# Sometimes switch to another usable throw first
			if gm.throw_pool.size() > 1 and rng.randf() < 0.3:
				var other := rng.randi() % gm.throw_pool.size()
				if gm.can_use_throw(gm.throw_pool[other]):
					ctrl.select_throw(other)
					return
			var movable := gm.get_movable_pawns(gm.current_roll)
			if not movable.is_empty():
				ctrl.move_pawn(movable[rng.randi() % movable.size()])
