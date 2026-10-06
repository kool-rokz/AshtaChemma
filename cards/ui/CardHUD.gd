class_name CardHUD
extends CanvasLayer

## Card UI, created by CardManager: the hand strip under the board, the private
## draft screens with "pass to" covers, and card lines in the main HUD log.
## Hands stay face-down until their owner clicks "Show cards", and hide again every turn.

const HAND_POS := Vector2(390, 540)
const HAND_SIZE := Vector2(500, 172)
const HAND_CARD_SIZE := Vector2(92, 124)
const DRAFT_CARD_SIZE := Vector2(150, 172)
const BACK_COLOR := Color(0.22, 0.22, 0.3)
const TEXT_COLOR := Color(0.95, 0.95, 0.97)
const MUTED_COLOR := Color(0.7, 0.7, 0.75)

signal _draft_done(picks: Array)
signal _cover_closed

var _cm: CardManager
var _game: GameManager
var _hud: HUD

var _hand_panel: PanelContainer
var _hand_style: StyleBoxFlat
var _hand_title: Label
var _toggle_button: Button
var _cancel_button: Button
var _cards_row: HBoxContainer
var _revealed: bool = false
var _refresh_queued: bool = false

var _overlay: ColorRect
var _overlay_box: VBoxContainer

func _init() -> void:
	layer = 5

func bind(manager: CardManager) -> void:
	_cm = manager
	_game = manager.game
	_hud = _game.hud
	_build_hand_panel()
	_build_overlay()

	_cm.hand_changed.connect(func(_p): _refresh())
	_cm.play_window_changed.connect(_on_play_window_changed)
	_cm.targeting_started.connect(_on_targeting_started)
	_cm.targeting_cancelled.connect(_on_targeting_cancelled)
	_cm.card_played.connect(_on_card_played)
	_cm.card_resolved.connect(_on_card_resolved)
	_cm.card_rejected.connect(_on_card_rejected)
	_cm.modifier_added.connect(func(_m): _refresh_player_notes())
	_cm.modifier_expired.connect(_on_modifier_expired)
	_game.turn_changed.connect(_on_turn_changed)
	_game.game_over.connect(func(_w): _hand_panel.visible = false)
	_refresh()

# --- HAND STRIP ---
func _build_hand_panel() -> void:
	_hand_panel = PanelContainer.new()
	_hand_panel.position = HAND_POS
	_hand_panel.size = HAND_SIZE
	_hand_style = StyleBoxFlat.new()
	_hand_style.bg_color = Color(0.13, 0.13, 0.16, 0.92)
	_hand_style.set_corner_radius_all(8)
	_hand_style.set_content_margin_all(8)
	_hand_style.set_border_width_all(2)
	_hand_style.border_color = Color(0, 0, 0, 0)
	_hand_panel.add_theme_stylebox_override("panel", _hand_style)
	add_child(_hand_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_hand_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_hand_title = _label("", 14, MUTED_COLOR)
	_hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_title.clip_text = true
	header.add_child(_hand_title)
	_cancel_button = _small_button("Cancel")
	# Actions go through MatchController as intents (set after this panel is built)
	_cancel_button.pressed.connect(func(): _cm.controller.cancel_card())
	header.add_child(_cancel_button)
	_toggle_button = _small_button("Show cards")
	_toggle_button.name = "ShowCards"
	_toggle_button.pressed.connect(func():
		_revealed = not _revealed
		_refresh())
	header.add_child(_toggle_button)
	box.add_child(header)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 6)
	box.add_child(_cards_row)

## Refreshes once at the end of the frame, after GameManager's state has settled
## (turn_changed fires before the turn reaches WAITING_FOR_ROLL).
func _refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_apply_refresh.call_deferred()

func _apply_refresh() -> void:
	_refresh_queued = false
	if _cm == null or _game.players.is_empty():
		return
	var player := _game.current_player_index
	var hand: Array = _cm.hands[player] if player < _cm.hands.size() else []
	var targeting := _cm.is_targeting()

	# Card time = this player may still play a card (before their first throw).
	var card_time := _cm.can_play_now(player) and not _cm.get_playable_cards(player).is_empty()

	_cancel_button.visible = targeting
	_toggle_button.visible = not targeting and not hand.is_empty()
	_toggle_button.text = "Hide cards" if _revealed else "Show cards (%d)" % hand.size()
	var title_color := MUTED_COLOR
	if targeting:
		_hand_title.text = _cm.get_current_target_spec().get_prompt() + " (right-click to cancel)"
		title_color = TEXT_COLOR
	elif hand.is_empty():
		_hand_title.text = "%s has no cards left" % _game.get_player_name(player)
	elif card_time:
		_hand_title.text = "Card time: play one BEFORE you throw"
		title_color = _game.get_player_color(player)
	elif _cm.get_played_this_turn() > 0:
		_hand_title.text = "Card played. Next one on your next turn"
	elif not _cm.is_play_window_open() and not _game.is_game_finished():
		_hand_title.text = "You threw: cards locked until your next turn"
	else:
		_hand_title.text = "No card can be played right now"
	_hand_title.add_theme_color_override("font_color", title_color)

	# Coloured frame while cards can be played; none once the window has closed
	_hand_style.border_color = _game.get_player_color(player) if card_time or targeting else Color(0, 0, 0, 0)
	_update_throw_button(card_time)

	for child in _cards_row.get_children():
		child.queue_free()
	for i in hand.size():
		var card: CardData = hand[i]
		var widget: Button
		if _revealed or targeting:
			widget = _card_widget(card, HAND_CARD_SIZE, true, 13, 11)
			var reason := _cm.get_block_reason(player, i)
			widget.disabled = reason != ""
			widget.tooltip_text = card.description + ("" if reason == "" else "\n\n" + reason)
			widget.pressed.connect(func(): _cm.controller.play_card(card.id))
		else:
			widget = _card_widget(null, HAND_CARD_SIZE, false, 13, 11)
			widget.tooltip_text = "Click to show your cards"
			widget.pressed.connect(func():
				_revealed = true
				_refresh())
		widget.name = "Card%d" % (i + 1)
		_cards_row.add_child(widget)
	_refresh_player_notes()

const THROW_ENDS_CARDS := "Throw shells (ends card play)"

## While a card could still be played, the Throw button says that throwing gives that up.
func _update_throw_button(card_time: bool) -> void:
	var button := _hud.roll_button
	if card_time:
		button.text = THROW_ENDS_CARDS
	elif button.text == THROW_ENDS_CARDS:
		button.text = "Throw shells"

func _refresh_player_notes() -> void:
	for p in _game.players.size():
		var parts: Array[String] = ["Cards: %d" % _cm.hands[p].size()]
		for active in _cm.get_modifiers_for_player(p):
			if active.data.label != "":
				parts.append(active.data.label)
		_hud.set_player_note(p, " · ".join(parts))

# --- DRAFT ---
func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.08, 0.08, 0.1, 0.97)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 16)
	center.add_child(_overlay_box)

func _clear_overlay() -> void:
	for child in _overlay_box.get_children():
		child.queue_free()

## Full-screen "pass the device" cover so others don't see the next player's cards.
func show_pass_cover(player: int, button_text: String = "") -> void:
	_clear_overlay()
	_overlay.visible = true
	var player_name := _game.get_player_name(player)
	var title := _label("Pass to %s" % player_name, 40, _game.get_player_color(player))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(title)
	var note := _label("Everyone else, look away: cards are secret.", 18, MUTED_COLOR)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(note)
	var ready_button := _big_button(button_text if button_text != "" else "I'm %s, show my cards" % player_name)
	ready_button.name = "PassReady"
	ready_button.pressed.connect(func(): _cover_closed.emit())
	_overlay_box.add_child(ready_button)
	await _cover_closed
	_overlay.visible = false

## Private draft for one player: a cover first, then pick `keep` of `offer`.
func run_draft(player: int, offer: Array, keep: int) -> Array:
	await show_pass_cover(player)
	_clear_overlay()
	_overlay.visible = true

	var title := _label("%s, pick %d cards" % [_game.get_player_name(player), keep], 30, _game.get_player_color(player))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(title)
	var note := _label("They stay in your hand all game. Each can be played once, before you throw (1 per turn).", 15, MUTED_COLOR)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(note)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_overlay_box.add_child(grid)

	var confirm := _big_button("")
	confirm.name = "ConfirmDraft"
	var picked: Array[Button] = []
	var buttons: Array[Button] = []
	var update := func():
		confirm.text = "Keep these %d" % keep if picked.size() == keep else "Picked %d / %d" % [picked.size(), keep]
		confirm.disabled = picked.size() != keep

	for i in offer.size():
		var widget := _card_widget(offer[i], DRAFT_CARD_SIZE, true, 16, 13)
		widget.name = "Offer%d" % (i + 1)
		widget.toggle_mode = true
		widget.tooltip_text = offer[i].description
		widget.toggled.connect(func(on: bool):
			if on and picked.size() >= keep:
				widget.set_pressed_no_signal(false)
				return
			if on:
				picked.append(widget)
			else:
				picked.erase(widget)
			update.call())
		buttons.append(widget)
		grid.add_child(widget)

	confirm.pressed.connect(func():
		var picks: Array = []
		for i in buttons.size():
			if buttons[i] in picked:
				picks.append(offer[i])
		_draft_done.emit(picks))
	_overlay_box.add_child(confirm)
	update.call()

	var result: Array = await _draft_done
	_overlay.visible = false
	return result

## Pick the first cards of the open draft screen (used by tests driving the real UI).
func debug_pick_first(count: int) -> void:
	var grid: GridContainer = null
	for child in _overlay_box.get_children():
		if child is GridContainer:
			grid = child
	if grid == null:
		return
	for i in mini(count, grid.get_child_count()):
		(grid.get_child(i) as Button).button_pressed = true

# --- EVENTS ---
func _on_turn_changed(_player: int) -> void:
	_revealed = false
	_refresh()

func _on_play_window_changed(open: bool) -> void:
	if open and not _cm.hands[_game.current_player_index].is_empty():
		_hud.set_hint("Card time: play a card first if you like (Show cards). Throwing the shells ends card play for this turn.")
	_refresh()

func _on_targeting_started(_player: int, card: CardData, spec: CardTarget, candidates: Array) -> void:
	_hud.set_hint("%s: %s (%d option%s). Right-click or Esc to cancel." % [
		card.title, spec.get_prompt(), candidates.size(), "" if candidates.size() == 1 else "s"])
	_refresh()

func _on_targeting_cancelled(_player: int, _card: CardData) -> void:
	_hud.set_hint("Card cancelled. Play a card or throw the shells.")
	_refresh()

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
	_hud.log_message("[color=#e8c26a]%s played [b]%s[/b]%s.[/color]" % [_hud.who(player), card.title, on])
	_hud.log_message("[color=#a8a8b0]   %s[/color]" % card.description)
	_refresh()

func _on_card_resolved(_player: int, _card: CardData) -> void:
	if not _game.is_game_finished():
		_hud.set_hint("Throw the shells.")
	_refresh()

func _on_card_rejected(_player: int, card: CardData, reason: String) -> void:
	_hud.set_hint("Can't play %s: %s" % [card.title, reason])

func _on_modifier_expired(active: ActiveModifier) -> void:
	var what := active.data.label if active.data.label != "" else active.card.title
	_hud.log_message("%s's [b]%s[/b] wore off (%s)." % [_hud.who(active.owner), active.card.title, what])
	_refresh_player_notes()

# --- WIDGETS ---
func _label(text: String, font_size: int, color: Color = TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	return button

func _big_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	return button

## A card face (title + description) or, with card = null, a face-down back.
func _card_widget(card: CardData, card_size: Vector2, face_up: bool, title_size: int, body_size: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	var base: Color = card.color if face_up and card else BACK_COLOR
	var looks := {
		"normal": [base.darkened(0.35), base, 2],
		"hover": [base.darkened(0.2), Color(1, 1, 1, 0.45), 2],
		"pressed": [base.darkened(0.05), Color.WHITE, 4],
		"hover_pressed": [base.darkened(0.05), Color.WHITE, 4],
		"disabled": [base.darkened(0.7), base.darkened(0.5), 2],
	}
	for state in looks:
		var style := StyleBoxFlat.new()
		style.bg_color = looks[state][0]
		style.border_color = looks[state][1]
		style.set_border_width_all(looks[state][2])
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 7
	box.offset_top = 6
	box.offset_right = -7
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	button.add_child(box)

	if not face_up or card == null:
		var mark := _label("?", 40, Color(1, 1, 1, 0.35))
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(mark)
		return button

	var title := _label(card.title, title_size)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var body := _label(card.description, body_size, Color(0.88, 0.88, 0.9))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	return button
