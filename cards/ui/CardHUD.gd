class_name CardHUD
extends CanvasLayer

## Card UI, created by CardManager, in the Ganjifa look:
##   - this screen's hand as round cards fanned at the bottom (GanjifaHand): hover to read,
##     click to play. A card that needs targets starts its pick (the board rings them);
##     one that needs none is chosen first and played with a second click.
##     Offline (one screen passed round) a hand stays face down until its owner shows it,
##     and hides again every turn.
##   - every card played, by anyone: it flies to the middle with its rule, then onto the
##     discard pile beside the board (CardEffects3D shows what it did on the board)
##   - the private draft (GanjifaDraft) with "pass to" covers offline, or the open draft
##     (GanjifaOpenDraft: one face-up pool, picks in turn, seen by everyone)
##   - card lines in the HUD log, cards held and lasting effects on the player badges, and
##     the board's target choices and markers (through Pawn / TileHighlighter state)
## Decides nothing about the rules: plays go through MatchController as intents.

const TEXT_COLOR := HudStyle.TEXT
const MUTED_COLOR := HudStyle.MUTED

signal _cover_closed

var _cm: CardManager
var _game: GameManager
var _hud: HUD
var _hand: GanjifaHand
var _caption: Label
var _toggle_button: Button
var _cancel_button: Button
var _revealed: bool = false
var _refresh_queued: bool = false
## A card that needs no target, chosen with one click and waiting for the second.
var _armed: int = -1
var _overlay: Control
var _open_draft: GanjifaOpenDraft

func _init() -> void:
	layer = 5

func bind(manager: CardManager) -> void:
	_cm = manager
	_game = manager.game
	_hud = manager.hud
	_hand = GanjifaHand.new()
	_hand.name = "Hand"
	add_child(_hand)
	_hand.card_clicked.connect(_on_card_clicked)
	_hand.cancel_requested.connect(_cancel)
	_build_caption()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 100 # covers and the draft hide the hand (its cards draw raised)
	add_child(_overlay)

	_cm.hand_changed.connect(func(_p): _refresh())
	_cm.play_window_changed.connect(_on_play_window_changed)
	_cm.targeting_started.connect(_on_targeting_started)
	_cm.targeting_cancelled.connect(_on_targeting_cancelled)
	_cm.targeting_ended.connect(_clear_target_highlights)
	_cm.modifiers_changed.connect(_draw_modifier_markers)
	_cm.card_played.connect(_on_card_played)
	_cm.card_resolved.connect(_on_card_resolved)
	_cm.card_rejected.connect(_on_card_rejected)
	_cm.modifier_added.connect(func(_m): _refresh_player_notes())
	_cm.modifier_expired.connect(_on_modifier_expired)
	_cm.open_draft_changed.connect(_on_open_draft_changed)
	_game.turn_changed.connect(_on_turn_changed)
	_game.game_over.connect(_on_game_over)
	_refresh()

# --- THE HAND ---
## A line above the hand saying what the cards can do now, with Show / Cancel buttons.
func _build_caption() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_caption = HudStyle.label("", 15, MUTED_COLOR)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_caption.add_theme_constant_override("outline_size", 6)
	row.add_child(_caption)
	_cancel_button = HudStyle.button("Cancel", Vector2(80, 30))
	_cancel_button.pressed.connect(_cancel)
	row.add_child(_cancel_button)
	_toggle_button = HudStyle.button("Show cards", Vector2(120, 30))
	_toggle_button.name = "ShowCards"
	_toggle_button.pressed.connect(func():
		_revealed = not _revealed
		_refresh())
	row.add_child(_toggle_button)
	row.resized.connect(func(): _place_caption(row))
	_hand.get_viewport().size_changed.connect(func(): _place_caption(row))

func _place_caption(row: Control) -> void:
	var screen := _hand.get_viewport_rect().size
	# Above the hand, clear of a raised (chosen) card
	row.position = Vector2(_hand.centre_x() - row.size.x / 2.0, screen.y - GanjifaCard.DIAMETER * GanjifaHand.PEEK - row.size.y - 46.0)

## Refreshes once at the end of the frame, after GameManager's state has settled
## (turn_changed fires before the turn reaches WAITING_FOR_ROLL).
func _refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_apply_refresh.call_deferred()

func _viewer() -> int:
	var online := _cm.controller != null and _cm.controller.local_seat >= 0
	return _cm.controller.local_seat if online else _game.current_player_index

func _online() -> bool:
	return _cm.controller != null and _cm.controller.local_seat >= 0

func _apply_refresh() -> void:
	_refresh_queued = false
	if _cm == null or _game.players.is_empty():
		return
	# Offline: the current player's hand. Online: always this screen's own hand.
	var player := _viewer()
	var my_turn := player == _game.current_player_index
	var cards: Array = _cm.hands[player] if player < _cm.hands.size() else []
	var targeting := _cm.is_targeting() and my_turn
	if _online():
		_revealed = true # nobody else looks at this screen
	if _armed >= cards.size() or not my_turn:
		_armed = -1
	# Card time = this player may still play a card (before their first throw).
	var card_time := _cm.can_play_now(player) and not _cm.get_playable_cards(player).is_empty()
	var face_up := _revealed or targeting
	var blocked: Array[String] = []
	for i in cards.size():
		blocked.append(_cm.get_block_reason(player, i) if my_turn else "Playable on your turn, before you throw")
	var chosen := _cm.get_targeting_hand_index() if targeting else _armed
	_hand.set_cards(cards, face_up, blocked, chosen)

	_cancel_button.visible = targeting or _armed >= 0
	_toggle_button.visible = not targeting and not cards.is_empty() and not _online()
	_toggle_button.text = "Hide cards" if _revealed else "Show cards (%d)" % cards.size()
	var color := MUTED_COLOR
	if targeting:
		_caption.text = _cm.get_current_target_spec().get_prompt() + GameInput.pick(" (right-click to cancel)", "", " (B / Esc to cancel)")
		color = TEXT_COLOR
	elif _armed >= 0:
		_caption.text = GameInput.pick("Click %s again to play it", "Tap %s again to play it", "Press A / Enter again to play %s") % (cards[_armed] as CardData).title
		color = TEXT_COLOR
	elif cards.is_empty():
		_caption.text = "No cards left" if _online() else "%s has no cards left" % _game.get_player_name(player)
	elif not my_turn:
		_caption.text = "Your cards: playable on your turn, before you throw"
	elif not face_up:
		_caption.text = "%s's cards are hidden" % _game.get_player_name(player)
	elif card_time:
		_caption.text = "Card time: play one before you throw"
		color = _game.get_player_color(player).lightened(0.2)
	elif _cm.get_played_this_turn() > 0:
		_caption.text = "Card played. The next one on your next turn"
	elif not _cm.is_play_window_open() and not _game.is_game_finished():
		_caption.text = "You threw: cards are locked until your next turn"
	else:
		_caption.text = "No card can be played right now"
	_caption.add_theme_color_override("font_color", color)
	_refresh_player_notes()

func _on_card_clicked(index: int) -> void:
	var player := _viewer()
	if _cm.is_targeting() or player != _game.current_player_index:
		return
	if not _revealed:
		_revealed = true # a click on a hidden hand shows it
		_refresh()
		return
	var cards: Array = _cm.hands[player]
	if index < 0 or index >= cards.size():
		return
	var card: CardData = cards[index]
	var reason := _cm.get_block_reason(player, index)
	if reason != "":
		_hud.set_hint("Can't play %s: %s" % [card.title, reason])
		return
	var needs_pick := card.targets.any(func(t: CardTarget): return t.kind != CardTarget.Kind.NEXT_OPPONENT)
	if needs_pick or _armed == index:
		_armed = -1
		_cm.controller.play_card(card.id)
	else:
		_armed = index # no target to pick: a second click plays it
		_hud.set_hint("%s: %s %s" % [card.title, card.description, GameInput.pick("Click it again to play it.", "Tap it again to play it.", "Press A / Enter again to play it.")])
	_refresh()

func _cancel() -> void:
	if _armed >= 0:
		_armed = -1
		_refresh()
	elif _cm.is_targeting():
		_cm.controller.cancel_card()

func _refresh_player_notes() -> void:
	for p in _game.players.size():
		_hud.set_player_cards(p, _cm.hands[p].size())
		var parts: Array[String] = []
		for active in _cm.get_modifiers_for_player(p):
			if active.data.label != "":
				parts.append(active.data.label)
		_hud.set_player_note(p, " · ".join(parts))

# --- DRAFT AND COVERS ---
## Full-screen "pass the device" cover so others don't see the next player's cards.
func show_pass_cover(player: int, button_text: String = "") -> void:
	var cover := ColorRect.new()
	cover.color = Color(0.06, 0.04, 0.03, 0.97)
	cover.size = _hand.get_viewport_rect().size
	_overlay.add_child(cover)
	var center := CenterContainer.new()
	center.size = cover.size
	cover.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var player_name := _game.get_player_name(player)
	var title := HudStyle.label("Pass to %s" % player_name, 44, _game.get_player_color(player).lightened(0.15), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := HudStyle.label("Everyone else, look away: cards are secret.", 18, MUTED_COLOR)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var ready_button := HudStyle.button(button_text if button_text != "" else "I'm %s, show my cards" % player_name, Vector2(320, 52))
	ready_button.name = "PassReady"
	ready_button.add_theme_font_size_override("font_size", 20)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_button.pressed.connect(func(): _cover_closed.emit())
	ready_button.focus_mode = Control.FOCUS_ALL # pad players press it with A
	box.add_child(ready_button)
	GameInput.offer_focus(get_tree(), ready_button)
	await _cover_closed
	cover.queue_free()

## Private draft for one player: a cover first, then pick `keep` of `offer`.
func run_draft(player: int, offer: Array, keep: int, with_cover: bool = true) -> Array:
	if with_cover:
		await show_pass_cover(player)
	var draft := GanjifaDraft.new()
	_overlay.add_child(draft)
	return await draft.run(offer, keep, "%s, pick %d cards" % [_game.get_player_name(player), keep],
		"They stay in your hand all game. Each can be played once, before you throw (1 per turn).",
		_game.get_player_color(player).lightened(0.15))

## The open draft: shown on every screen from CardManager's state; picks go to the
## controller, which checks them (offline: for whoever's pick it is).
func _on_open_draft_changed() -> void:
	if not _cm.is_open_draft_started():
		return
	if _open_draft == null:
		_open_draft = GanjifaOpenDraft.new()
		_open_draft.name = "OpenDraft"
		_overlay.add_child(_open_draft)
		_open_draft.card_chosen.connect(func(slot: int):
			if _cm.controller:
				_cm.controller.take_open_card(slot))
	var names: Array = []
	var colors: Array = []
	for p in _game.players.size():
		names.append(_game.get_player_name(p))
		colors.append(_game.get_player_color(p).lightened(0.15))
	var picker := _cm.open_draft_picker()
	var you: int = _cm.controller.local_seat if _online() else -1
	var can_pick := picker >= 0 and (you < 0 or picker == you)
	_open_draft.show_state(_cm.open_pool, _cm.open_taken, picker, names, colors, can_pick, you)
	if _cm.is_open_draft_done():
		var done := _open_draft
		_open_draft = null
		done.finish()

# --- EVENTS ---
func _on_game_over(_winner: int) -> void:
	_hand.visible = false
	_caption.get_parent().visible = false

func _on_turn_changed(_player: int) -> void:
	_revealed = false
	_armed = -1
	_refresh()

func _on_play_window_changed(open: bool) -> void:
	var my_turn := _cm.controller == null or _cm.controller.is_local_turn()
	if open and my_turn and not _cm.hands[_game.current_player_index].is_empty():
		var show_hint := GameInput.pick("" if _online() else " (Show cards)", "" if _online() else " (Show cards)", " (C / Y for your cards)")
		_hud.set_hint("Card time: play a card first if you like%s. Throwing the shells ends card play for this turn." % show_hint)
	_refresh()

func _on_targeting_started(player: int, card: CardData, spec: CardTarget, candidates: Array) -> void:
	_hand.release_pad_focus() # targets are picked on the board (PadCursor)
	_show_target_highlights(spec, candidates)
	if _cm.controller and not _cm.controller.is_local_turn():
		_hud.set_hint("%s is playing a card..." % _game.get_player_name(player)) # revealed once played
	else:
		_hud.set_hint("%s: %s (%d option%s). %s" % [
			card.title, spec.get_prompt(), candidates.size(), "" if candidates.size() == 1 else "s",
			GameInput.pick("Right-click or Esc to cancel.", "Tap Cancel to stop.", "Left / Right to choose, A / Enter to pick, B / Esc to cancel.")])
	_refresh()

func _on_targeting_cancelled(_player: int, _card: CardData) -> void:
	if _cm.controller == null or _cm.controller.is_local_turn():
		_hud.set_hint("Card cancelled. Play a card or throw the shells.")
	_refresh()

## Everyone sees a played card: it flies in (from the hand that played it, or that
## player's badge), shows its rule, and lands on the discard pile.
func _on_card_played(player: int, card: CardData, targets: Array) -> void:
	var parts: Array[String] = []
	for i in targets.size():
		var target: Variant = targets[i]
		if target is Pawn:
			parts.append("%s's pawn on %s" % [_hud.who(target.team_id), _hud.describe_tile(target.current_tile_index)])
		elif card.targets[i].kind == CardTarget.Kind.TILE:
			parts.append(_hud.describe_tile(target))
		else:
			parts.append(_hud.who(target))
	var on := "" if parts.is_empty() else " on " + " and ".join(parts)
	_hud.log_message("[color=#b8862a]%s played [b]%s[/b] (%s)%s.[/color]" % [_hud.who(player), card.title, Ganjifa.look(card)["avatar"], on], true)
	_hud.log_message("   %s" % card.description)
	var from := _hand.screen_centre_of(card.id) if player == _viewer() else _hud.badge_centre(player)
	var pile: Vector2 = _cm.board_view.discard_screen_point() if _cm.board_view else _hand.get_viewport_rect().size / 2.0
	_hand.show_played(card, from, pile)
	_refresh()

func _on_card_resolved(_player: int, _card: CardData) -> void:
	if not _game.is_game_finished():
		_hud.set_hint(HUD.throw_hint())
	_refresh()

func _on_card_rejected(_player: int, card: CardData, reason: String) -> void:
	_hud.set_hint("Can't play %s: %s" % [card.title, reason])

func _on_modifier_expired(active: ActiveModifier) -> void:
	var what := active.data.label if active.data.label != "" else active.card.title
	_hud.log_message("%s's [b]%s[/b] wore off (%s)." % [_hud.who(active.owner), active.card.title, what])
	_refresh_player_notes()

# --- BOARD MARKS (drawn by the board view from this state) ---
func _show_target_highlights(spec: CardTarget, candidates: Array) -> void:
	if _cm.controller and not _cm.controller.is_local_turn():
		return # only the player picking sees the choices
	if spec.is_pawn():
		for pawn in candidates:
			pawn.set_highlighted(true)
	elif spec.kind == CardTarget.Kind.TILE:
		var tiles: Array[int] = []
		tiles.assign(candidates)
		_game.board.highlighter.set_target_tiles(tiles)

func _clear_target_highlights() -> void:
	for pawn in _game.get_all_pawns():
		pawn.set_highlighted(false)
	_game.board.highlighter.set_target_tiles([])

## Domes on affected pawns, marks on affected squares.
func _draw_modifier_markers() -> void:
	var pawn_colors := {}
	var tiles := {}
	for active in _cm.active_modifiers:
		var color := active.data.marker_color
		if color.a <= 0.0:
			continue
		if active.target_pawn:
			pawn_colors[active.target_pawn] = color
		if active.target_tile >= 0:
			tiles[active.target_tile] = color
	for pawn in _game.get_all_pawns():
		pawn.set_status_color(pawn_colors.get(pawn, Color(0, 0, 0, 0)))
	_game.board.highlighter.set_marked_tiles(tiles)
