extends Control

## Two-step match setup: (1) how many players, (2) each player's name and pawn colour.
## Writes GameConfig.players, then loads the board.

const GAME_SCENE_PATH := "res://MainGame.tscn"
const NAME_MAX_LENGTH := 16

var _content: VBoxContainer
var _player_count: int = GameConfig.MIN_PLAYERS
## Per player: {"name_edit": LineEdit, "color_name": String, "buttons": {color_name: Button}}
var _rows: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.16, 0.19)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.14)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 18)
	panel.add_child(_content)

	_show_player_count_step()

func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()
	_rows.clear()

func _label(text: String, font_size: int, color := Color(0.92, 0.92, 0.95)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(text: String, min_size := Vector2(0, 48)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 20)
	return button

# --- STEP 1: player count ---
func _show_player_count_step() -> void:
	_clear()
	_content.add_child(_label("Ashta Chemma", 44))
	_content.add_child(_label("How many players?", 20, Color(0.7, 0.7, 0.75)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	for count in range(GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS + 1):
		var button := _button(str(count), Vector2(96, 72))
		button.name = "Players%d" % count
		button.add_theme_font_size_override("font_size", 30)
		button.pressed.connect(_show_player_setup_step.bind(count))
		row.add_child(button)
	_content.add_child(row)

# --- STEP 2: names and colours ---
func _show_player_setup_step(count: int) -> void:
	_clear()
	_player_count = count
	_content.add_child(_label("Players", 32))
	_content.add_child(_label("Name each player and pick a pawn colour.", 16, Color(0.7, 0.7, 0.75)))

	var defaults := GameConfig.default_players(count)
	for i in count:
		_content.add_child(_build_player_row(i, defaults[i]["color_name"]))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	var back := _button("Back", Vector2(140, 48))
	back.pressed.connect(_show_player_count_step)
	actions.add_child(back)
	var start := _button("Start game")
	start.name = "StartGame"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_start_game)
	actions.add_child(start)
	_content.add_child(actions)

func _build_player_row(index: int, color_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_edit := LineEdit.new()
	name_edit.name = "Name%d" % (index + 1)
	name_edit.placeholder_text = "Player %d" % (index + 1)
	name_edit.max_length = NAME_MAX_LENGTH
	name_edit.custom_minimum_size = Vector2(0, 44)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 18)
	row.add_child(name_edit)

	var buttons := {}
	for option in GameConfig.COLORS:
		var swatch := Button.new()
		swatch.name = "%s%d" % [option, index + 1]
		swatch.tooltip_text = option
		swatch.custom_minimum_size = Vector2(44, 44)
		swatch.pressed.connect(_pick_color.bind(index, option))
		row.add_child(swatch)
		buttons[option] = swatch

	_rows.append({"name_edit": name_edit, "color_name": color_name, "buttons": buttons})
	_refresh_swatches(index)
	return row

## Picking a colour another player has swaps the two players' colours,
## so every player always has a unique colour (even with all four taken).
func _pick_color(index: int, color_name: String) -> void:
	var previous: String = _rows[index]["color_name"]
	for i in _rows.size():
		if i != index and _rows[i]["color_name"] == color_name:
			_rows[i]["color_name"] = previous
			_refresh_swatches(i)
	_rows[index]["color_name"] = color_name
	_refresh_swatches(index)

func _refresh_swatches(index: int) -> void:
	var row: Dictionary = _rows[index]
	for option in row["buttons"]:
		var selected: bool = option == row["color_name"]
		var button: Button = row["buttons"][option]
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = GameConfig.COLORS[option]
			if not selected:
				style.bg_color = style.bg_color.darkened(0.45 if state != "hover" else 0.25)
			style.set_corner_radius_all(22)
			style.set_border_width_all(4 if selected else 0)
			style.border_color = Color.WHITE
			button.add_theme_stylebox_override(state, style)

func _start_game() -> void:
	var config: Array[Dictionary] = []
	for i in _rows.size():
		var typed: String = _rows[i]["name_edit"].text.strip_edges()
		config.append({
			"name": typed if typed != "" else "Player %d" % (i + 1),
			"color_name": _rows[i]["color_name"],
		})
	GameConfig.players = config
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
