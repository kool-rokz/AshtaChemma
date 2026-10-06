class_name MenuWidgets
extends RefCounted

## Shared look for the menu screens (StartScreen, LobbyView).

const TEXT := Color(0.92, 0.92, 0.95)
const MUTED := Color(0.7, 0.7, 0.75)
const ERROR := Color(0.95, 0.45, 0.4)
const HIGHLIGHT := Color(1.0, 0.85, 0.4)

static func label(text: String, font_size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.horizontal_alignment = align
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

static func button(text: String, min_size := Vector2(0, 52)) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = min_size
	result.add_theme_font_size_override("font_size", 20)
	return result

static func line_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 18)
	return edit
