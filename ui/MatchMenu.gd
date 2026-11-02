class_name MatchMenu
extends CanvasLayer

## The menu during a match (the HUD's Menu button, Esc, F10 or pad Start): music and
## effects volume, Resume, and Leave match (asked twice, so it can't happen by
## accident). Online the match carries on underneath; offline nothing moves anyway
## while you're in here, since the HUD stops throws. A view: it only reports what the
## player chose (closed, leave_requested); the HUD decides what that means.

signal closed
signal leave_requested

const LAYER := 19
const CONFIRM_TIME := 3.0

var _panel: PanelContainer
var _resume: Button
var _leave: Button
var _confirming := false

func _init() -> void:
	layer = LAYER
	visible = false
	var root := Control.new()
	root.theme = MenuStyle.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var veil := ColorRect.new()
	veil.color = Color(0.05, 0.03, 0.02, 0.6)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close()) # a click outside the panel closes it
	root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	box.add_child(MenuStyle.title("Menu", 36))
	box.add_child(MenuStyle.row("Music", MenuStyle.volume_slider(Settings.MUSIC_VOLUME, &"ui_click")))
	box.add_child(MenuStyle.row("Effects", MenuStyle.volume_slider(Settings.EFFECTS_VOLUME, &"turn_yours")))
	_resume = MenuStyle.button("Resume")
	_resume.name = "Resume"
	_resume.pressed.connect(close)
	box.add_child(_resume)
	_leave = MenuStyle.button("Leave match")
	_leave.name = "LeaveMatch"
	_leave.pressed.connect(_on_leave)
	box.add_child(_leave)

func open() -> void:
	_set_confirming(false)
	visible = true
	GameInput.offer_focus(get_tree(), _resume)

func close() -> void:
	if visible:
		visible = false
		closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _on_leave() -> void:
	if _confirming:
		leave_requested.emit()
		return
	_set_confirming(true)
	get_tree().create_timer(CONFIRM_TIME).timeout.connect(func(): _set_confirming(false))

func _set_confirming(on: bool) -> void:
	_confirming = on
	_leave.text = "Really leave? Press again" if on else "Leave match"

## While open, B / Esc / Start close it (and the match behind gets no input from them).
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pick_cancel") or event.is_action_pressed("menu_toggle")):
		close()
		get_viewport().set_input_as_handled()
