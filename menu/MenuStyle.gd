class_name MenuStyle
extends RefCounted

## The menu's look, in one place: a palm-leaf panel with dark ink lettering, lacquered
## wooden buttons with a gold edge, cream fields. theme() is set on the menu's root, so
## every control under it takes this look without per-widget styling; restyle (or
## replace) the menu by changing this file. The helpers below make the controls the
## screens use: all large enough for touch and focusable for pads (B/Esc goes back).

const LEAF := Color(0.87, 0.78, 0.57, 0.97)
const LEAF_EDGE := Color(0.45, 0.3, 0.15)
const INK := Color(0.2, 0.11, 0.05)
const INK_MUTED := Color(0.38, 0.27, 0.16)
const INK_RED := Color(0.55, 0.12, 0.08)
const WOOD := Color(0.42, 0.13, 0.08)
const WOOD_LIGHT := Color(0.55, 0.2, 0.1)
const GOLD := Color(0.88, 0.7, 0.3)
const CREAM := Color(0.98, 0.93, 0.82)
const ERROR := Color(0.7, 0.12, 0.08)
## Touch-sized controls.
const BUTTON_HEIGHT := 52.0
const FIELD_HEIGHT := 46.0

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = GameFonts.body()
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	# Buttons (and option buttons): lacquered wood with a gold edge
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(WOOD, Color(GOLD, 0.6), 2))
		t.set_stylebox("hover", type, _box(WOOD_LIGHT, GOLD, 2))
		t.set_stylebox("pressed", type, _box(WOOD.darkened(0.2), GOLD, 2))
		t.set_stylebox("disabled", type, _box(Color(WOOD, 0.45), Color(GOLD, 0.25), 1))
		t.set_stylebox("focus", type, _ring())
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, CREAM)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_focus_color", type, CREAM)
		t.set_color("font_disabled_color", type, Color(CREAM, 0.45))
		t.set_font_size("font_size", type, 20)
	# Text fields: cream paper
	t.set_stylebox("normal", "LineEdit", _box(CREAM, LEAF_EDGE, 2))
	t.set_stylebox("focus", "LineEdit", _box(CREAM, GOLD.darkened(0.2), 3))
	t.set_stylebox("read_only", "LineEdit", _box(Color(CREAM, 0.6), Color(LEAF_EDGE, 0.5), 1))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK_MUTED, 0.6))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 18)
	# Option lists: dark cloth with cream text
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.12, 0.08, 0.05, 0.98), GOLD, 2))
	t.set_stylebox("hover", "PopupMenu", _box(WOOD_LIGHT, GOLD, 1))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_font_size("font_size", "PopupMenu", 18)
	# Sliders and check boxes
	t.set_stylebox("slider", "HSlider", _box(Color(LEAF_EDGE, 0.5), Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", _box(WOOD, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(WOOD_LIGHT, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("focus", "HSlider", _ring())
	# Check boxes are buttons underneath: no wooden board behind them
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "CheckBox", INK_MUTED)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_focus_color", "CheckBox", INK)
	t.set_stylebox("focus", "CheckBox", _ring())
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("bold_font", "RichTextLabel", GameFonts.body_bold())
	t.set_stylebox("panel", "PanelContainer", leaf())
	_theme = t
	return t

## The palm leaf the screens sit on.
static func leaf() -> StyleBoxFlat:
	var style := _box(LEAF, LEAF_EDGE, 3, 14)
	style.set_content_margin_all(26)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 10
	return style

static func _box(bg: Color, border: Color, width: int, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(8)
	return style

## Pad / keyboard focus: a bright ring, never shown to mouse or touch players
## (GameInput only hands out focus to them).
static func _ring() -> StyleBoxFlat:
	var style := _box(Color(0, 0, 0, 0), Color(1, 0.95, 0.75), 3, 12)
	style.draw_center = false
	style.set_expand_margin_all(3)
	return style

# --- controls ---
static func title(text: String, font_size: int = 40) -> Label:
	var result := label(text, font_size, INK_RED, HORIZONTAL_ALIGNMENT_CENTER)
	result.add_theme_font_override("font", GameFonts.title())
	return result

static func label(text: String, font_size: int = 18, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.horizontal_alignment = align
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

static func note(text: String) -> Label:
	return label(text, 15, INK_MUTED)

static func error(text: String) -> Label:
	var result := label(text, 15, ERROR)
	result.visible = text != ""
	return result

static func button(text: String, min_width: float = 0.0) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(min_width, BUTTON_HEIGHT)
	result.focus_mode = Control.FOCUS_ALL
	result.pressed.connect(func(): Sound.play(&"ui_click"))
	return result

static func line_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, FIELD_HEIGHT)
	return edit

static func options(labels: Array, selected: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(200, FIELD_HEIGHT)
	for text in labels:
		picker.add_item(text)
	picker.select(maxi(0, selected))
	picker.item_selected.connect(func(_i): Sound.play(&"ui_click"))
	return picker

static func slider(value: float) -> HSlider:
	var result := HSlider.new()
	result.custom_minimum_size = Vector2(200, FIELD_HEIGHT)
	result.min_value = 0.0
	result.max_value = 1.0
	result.step = 0.05
	result.value = value
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return result

## A 0-100% volume slider for Settings.AUDIO/key (MUSIC_VOLUME / EFFECTS_VOLUME):
## saves and applies as it moves, and plays `sample` when let go.
static func volume_slider(key: String, sample: StringName) -> HSlider:
	var current := Settings.music_volume() if key == Settings.MUSIC_VOLUME else Settings.effects_volume()
	var result := slider(current)
	result.value_changed.connect(func(v: float):
		Settings.set_value(Settings.AUDIO, key, v)
		Sound.apply_volumes())
	result.drag_ended.connect(func(_changed: bool): Sound.play(sample))
	return result

## A labelled row: the label on the left, the control on the right.
static func row(text: String, control: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var name_label := label(text, 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	box.add_child(control)
	return box

## Buttons side by side, sharing the width.
static func button_row(buttons: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	for b: Button in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(b)
	return box
