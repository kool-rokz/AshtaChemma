class_name GanjifaHand
extends Control

## A hand of round Ganjifa cards fanned along the bottom of the screen, peeking up.
##   Hover a card (anywhere in its column of the hand, or over the raised card) to lift
##   it and read its rule; it drops once the pointer leaves the hand. The hover areas
##   are fixed, not the moving cards, so a rising card can't flicker.
##   Click: card_clicked(index). Right-click / Esc while a card is chosen: cancel_requested.
##   Touch (no hover): the first tap lifts a card to read, a second tap clicks it.
##   Keyboard / pad: cards_toggle (C / Y) goes to the hand, pick_prev / pick_next step
##   through it, pick_confirm clicks, pick_cancel (or cards_toggle) leaves.
##   Laid out from the screen's size (and again when it changes), centred a little left
##   of the middle, clear of the throw panel.
##   A chosen card (set_chosen) sits raised and glowing, its rule in the corner, clear of
##   the board where its targets are picked.
## Only shows cards and reports clicks; CardHUD decides what they mean.

signal card_clicked(index: int)
signal cancel_requested

const SPACING := 100.0
## Share of a resting card that peeks above the bottom of the screen.
const PEEK := 0.5
## The hand's centre sits this far left of the screen's middle (the throw panel is right).
const CENTRE_SHIFT := 40.0
## Seconds a played card spends flying in, held for reading, and flying to the pile.
const PLAY_IN := 0.4
const PLAY_HOLD := 1.1
const PLAY_OUT := 0.45
const PLAY_TIME := PLAY_IN + PLAY_HOLD + PLAY_OUT

var _cards: Array[GanjifaCard] = []
var _blocked: Array[String] = []
var _hovered: GanjifaCard
## Keyboard / pad: the hand has the focus (the hovered card is the one in focus).
var _pad_focus := false
var _chosen: GanjifaCard
var _info: PanelContainer
var _info_label: Label
## Card id -> where its card last sat on screen (a played card flies from there).
var _last_centres: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = _screen()
	_info = PanelContainer.new()
	_info.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.GOLD))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label = HudStyle.label("", 16)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size.x = 260
	_info.add_child(_info_label)
	_info.visible = false
	add_child(_info)
	get_viewport().size_changed.connect(func():
		size = _screen()
		_layout(false)
		_show_info())

func centre_x() -> float:
	return _screen().x / 2.0 - CENTRE_SHIFT

## Keyboard / pad: is the hand in focus (so arrows and A act on the cards)?
func has_pad_focus() -> bool:
	return _pad_focus

## Keyboard / pad: hand the arrows back to the board (a card's targets are picked there).
func release_pad_focus() -> void:
	if _pad_focus:
		_pad_focus = false
		_hover(null)
func _screen() -> Vector2:
	return get_viewport_rect().size

## Shows `cards` (CardData). face_up false = backs only (a hidden hand). blocked: per
## card, why it can't be played now ("" = it can). chosen: index of the chosen card or -1.
func set_cards(cards: Array, face_up: bool, blocked: Array[String], chosen: int) -> void:
	var same := cards.size() == _cards.size()
	if same:
		for i in cards.size():
			same = same and _cards[i].card == cards[i] and _cards[i].face_up == face_up
	if not same:
		for card in _cards:
			card.queue_free()
		_cards.clear()
		_hovered = null
		_pad_focus = false
		for data in cards:
			var card := GanjifaCard.new(data, face_up)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE # the hand picks (see _card_at)
			add_child(card)
			_cards.append(card)
		move_child(_info, -1)
	_blocked = blocked
	_chosen = _cards[chosen] if chosen >= 0 and chosen < _cards.size() else null
	_layout(same)
	_show_info()

func screen_centre_of(card_id: StringName) -> Vector2:
	return _last_centres.get(card_id, Vector2(centre_x(), _screen().y))

# --- layout ---
func _rest(i: int, n: int) -> Dictionary:
	var mid := (n - 1) / 2.0
	var x := centre_x() + (i - mid) * SPACING - GanjifaCard.DIAMETER / 2.0
	var y := _screen().y - GanjifaCard.DIAMETER * PEEK + pow(i - mid, 2) * 5.0
	return {"position": Vector2(x, y), "rotation": (i - mid) * 0.09, "scale": Vector2.ONE}

## Hovered: lifted right up and enlarged so it can be read.
func _lifted(i: int, n: int) -> Dictionary:
	var rest := _rest(i, n)
	return {"position": Vector2(rest["position"].x, _screen().y - GanjifaCard.DIAMETER - 70), "rotation": 0.0, "scale": Vector2.ONE * 1.3}

## Chosen (its target is being picked): raised just above the others, upright.
func _raised(i: int, n: int) -> Dictionary:
	var rest := _rest(i, n)
	return {"position": rest["position"] - Vector2(0, 36), "rotation": 0.0, "scale": Vector2.ONE * 1.08}

func _pose_for(card: GanjifaCard, i: int, n: int) -> Dictionary:
	if card == _hovered and _chosen == null:
		return _lifted(i, n)
	if card == _chosen or card == _hovered:
		return _raised(i, n)
	return _rest(i, n)

func _layout(animate: bool) -> void:
	var n := _cards.size()
	for i in n:
		var card := _cards[i]
		var pose := _pose_for(card, i, n)
		card.z_index = 10 if card == _hovered or card == _chosen else i
		card.modulate = Color(1, 1, 1, 1) if i >= _blocked.size() or _blocked[i] == "" or not card.face_up else Color(0.6, 0.6, 0.6, 1)
		if animate:
			var t := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			for key in pose:
				t.tween_property(card, key, pose[key], 0.2)
		else:
			for key in pose:
				card.set(key, pose[key])
		card.glow = 1.0 if card == _chosen else (0.5 if card == _hovered else 0.0)
		_last_centres[card.card.id if card.card else &""] = pose["position"] + Vector2.ONE * GanjifaCard.DIAMETER / 2.0

func _column_x(i: int, n: int) -> float:
	return centre_x() + (i - (n - 1) / 2.0) * SPACING

## The card the pointer is over: its fixed column in the strip at the bottom, or the
## raised card itself (so it stays up while the pointer follows it).
func _card_at(point: Vector2) -> GanjifaCard:
	var n := _cards.size()
	if n == 0:
		return null
	if _hovered and _cards.has(_hovered):
		var i := _cards.find(_hovered)
		var pose := _pose_for(_hovered, i, n)
		var centre: Vector2 = pose["position"] + Vector2.ONE * GanjifaCard.DIAMETER / 2.0
		var radius: float = GanjifaCard.DIAMETER / 2.0 * pose["scale"].x
		var in_column := absf(point.x - _column_x(i, n)) <= SPACING / 2.0 and point.y >= centre.y
		if point.distance_to(centre) <= radius or in_column:
			return _hovered
	if point.y < _screen().y - GanjifaCard.DIAMETER * PEEK - 6.0:
		return null
	var index := roundi((point.x - _column_x(0, n)) / SPACING)
	if index < 0 or index >= n or absf(point.x - _column_x(index, n)) > GanjifaCard.DIAMETER / 2.0:
		return null
	return _cards[index]

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _cards.is_empty():
		return
	if event is InputEventMouseMotion:
		if not GameInput.is_touch(): # a touch drag isn't hovering
			_hover(_card_at(event.position))
	elif event is InputEventMouseButton and event.pressed:
		var card := _card_at(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and _chosen:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.button_index != MOUSE_BUTTON_LEFT:
			return
		elif card and GameInput.is_touch() and card != _hovered:
			_hover(card) # touch: the first tap shows the card, the next one plays it
			get_viewport().set_input_as_handled()
		elif card:
			card_clicked.emit(_cards.find(card))
			get_viewport().set_input_as_handled()
		elif GameInput.is_touch():
			_hover(null) # a tap elsewhere puts the card back
	elif event.is_action_pressed("pick_cancel") and _chosen:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
	else:
		_pad_input(event)

func _hover(card: GanjifaCard) -> void:
	if card != _hovered:
		if card:
			Sound.play(&"card_hover")
		_hovered = card
		_layout(true)
		_show_info()

## Keyboard / pad: go to the hand, step along it, click, leave.
func _pad_input(event: InputEvent) -> void:
	if event.is_action_pressed("cards_toggle"):
		_pad_focus = not _pad_focus and _chosen == null
		_hover(_cards[0] if _pad_focus else null)
	elif not _pad_focus:
		return
	elif event.is_action_pressed("pick_next", true) or event.is_action_pressed("pick_prev", true):
		var step := 1 if event.is_action_pressed("pick_next", true) else -1
		_hover(_cards[wrapi(_cards.find(_hovered) + step, 0, _cards.size())])
	elif event.is_action_pressed("pick_confirm"):
		if _hovered:
			card_clicked.emit(_cards.find(_hovered))
	elif event.is_action_pressed("pick_cancel"):
		_pad_focus = false
		_hover(null)
	else:
		return
	get_viewport().set_input_as_handled()

func _show_info() -> void:
	var card := _hovered if _hovered else _chosen
	_info.visible = card != null and card.face_up and card.card != null
	if not _info.visible:
		return
	var i := _cards.find(card)
	var look := Ganjifa.look(card.card)
	var text := "%s  ·  %s\n%s" % [card.card.title, look["avatar"], card.card.description]
	if i < _blocked.size() and _blocked[i] != "":
		text += "\n(" + _blocked[i] + ")"
	_info_label.text = text
	_info.reset_size()
	if _chosen:
		# Picking a target: keep the rule in the corner, off the board
		_info.position = Vector2(16, _screen().y - _info.size.y - 16)
		return
	var x: float = _lifted(i, _cards.size())["position"].x + GanjifaCard.DIAMETER / 2.0 - _info.size.x / 2.0
	_info.position = Vector2(clampf(x, 16, _screen().x - _info.size.x - 330), _screen().y - GanjifaCard.DIAMETER * 1.3 - 70 - _info.size.y - 14)

# --- a card being played ---
## Shows a played card for everyone: it flies from `from` (screen point) to the middle of
## the screen at full size with its rule, holds there so it can be read, then spins down
## onto `pile` (the discard pile's screen point). Returns when it has landed.
func show_played(card: CardData, from: Vector2, pile: Vector2) -> void:
	var flying := GanjifaCard.new(card, true)
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.position = from - flying.size / 2.0
	flying.z_index = 50
	add_child(flying)
	var middle := _screen() / 2.0 - flying.size / 2.0 + Vector2(0, -40)
	Sound.play(&"card_play")
	var t := flying.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(flying, "position", middle, PLAY_IN)
	t.tween_property(flying, "scale", Vector2.ONE * 2.1, PLAY_IN)
	await t.finished
	var caption := HudStyle.label(card.description, 21, HudStyle.TEXT)
	caption.add_theme_font_override("font", GameFonts.body_bold())
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A shadow, not an outline: Laila SemiBold's outlines render as solid boxes
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.add_theme_constant_override("shadow_outline_size", 6)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.size = Vector2(560, 30)
	caption.position = Vector2(_screen().x / 2.0 - 280, middle.y + flying.size.y * 1.6 + 16)
	add_child(caption)
	await get_tree().create_timer(PLAY_HOLD).timeout
	caption.queue_free()
	var down := flying.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	down.tween_property(flying, "position", pile - flying.size / 2.0, PLAY_OUT)
	down.tween_property(flying, "scale", Vector2.ONE * 0.35, PLAY_OUT)
	down.tween_property(flying, "rotation", 2.6, PLAY_OUT)
	await down.finished
	Sound.play(&"card_land")
	flying.queue_free()
