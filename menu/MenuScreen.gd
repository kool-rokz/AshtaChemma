class_name MenuScreen
extends VBoxContainer

## One page of the main menu (home, join, lobby, settings...). Screens are views: they
## build their controls, read the session, and say what the player wants through two
## signals; the menu shell (StartScreen) does the navigating and the connecting.
##   navigate(screen, args)   show another screen (StartScreen's registry names)
##   action(name, args)       something for the shell to do: "host", "join", "leave"...
## The shell hands each screen `net` (the NetSession) and `stage` (the courtyard behind
## the menu, a MenuStage; its calls do nothing when there's no 3D) before it's added.
## Replace a screen by registering another MenuScreen under the same name.
## The page's main buttons (Back, Join, Start...) go in `footer` (add_footer): the shell
## pins it under the scrolling page, so they're always in view, even on small screens.

signal navigate(screen: StringName, args: Dictionary)
signal action(name: StringName, args: Dictionary)

var net: NetSession
var stage: MenuStage
## What the shell passed when showing this screen.
var args: Dictionary = {}
## Buttons pinned under the page (shown by the shell; freed with the screen).
var footer := HBoxContainer.new()

func _init() -> void:
	add_theme_constant_override("separation", 14)
	footer.add_theme_constant_override("separation", 12)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(footer):
		footer.queue_free()

## Pins buttons under the page, sharing its width.
func add_footer(buttons: Array) -> void:
	for b: Control in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(b)

## The control a pad / keyboard player starts on (null = none).
func first_focus() -> Control:
	return null

## B / Esc / the Back button. Default: back to the home screen.
func go_back() -> void:
	navigate.emit(&"home", {})

## A figure was picked in the courtyard (the stage's figures can be clicked).
func on_figure_clicked(_figure: String) -> void:
	pass
