class_name HudStyle
extends RefCounted

## The match UI's look, shared by the HUD, the card UI and the art labs: dark cloth
## panels with an ochre border, palm-leaf scrolls, warm cream text, figure portraits.

const PANEL_BG := Color(0.1, 0.07, 0.05, 0.82)
const BORDER := Color(0.72, 0.52, 0.25)
const GOLD := Color(0.86, 0.68, 0.28)
const TEXT := Color(0.97, 0.92, 0.82)
const MUTED := Color(0.78, 0.7, 0.58)
const WARN := Color(1.0, 0.62, 0.4)
const LEAF_BG := Color(0.86, 0.76, 0.55, 0.96)
const LEAF_BORDER := Color(0.45, 0.3, 0.15)
const LEAF_TEXT := Color(0.2, 0.12, 0.06)

static func panel(border: Color = BORDER, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	return style

## A palm-leaf scroll (the event log).
static func leaf() -> StyleBoxFlat:
	var style := panel(LEAF_BORDER)
	style.bg_color = LEAF_BG
	return style

static func label(text: String, font_size: int, color: Color = TEXT, title: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if title:
		result.add_theme_font_override("font", GameFonts.title())
	return result

## A button in the panel look (gold border when hovered or pressed).
static func button(text: String, min_size: Vector2 = Vector2(0, 40)) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size = min_size
	result.add_theme_stylebox_override("normal", panel())
	result.add_theme_stylebox_override("hover", panel(GOLD, 3))
	result.add_theme_stylebox_override("pressed", panel(GOLD, 3))
	result.add_theme_stylebox_override("focus", panel(Color(1, 1, 1), 3)) # pad / keyboard focus
	result.pressed.connect(func(): Sound.play(&"ui_click"))
	result.add_theme_stylebox_override("disabled", panel(Color(BORDER, 0.3), 1))
	result.add_theme_color_override("font_color", TEXT)
	result.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	return result

## A small 3D portrait of a player's figure, idling, in their lacquer.
static func figure_portrait(figure: String, color_name: String, portrait_size: Vector2i = Vector2i(56, 56)) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = portrait_size
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 28
	camera.position = Vector3(0.0, 0.42, 1.15)
	camera.rotation_degrees.x = -10
	viewport.add_child(camera)
	ShellModel.add_lighting(viewport)
	var fig := PawnFigure.create(figure, color_name)
	fig.rotation.y = PI * 0.82
	viewport.add_child(fig)
	return container
