class_name GanjifaDraft
extends Control

## The card draft as a dealt hand of Ganjifa cards: the offer is dealt face down from a
## deck at the top, flipped one by one, the player picks `keep` (picked cards rise and
## glow; hovering shows a card's rule), then the picks fly down into the hand and the
## rest go back to the deck. Usage: add it to a full-screen layer, then
## `var picks = await draft.run(...)`; it frees itself when done.
## Laid out on a 1280x720 stage scaled to fit the screen. Touch: a tap picks a card and
## shows its rule. Keyboard / pad: pick_prev / pick_next step through the cards and the
## Keep button, pick_confirm picks (or presses Keep).

signal _confirmed

const ROW := 5
const SLOT_GAP := 160.0
const ROW_GAP := 170.0
const FIRST_ROW_Y := 200.0
const STAGE := Vector2(1280, 720)

var _stage: Control
var _cards: Array[GanjifaCard] = []
var _confirm: Button
var _info: Label
## Keyboard / pad: index of the card in focus (_cards.size() = the Keep button), -1 = none.
var _focus := -1
var _toggle: Callable

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it can be clicked meanwhile
	_stage = Control.new()
	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	size = get_viewport_rect().size
	var fit := minf(size.x / STAGE.x, size.y / STAGE.y)
	_stage.scale = Vector2.ONE * fit
	_stage.position = (size - STAGE * fit) / 2.0

## Returns the picked CardData, in offer order.
func run(offer: Array, keep: int, title_text: String, note_text: String, color: Color) -> Array:
	var screen := STAGE
	var veil := ColorRect.new()
	veil.color = Color(0.05, 0.03, 0.02, 0.0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	move_child(veil, 0)
	create_tween().tween_property(veil, "color:a", 0.8, 0.3)
	var title := HudStyle.label(title_text, 34, color, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(screen.x, 44)
	title.position = Vector2(0, 92)
	_stage.add_child(title)
	var note := HudStyle.label(note_text, 16, HudStyle.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(screen.x, 24)
	note.position = Vector2(0, 140)
	_stage.add_child(note)
	_info = HudStyle.label("", 16, HudStyle.TEXT)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.size = Vector2(screen.x, 24)
	_info.position = Vector2(0, FIRST_ROW_Y + ROW_GAP * 2.0 - 4.0)
	_stage.add_child(_info)
	var deck_at := Vector2(screen.x / 2.0 - GanjifaCard.DIAMETER / 2.0, -GanjifaCard.DIAMETER)
	for i in offer.size():
		var card := GanjifaCard.new(offer[i], false)
		card.name = "Offer%d" % (i + 1)
		card.position = deck_at
		_stage.add_child(card)
		_cards.append(card)
		Sound.play(&"card_deal", -2.0, i * 0.07)
		var t := card.create_tween().set_parallel()
		t.tween_property(card, "position", _slot(i, offer.size()), 0.4).set_delay(i * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(card, "rotation", TAU, 0.4).set_delay(i * 0.07)
	await get_tree().create_timer(0.4 + offer.size() * 0.07).timeout
	for card in _cards: # flip each over
		var flip := card.create_tween()
		flip.tween_property(card, "scale:x", 0.0, 0.1)
		flip.tween_callback(func():
			card.face_up = true
			Sound.play(&"card_flip", -4.0))
		flip.tween_property(card, "scale:x", 1.0, 0.1)
		await get_tree().create_timer(0.05).timeout
	_confirm = HudStyle.button("Pick %d" % keep, Vector2(240, 48))
	_confirm.name = "ConfirmDraft"
	_confirm.add_theme_font_size_override("font_size", 20)
	_confirm.disabled = true
	_confirm.position = Vector2(screen.x / 2.0 - 120, FIRST_ROW_Y + ROW_GAP * 2.0 + 30.0)
	_confirm.pressed.connect(func(): _confirmed.emit())
	_stage.add_child(_confirm)
	var picked := {}
	_toggle = func(card: GanjifaCard):
		_show_rule(card)
		Sound.play(&"card_hover", 4.0)
		if picked.has(card):
			picked.erase(card)
		elif picked.size() < keep:
			picked[card] = true
		var t := card.create_tween().set_parallel()
		t.tween_property(card, "position:y", _slot(_cards.find(card), _cards.size()).y - (16.0 if picked.has(card) else 0.0), 0.15)
		t.tween_property(card, "scale", Vector2.ONE * (1.1 if picked.has(card) else 1.0), 0.15)
		t.tween_property(card, "glow", 1.0 if picked.has(card) else 0.0, 0.15)
		_confirm.text = "Keep these %d" % keep if picked.size() == keep else "Picked %d / %d" % [picked.size(), keep]
		_confirm.disabled = picked.size() != keep
	for card in _cards:
		card.mouse_entered.connect(_show_rule.bind(card))
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_toggle.call(card))
	if GameInput.is_focus_driven():
		_set_focus(0)
	await _confirmed
	_focus = -1
	_confirm.queue_free()
	var result: Array = []
	var hand_at := Vector2(screen.x / 2.0 - GanjifaCard.DIAMETER / 2.0, screen.y)
	for i in _cards.size():
		var card := _cards[i]
		var t := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if picked.has(card):
			result.append(offer[i])
			t.tween_property(card, "position", hand_at + Vector2((result.size() - 3) * 60.0, 0), 0.45).set_delay(result.size() * 0.05)
		else:
			t.tween_property(card, "position", deck_at, 0.35)
			t.tween_property(card, "modulate:a", 0.0, 0.35)
	create_tween().tween_property(veil, "color:a", 0.0, 0.45)
	await get_tree().create_timer(0.6).timeout
	queue_free()
	return result

func _show_rule(card: GanjifaCard) -> void:
	_info.text = "%s  ·  %s" % [card.card.title, card.card.description]

## Keyboard / pad: the card (or the Keep button) in focus is outlined.
func _set_focus(index: int) -> void:
	_focus = index
	for i in _cards.size():
		_cards[i].glow_color = Color(1, 1, 1) if i == index else Color(1.0, 0.85, 0.4)
		if i == index and _cards[i].glow < 0.5:
			_cards[i].glow = 0.35
		elif i != index and _cards[i].glow < 0.5:
			_cards[i].glow = 0.0
		_cards[i].queue_redraw()
	if index >= 0 and index < _cards.size():
		_show_rule(_cards[index])
		_confirm.release_focus()
	elif index == _cards.size():
		_confirm.focus_mode = Control.FOCUS_ALL
		_confirm.grab_focus()

func _input(event: InputEvent) -> void:
	if _confirm == null or not is_instance_valid(_confirm) or _toggle.is_null():
		return
	var slots := _cards.size() + 1
	if event.is_action_pressed("pick_next", true) or event.is_action_pressed("pick_prev", true):
		var step := 1 if event.is_action_pressed("pick_next", true) else -1
		_set_focus(wrapi(_focus + step, 0, slots) if _focus >= 0 else 0)
	elif event.is_action_pressed("pick_confirm") and _focus >= 0:
		if _focus < _cards.size():
			_toggle.call(_cards[_focus])
		elif not _confirm.disabled:
			_confirmed.emit()
	else:
		return
	get_viewport().set_input_as_handled()

func _slot(i: int, count: int) -> Vector2:
	var per_row := mini(ROW, count)
	@warning_ignore("integer_division")
	var row := i / ROW
	var in_row := i % ROW
	return Vector2(STAGE.x / 2.0 + (in_row - (per_row - 1) / 2.0) * SLOT_GAP - GanjifaCard.DIAMETER / 2.0,
		FIRST_ROW_Y + row * ROW_GAP)
