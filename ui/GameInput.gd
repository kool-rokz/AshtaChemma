class_name GameInput
extends Node

## The game's input actions, and which kind of device the player is using now.
## Every action works by mouse or touch AND by keyboard or gamepad (Joy-Con or pad):
##   shell_hold          Space / A           hold to shake the shells, let go to throw
##   shell_left/right/up/down  arrows / left stick   shake while holding
##   pick_prev/next      Left, Right / d-pad left, right   the pawn, square or card in focus
##   pick_confirm        Enter / A           move that pawn, pick that target or card
##   pick_cancel         Esc, Backspace / B  cancel a card, leave the hand
##   throw_prev/next     Up, Down / d-pad up, down   which throw to use
##   cards_toggle        C / Y               go to (or leave) your hand of cards
##   log_toggle          Tab / Back (-)      the game log
## Actions are added in code (not project.godot), the first time a screen calls ensure().
## Menus use Godot's own ui_* actions and focus; screens hand their first button to
## offer_focus() so a pad (which has no pointer) always has something to act on.
## One node under the root, like NetSession; views read `device` and `changed`.

enum Device { MOUSE, TOUCH, KEYS, PAD }

signal changed(device: Device)

const NODE_NAME := "GameInput"
const STICK_DEADZONE := 0.5

static var device: Device = Device.MOUSE

var _offered: Control

static var _instance: GameInput

static func ensure(tree: SceneTree) -> GameInput:
	_add_actions()
	if _instance == null or not is_instance_valid(_instance):
		_instance = GameInput.new()
		_instance.name = NODE_NAME
		# Deferred: screens call this from _ready, while the root is busy adding children
		tree.root.add_child.call_deferred(_instance)
		if DisplayServer.is_touchscreen_available() and Platform.is_mobile():
			device = Device.TOUCH
	return _instance

static func find(_tree: SceneTree) -> GameInput:
	return _instance if _instance and is_instance_valid(_instance) else null

## Touch has no hover: a first tap shows what a second tap would do.
static func is_touch() -> bool:
	return device == Device.TOUCH

## Keyboard or pad: things are picked by focus, not pointed at.
static func is_focus_driven() -> bool:
	return device == Device.KEYS or device == Device.PAD

## Words for the device in use: hints say "click", "tap" or "press A" as fits.
static func pick(mouse: String, touch: String, pad: String) -> String:
	if device == Device.TOUCH:
		return touch
	return pad if is_focus_driven() else mouse

## A screen's first control for pad/keyboard players: focused now if they're using one,
## else as soon as they pick one up. Mouse and touch players never see the focus ring.
static func offer_focus(tree: SceneTree, control: Control) -> void:
	var node := find(tree)
	if node:
		node._offered = control
	if is_focus_driven() and control and control.is_inside_tree() and control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	var now := device
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		now = Device.TOUCH
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		# Touch screens also send emulated mouse events; those don't switch away from touch
		if device != Device.TOUCH or not DisplayServer.is_touchscreen_available():
			now = Device.MOUSE
	elif event is InputEventKey and event.pressed:
		now = Device.KEYS
	elif event is InputEventJoypadButton and event.pressed:
		now = Device.PAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE:
		now = Device.PAD
	if now == device:
		return
	device = now
	if is_focus_driven() and get_viewport().gui_get_focus_owner() == null \
			and _offered and is_instance_valid(_offered) and _offered.is_visible_in_tree():
		_offered.grab_focus()
	changed.emit(device)

# --- actions ---
static func _add_actions() -> void:
	var bindings := {
		"shell_hold": [_key(KEY_SPACE), _pad_button(JOY_BUTTON_A)],
		"shell_left": [_key(KEY_LEFT), _pad_axis(JOY_AXIS_LEFT_X, -1.0)],
		"shell_right": [_key(KEY_RIGHT), _pad_axis(JOY_AXIS_LEFT_X, 1.0)],
		"shell_up": [_key(KEY_UP), _pad_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"shell_down": [_key(KEY_DOWN), _pad_axis(JOY_AXIS_LEFT_Y, 1.0)],
		"pick_prev": [_key(KEY_LEFT), _pad_button(JOY_BUTTON_DPAD_LEFT)],
		"pick_next": [_key(KEY_RIGHT), _pad_button(JOY_BUTTON_DPAD_RIGHT)],
		"pick_confirm": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad_button(JOY_BUTTON_A)],
		"pick_cancel": [_key(KEY_ESCAPE), _key(KEY_BACKSPACE), _pad_button(JOY_BUTTON_B)],
		"throw_prev": [_key(KEY_UP), _pad_button(JOY_BUTTON_DPAD_UP)],
		"throw_next": [_key(KEY_DOWN), _pad_button(JOY_BUTTON_DPAD_DOWN)],
		"cards_toggle": [_key(KEY_C), _pad_button(JOY_BUTTON_Y)],
		"log_toggle": [_key(KEY_TAB), _pad_button(JOY_BUTTON_BACK)],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.15)
		for event in bindings[action]:
			InputMap.action_add_event(action, event)

static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

static func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

static func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
