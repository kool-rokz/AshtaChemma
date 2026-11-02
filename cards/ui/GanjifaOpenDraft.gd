class_name GanjifaOpenDraft
extends Control

## The open draft, seen by everyone: one face-up pool of Ganjifa cards in the middle,
## each player's picks in a strip along the bottom, and whose pick it is. Players take
## turns (snake order); every pick flies from the pool into the taker's strip, so the
## table can see (and should remember) who took what.
##   Hover a card to read it; click to take it (on your pick). Touch: tap to read, tap
##   again to take. Keyboard / pad: pick_prev / pick_next to choose, pick_confirm to take.
## A view only: show_state() draws CardManager's draft state, card_chosen reports a pick
## (CardHUD sends it to MatchController). Laid out on a 1280x720 stage scaled to fit.

signal card_chosen(slot: int)

const STAGE := Vector2(1280, 720)
const POOL_SCALE := 0.72
const POOL_COLUMNS := 8
const POOL_GAP := Vector2(112, 112)
const POOL_TOP := 132.0
const STRIP_TOP := 512.0
const STRIP_SCALE := 0.42
const STRIP_GAP := 58.0

var _stage: Control
var _title: Label
var _status: Label
var _info: Label
var _slots: Array[GanjifaCard] = []
var _taken: Array[int] = []
## Player -> cards in their strip so far.
var _strip_counts: Dictionary = {}
var _strip_labels: Array[Label] = []
var _strip_frames: Array[Panel] = []
var _can_pick := false
var _picker := -1
## Keyboard / pad / touch: the slot shown (and taken on confirm or a second tap), -1 = none.
var _focus := -1
var _players := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it can be clicked meanwhile
	var veil := ColorRect.new()
	veil.color = Color(0.05, 0.03, 0.02, 0.85)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	_stage = Control.new()
	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_title = _centred_label("Open draft: take turns, everyone sees every pick", 30, HudStyle.TEXT, 36, true)
	_status = _centred_label("", 22, HudStyle.TEXT, 80, true)
	_info = _centred_label("", 16, HudStyle.MUTED, 470, false)
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	var screen := get_viewport_rect().size
	position = Vector2.ZERO
	size = screen
	var fit := minf(screen.x / STAGE.x, screen.y / STAGE.y)
	_stage.scale = Vector2.ONE * fit
	_stage.position = (screen - STAGE * fit) / 2.0

func _centred_label(text: String, font_size: int, color: Color, y: float, title_font: bool) -> Label:
	var label := HudStyle.label(text, font_size, color, title_font)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(STAGE.x, font_size * 1.5)
	label.position = Vector2(0, y)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(label)
	return label

## Draws the draft: pool (CardData per slot), taken (who took each slot, -1 = still
## there), picker (whose pick, -1 = done), names/colors per player, can_pick (this
## screen may take now), you (this screen's seat online, -1 offline).
func show_state(pool: Array, taken: Array[int], picker: int, names: Array, colors: Array, can_pick: bool, you: int) -> void:
	if _slots.is_empty():
		_build(pool, names, colors)
	for slot in taken.size():
		if taken[slot] >= 0 and _taken[slot] < 0:
			_move_to_strip(slot, taken[slot])
	_taken = taken.duplicate()
	_picker = picker
	_can_pick = can_pick
	for p in _strip_frames.size():
		_strip_frames[p].modulate.a = 1.0 if p == picker else 0.0
	if picker < 0:
		_status.text = "Everyone has their cards. Remember who took what!"
		_status.add_theme_color_override("font_color", HudStyle.TEXT)
		_set_focus(-1)
		return
	var who: String = names[picker]
	if you >= 0: # online: this screen picks only for its own seat
		_status.text = "Your pick: take a card" if picker == you else "%s is picking..." % who
	else: # one screen passed round the table
		_status.text = "%s's pick: take a card" % who
	_status.add_theme_color_override("font_color", colors[picker])
	if can_pick and picker == you:
		Sound.play(&"turn_yours", -6.0)
	if not _can_pick or (_focus >= 0 and _taken[_focus] >= 0):
		_set_focus(-1)
	if _can_pick and _focus < 0 and GameInput.is_focus_driven():
		_set_focus(_next_free(-1, 1))

func _build(pool: Array, names: Array, colors: Array) -> void:
	_players = names.size()
	for slot in pool.size():
		var card := GanjifaCard.new(pool[slot], true)
		card.name = "Pool%d" % (slot + 1)
		card.scale = Vector2.ONE * POOL_SCALE
		card.position = _pool_position(slot, pool.size())
		card.modulate.a = 0.0
		_stage.add_child(card)
		card.create_tween().tween_property(card, "modulate:a", 1.0, 0.3).set_delay(slot * 0.03)
		card.mouse_entered.connect(func():
			if not GameInput.is_touch():
				_show_rule(slot))
		card.gui_input.connect(_on_card_input.bind(slot))
		_slots.append(card)
		_taken.append(-1)
		Sound.play(&"card_deal", -6.0, slot * 0.03)
	var width := STAGE.x / _players
	for p in _players:
		var frame := Panel.new()
		frame.add_theme_stylebox_override("panel", HudStyle.panel(colors[p], 3))
		frame.position = Vector2(p * width + 8, STRIP_TOP - 8)
		frame.size = Vector2(width - 16, STAGE.y - STRIP_TOP)
		frame.modulate.a = 0.0
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(frame)
		_strip_frames.append(frame)
		var label := HudStyle.label(names[p], 18, colors[p], true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(width, 28)
		label.position = Vector2(p * width, STRIP_TOP)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(label)
		_strip_labels.append(label)
		_strip_counts[p] = 0

func _pool_position(slot: int, count: int) -> Vector2:
	var per_row := mini(POOL_COLUMNS, count)
	@warning_ignore("integer_division")
	var row := slot / POOL_COLUMNS
	var in_row := slot % POOL_COLUMNS
	var rows_total := ceili(count / float(POOL_COLUMNS))
	var in_this_row := per_row if row < rows_total - 1 else count - row * POOL_COLUMNS
	var size_px := GanjifaCard.DIAMETER * POOL_SCALE
	return Vector2(STAGE.x / 2.0 + (in_row - (in_this_row - 1) / 2.0) * POOL_GAP.x - size_px / 2.0,
		POOL_TOP + row * POOL_GAP.y)

func _strip_position(player: int, index: int) -> Vector2:
	var width := STAGE.x / maxi(_players, 1)
	var size_px := GanjifaCard.DIAMETER * STRIP_SCALE
	var start := player * width + width / 2.0 - 2.0 * STRIP_GAP - size_px / 2.0
	return Vector2(start + index * STRIP_GAP, STRIP_TOP + 40.0)

func _move_to_strip(slot: int, player: int) -> void:
	var card := _slots[slot]
	var index: int = _strip_counts.get(player, 0)
	_strip_counts[player] = index + 1
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.glow = 0.0
	card.z_index = 5
	Sound.play(&"card_deal")
	var t := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "position", _strip_position(player, index), 0.45)
	t.tween_property(card, "scale", Vector2.ONE * STRIP_SCALE, 0.45)

func _on_card_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if GameInput.is_touch() and _focus != slot:
		_set_focus(slot) # touch: the first tap shows the card, the next one takes it
		return
	_take(slot)

func _take(slot: int) -> void:
	if not _can_pick or slot < 0 or slot >= _taken.size() or _taken[slot] >= 0:
		return
	_can_pick = false # until the pick comes back as the new state
	card_chosen.emit(slot)

func _show_rule(slot: int) -> void:
	var card := _slots[slot].card
	if card:
		_info.text = "%s  ·  %s  ·  %s" % [card.title, Ganjifa.look(card)["avatar"], card.description]

func _set_focus(slot: int) -> void:
	if _focus >= 0 and _focus < _slots.size() and _taken[_focus] < 0:
		_slots[_focus].glow = 0.0
	_focus = slot
	if slot >= 0:
		_slots[slot].glow = 0.6
		_show_rule(slot)
		Sound.play(&"card_hover")

func _next_free(from: int, step: int) -> int:
	var n := _taken.size()
	for k in range(1, n + 1):
		var slot := wrapi(from + step * k, 0, n)
		if _taken[slot] < 0:
			return slot
	return -1

func _input(event: InputEvent) -> void:
	if not _can_pick or _slots.is_empty():
		return
	if event.is_action_pressed("pick_next", true) or event.is_action_pressed("pick_prev", true):
		_set_focus(_next_free(_focus, 1 if event.is_action_pressed("pick_next", true) else -1))
	elif event.is_action_pressed("pick_confirm") and _focus >= 0:
		_take(_focus)
	else:
		return
	get_viewport().set_input_as_handled()

## The draft is over: hold a moment so the last pick is seen, then fade away.
func finish() -> void:
	_can_pick = false
	await get_tree().create_timer(1.6).timeout
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	await t.finished
	queue_free()
