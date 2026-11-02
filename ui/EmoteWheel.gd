class_name EmoteWheel
extends Control

## The emote button (bottom left) and its little fan of emotes (Emotes.all(), from emotes/data/). Click,
## tap, the emote_toggle action (E / pad X) or pad focus to pick one; it reports
## `chosen(id)` and greys out for Emotes.COOLDOWN. Works on anyone's turn: taunting is
## for when it isn't yours. A view only (the HUD passes the choice to MatchController).

signal chosen(emote_id: String)

const BUTTON_SIZE := Vector2(64, 40)
const ITEM_SIZE := Vector2(116, 38)

var _toggle: Button
var _panel: PanelContainer
var _items: Array[Button] = []
var _cooldown_left := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = HudStyle.button("Emote", BUTTON_SIZE)
	_toggle.name = "EmoteButton"
	_toggle.pressed.connect(toggle)
	add_child(_toggle)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	_panel.visible = false
	add_child(_panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_panel.add_child(grid)
	for emote in Emotes.all():
		var item := HudStyle.button(emote.label, ITEM_SIZE)
		item.name = "Emote_" + String(emote.id)
		item.focus_mode = Control.FOCUS_ALL # pads move between them
		item.pressed.connect(_pick.bind(String(emote.id)))
		grid.add_child(item)
		_items.append(item)

## Lays the button out at `at` (its bottom-left corner), the fan opening upwards.
func place(at: Vector2) -> void:
	_toggle.position = at - Vector2(0, BUTTON_SIZE.y)
	_panel.reset_size()
	_panel.position = _toggle.position - Vector2(0, _panel.size.y + 8)

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_panel.reset_size()
		_panel.position = _toggle.position - Vector2(0, _panel.size.y + 8)
		GameInput.offer_focus(get_tree(), _items[0])

func is_open() -> bool:
	return _panel.visible

func _pick(emote_id: String) -> void:
	_panel.visible = false
	_cooldown_left = Emotes.COOLDOWN
	_set_ready(false)
	chosen.emit(emote_id)

func _set_ready(ready: bool) -> void:
	_toggle.disabled = not ready
	_toggle.text = "Emote" if ready else "..."
	if not ready:
		_panel.visible = false

func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
		if _cooldown_left <= 0.0:
			_set_ready(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("emote_toggle") and not _toggle.disabled:
		toggle()
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("pick_cancel"):
		_panel.visible = false
		get_viewport().set_input_as_handled()
