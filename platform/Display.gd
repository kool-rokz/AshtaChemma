class_name Display
extends RefCounted

## Screen shape and size for every screen: the UI is laid out for 1280x720 and scaled
## (Settings.ui_scale) with the window, keeping its aspect "expand" so wider or taller
## screens (phones, tablets) get more room instead of black bars. Screens lay out
## inside safe_rect() (clear of notches and rounded corners) and redo their layout on
## the viewport's size_changed. Set at runtime, so project.godot stays as it is.

## Applies the stretch settings to the window. Safe to call from every screen.
static func apply(tree: SceneTree) -> void:
	var window := tree.root
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor = Settings.ui_scale()

## The part of the viewport clear of notches and rounded corners, in UI units.
static func safe_rect(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	if not Platform.is_mobile():
		return visible
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0.0:
		return visible
	var scale := visible.size / screen
	return Rect2(visible.position + safe.position * scale, safe.size * scale)
