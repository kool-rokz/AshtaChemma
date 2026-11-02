class_name HomeScreen
extends MenuScreen

## The first screen: your name, your figure (step through them, or click one in the
## courtyard), then Host / Join, How to play, Settings, Credits.
## Actions: "host". Name and figure are saved in Settings as they change.

var _name_edit: LineEdit
var _figure_label: Label
var _first: Control

func _ready() -> void:
	add_child(MenuStyle.title("Ashta Chemma", 48))
	add_child(MenuStyle.label("Throw the cowries. Race your pawns home.", 17, MenuStyle.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var system_name := Platform.system_player_name()
	_name_edit = MenuStyle.line_edit(system_name if system_name != "" else Settings.get_value(Settings.PLAYER, Settings.NAME, ""), "Your name")
	_name_edit.name = "PlayerName"
	_name_edit.max_length = GameConfig.NAME_MAX_LENGTH
	_name_edit.editable = system_name == "" # the platform's account name, when it has one
	_name_edit.text_changed.connect(func(text: String): Settings.set_value(Settings.PLAYER, Settings.NAME, text.strip_edges()))
	add_child(MenuStyle.row("Your name", _name_edit))
	_name_edit.custom_minimum_size.x = 240

	var prev := MenuStyle.button("<", 56)
	prev.name = "PrevFigure"
	prev.pressed.connect(_step_figure.bind(-1))
	_figure_label = MenuStyle.label("", 22, MenuStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_figure_label.add_theme_font_override("font", GameFonts.title())
	_figure_label.custom_minimum_size.x = 140
	_figure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var next := MenuStyle.button(">", 56)
	next.name = "NextFigure"
	next.pressed.connect(_step_figure.bind(1))
	var chooser := HBoxContainer.new()
	chooser.add_theme_constant_override("separation", 8)
	chooser.add_child(prev)
	chooser.add_child(_figure_label)
	chooser.add_child(next)
	add_child(MenuStyle.row("Your pawns", chooser))
	add_child(MenuStyle.note("Or click a figure in the courtyard."))

	var host := MenuStyle.button("Host a game")
	host.name = "HostGame"
	host.pressed.connect(func(): action.emit(&"host", {}))
	host.visible = net.transport.can_host() # browsers can't accept connections
	add_child(host)
	var join := MenuStyle.button("Join a game")
	join.name = "JoinGame"
	join.pressed.connect(func(): navigate.emit(&"join", {}))
	add_child(join)
	_first = host if host.visible else join
	var how := MenuStyle.button("How to play")
	how.name = "HowToPlay"
	how.pressed.connect(func(): navigate.emit(&"how_to_play", {}))
	var settings := MenuStyle.button("Settings")
	settings.name = "Settings"
	settings.pressed.connect(func(): navigate.emit(&"settings", {}))
	var credits := MenuStyle.button("Credits")
	credits.name = "Credits"
	credits.pressed.connect(func(): navigate.emit(&"credits", {}))
	add_child(MenuStyle.button_row([how, settings, credits]))
	for b in [how, settings, credits]:
		b.add_theme_font_size_override("font_size", 17)

	add_child(MenuStyle.error(String(args.get("error", ""))))
	add_child(MenuStyle.label("v" + GameConfig.GAME_VERSION, 13, MenuStyle.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_show_figure(false)
	stage.show_lineup(_figure())

func first_focus() -> Control:
	return _first

## Home is the top: Back does nothing here.
func go_back() -> void:
	pass

func on_figure_clicked(figure: String) -> void:
	_set_figure(figure)

static func saved_figure() -> String:
	return GameConfig.figure_or_default(Settings.get_value(Settings.PLAYER, Settings.FIGURE, ""))

func _figure() -> String:
	return saved_figure()

func _step_figure(step: int) -> void:
	var ids: Array = GameConfig.FIGURES.keys()
	_set_figure(ids[wrapi(ids.find(_figure()) + step, 0, ids.size())])

func _set_figure(figure: String) -> void:
	if figure == _figure():
		stage.select_figure(figure) # a little hello again
		return
	Settings.set_value(Settings.PLAYER, Settings.FIGURE, figure)
	_show_figure(true)

func _show_figure(react: bool) -> void:
	_figure_label.text = GameConfig.FIGURES[_figure()]
	if react:
		stage.select_figure(_figure())
