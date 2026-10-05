class_name HUD
extends CanvasLayer

## Match UI: players panel (left), turn/throw/log panel (right), winner overlay.
## Listens to GameManager signals and turns them into plain-language messages.

const START_SCREEN_PATH := "res://ui/StartScreen.tscn"
const PANEL_WIDTH := 360.0
const MAX_LOG_LINES := 60

var roll_button: Button

var _gm: GameManager
var _turn_label: Label
var _hint_label: Label
var _shells_view: ShellsView
var _roll_value_label: Label
var _pool_row: HBoxContainer
var _tile_label: RichTextLabel
var _preview_label: RichTextLabel
var _log: RichTextLabel
var _player_rows: Array[Dictionary] = []
var _winner_overlay: Control
var _winner_label: Label
## Pulsing screen-edge glow in the active player's colour.
var _turn_glow: ColorRect
var _glow_tween: Tween

const TURN_GLOW_SHADER := preload("res://ui/TurnGlow.gdshader")
const GLOW_FADE_TIME := 0.6

func _init() -> void:
	# Built here (not in _ready) so GameManager can grab roll_button in its own _ready.
	_build_turn_glow() # first, so it draws behind the panels
	_build_right_panel()
	_build_winner_overlay()

## Called by GameManager once players exist.
func bind(gm: GameManager) -> void:
	_gm = gm
	_build_players_panel()
	gm.turn_changed.connect(_on_turn_changed)
	gm.shells_thrown.connect(func(shells: Array[bool]): _shells_view.shells = shells)
	gm.roll_result.connect(_on_roll_result)
	gm.valid_moves_highlighted.connect(_on_moves_available)
	gm.throw_pool_changed.connect(_on_throw_pool_changed)
	gm.throws_exhausted.connect(_on_throws_exhausted)
	gm.turn_forfeited.connect(_on_turn_forfeited)
	gm.pawn_moved.connect(_on_pawn_moved)
	gm.pawn_captured.connect(_on_pawn_captured)
	gm.pawn_sent_home.connect(_on_pawn_sent_home)
	gm.pawns_swapped.connect(_on_pawns_swapped)
	gm.turn_skipped.connect(_on_turn_skipped)
	gm.inner_ring_unlocked.connect(_on_inner_ring_unlocked)
	gm.pawn_reached_home.connect(_on_pawn_reached_home)
	gm.bonus_turn.connect(_on_bonus_turn)
	gm.move_preview_changed.connect(_on_move_preview_changed)
	gm.game_over.connect(_on_game_over)
	gm.board.tile_hovered.connect(_on_tile_hovered)
	_log_line("Game started with %d players." % gm.players.size())

# --- LAYOUT ---
func _make_panel(pos: Vector2, panel_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.16, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box

func _label(text: String, font_size: int = 16, color: Color = Color(0.92, 0.92, 0.95)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _rich(fit: bool) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = fit
	rich.scroll_active = not fit
	rich.add_theme_font_size_override("normal_font_size", 14)
	rich.add_theme_font_size_override("bold_font_size", 14)
	return rich

func _build_right_panel() -> void:
	var box := _make_panel(Vector2(900, 20), Vector2(PANEL_WIDTH, 680))

	_turn_label = _label("", 24)
	box.add_child(_turn_label)
	_hint_label = _label("", 14, Color(0.7, 0.7, 0.75))
	# Fixed height (3 lines) so hint changes never shift the Throw button under the cursor
	_hint_label.custom_minimum_size = Vector2(0, 62)
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_hint_label)

	var throw_row := HBoxContainer.new()
	throw_row.add_theme_constant_override("separation", 16)
	_shells_view = ShellsView.new()
	throw_row.add_child(_shells_view)
	_roll_value_label = _label("–", 36)
	throw_row.add_child(_roll_value_label)
	box.add_child(throw_row)

	var pool_box := HBoxContainer.new()
	pool_box.add_theme_constant_override("separation", 8)
	pool_box.custom_minimum_size = Vector2(0, 36)
	var pool_title := _label("Throws:", 15, Color(0.7, 0.7, 0.75))
	pool_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	pool_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pool_box.add_child(pool_title)
	_pool_row = HBoxContainer.new()
	_pool_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_row.add_theme_constant_override("separation", 6)
	pool_box.add_child(_pool_row)
	box.add_child(pool_box)

	roll_button = Button.new()
	roll_button.name = "RollButton"
	roll_button.text = "Throw shells"
	roll_button.custom_minimum_size = Vector2(0, 44)
	roll_button.add_theme_font_size_override("font_size", 18)
	box.add_child(roll_button)

	box.add_child(HSeparator.new())
	_tile_label = _rich(true)
	box.add_child(_tile_label)
	_preview_label = _rich(true)
	box.add_child(_preview_label)

	box.add_child(HSeparator.new())
	box.add_child(_label("What's happening", 15, Color(0.7, 0.7, 0.75)))
	_log = _rich(false)
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)

func _build_players_panel() -> void:
	var box := _make_panel(Vector2(20, 20), Vector2(PANEL_WIDTH, 0))
	box.add_child(_label("Players", 20))
	for i in _gm.players.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = _gm.get_player_color(i)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		# Autowrap labels have no minimum width, so the column must claim the row's space
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := _label(_gm.get_player_name(i), 17)
		var status_label := _label("", 13, Color(0.7, 0.7, 0.75))
		var note_label := _label("", 13, Color(0.85, 0.78, 0.55))
		note_label.visible = false
		text.add_child(name_label)
		text.add_child(status_label)
		text.add_child(note_label)
		row.add_child(text)
		box.add_child(row)
		_player_rows.append({"name": name_label, "status": status_label, "note": note_label})
	_refresh_players()

func _build_turn_glow() -> void:
	_turn_glow = ColorRect.new()
	_turn_glow.name = "TurnGlow"
	_turn_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = TURN_GLOW_SHADER
	material.set_shader_parameter("glow_color", Color(1, 1, 1, 0))
	_turn_glow.material = material
	add_child(_turn_glow)

## Cross-fades the edge glow to `color`.
func _set_glow_color(color: Color) -> void:
	var material := _turn_glow.material as ShaderMaterial
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(func(c: Color): material.set_shader_parameter("glow_color", c),
		material.get_shader_parameter("glow_color"), color, GLOW_FADE_TIME)

func _build_winner_overlay() -> void:
	_winner_overlay = ColorRect.new()
	(_winner_overlay as ColorRect).color = Color(0, 0, 0, 0.6)
	_winner_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_winner_overlay.visible = false
	add_child(_winner_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_winner_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_winner_label = _label("", 40)
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_winner_label)
	var again := Button.new()
	again.text = "New game"
	again.custom_minimum_size = Vector2(220, 48)
	again.add_theme_font_size_override("font_size", 20)
	again.pressed.connect(func(): get_tree().change_scene_to_file(START_SCREEN_PATH))
	box.add_child(again)

# --- PUBLIC (for add-on systems such as the card UI) ---
## Adds a line (BBCode) to the "What's happening" log.
func log_message(bbcode: String) -> void:
	_log_line(bbcode)

## Player name in their colour, bold (BBCode).
func who(player_id: int) -> String:
	return _who(player_id)

## Replaces the hint under the turn label.
func set_hint(text: String) -> void:
	_hint_label.text = text

## Extra line under a player's status in the players panel ("" hides it).
func set_player_note(player_id: int, text: String) -> void:
	if player_id < 0 or player_id >= _player_rows.size():
		return
	_player_rows[player_id]["note"].text = text
	_player_rows[player_id]["note"].visible = text != ""

func describe_tile(tile: int) -> String:
	return _describe_tile(tile)

# --- TEXT HELPERS ---
func _who(player_id: int) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [_gm.get_player_color(player_id).to_html(false), _gm.get_player_name(player_id)]

func _describe_tile(tile: int) -> String:
	var data := _gm.board.board_data
	if tile == data.home_index:
		return "home (centre)"
	var home_owner := _gm.get_homebase_owner(tile)
	if home_owner >= 0:
		return "%s's homebase (safe)" % _gm.get_player_name(home_owner)
	var n := data.get_grid_size()
	var where := "tile %d,%d" % [tile % n + 1, tile / n + 1]
	return where + (" — safe house" if _gm.board.is_safe(tile) else "")

func _join_values(values: Array[int]) -> String:
	var parts: Array[String] = []
	for v in values:
		parts.append(str(v))
	return ", ".join(parts)

func _log_line(bbcode: String) -> void:
	_log.append_text(bbcode + "\n")
	if _log.get_paragraph_count() > MAX_LOG_LINES:
		_log.remove_paragraph(0)

func _refresh_players() -> void:
	for i in _player_rows.size():
		var unlocked := "inner ring open" if _gm.player_has_killed[i] else "needs a capture for inner ring"
		_player_rows[i]["status"].text = "Home %d/%d · %s" % [_gm.count_pawns_home(i), GameConfig.PAWNS_PER_PLAYER, unlocked]
		var is_turn := i == _gm.current_player_index
		_player_rows[i]["name"].text = ("▸ " if is_turn else "") + _gm.get_player_name(i)

# --- SIGNAL HANDLERS ---
func _on_turn_changed(player_id: int) -> void:
	_turn_label.text = "%s's turn" % _gm.get_player_name(player_id)
	_turn_label.add_theme_color_override("font_color", _gm.get_player_color(player_id))
	_hint_label.text = "Throw the shells."
	roll_button.text = "Throw shells"
	# The previous player's throw would read as this player's, so start blank
	_shells_view.shells = []
	_roll_value_label.text = "–"
	_preview_label.text = ""
	_set_glow_color(_gm.get_player_color(player_id))
	_refresh_players()

func _on_roll_result(value: int) -> void:
	_roll_value_label.text = str(value)
	var open_up := 0 if value == 8 else value
	var term: String = {0: " (ashta — all face down)", 4: " (chamma — all face up)"}.get(open_up, "")
	_log_line("%s threw [b]%d[/b]: %d of 4 shells open side up%s." % [_who(_gm.current_player_index), value, open_up, term])
	if value in GameManager.BONUS_THROWS and _gm.throw_pool.size() < GameManager.MAX_BONUS_CHAIN:
		roll_button.text = "Throw again"
		_hint_label.text = "%s! Throw again before moving. (Three 4/8s in a row forfeits the turn.)" % ("Chamma" if value == 4 else "Ashta")

func _on_moves_available(pawns: Array[Pawn]) -> void:
	_hint_label.text = "Using a throw of %d: pick a highlighted pawn (%d can move). Click another throw to switch; hover a pawn to preview." % [_gm.current_roll, pawns.size()]

func _on_throw_pool_changed(pool: Array[int], exhausted: Array[int], selected: int) -> void:
	for child in _pool_row.get_children():
		child.queue_free()
	var choosing := _gm.current_state == GameManager.GameState.SELECTING_PIECE
	if choosing:
		roll_button.text = "Throw shells"
	for i in pool.size():
		var chip := Button.new()
		chip.text = str(pool[i])
		chip.custom_minimum_size = Vector2(38, 34)
		chip.add_theme_font_size_override("font_size", 18)
		var usable := choosing and _gm._is_throw_usable(pool[i])
		chip.disabled = not usable
		chip.tooltip_text = "Use this throw" if usable else "No pawn can use this throw right now"
		if i == selected and choosing:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.25, 0.25, 0.3)
			style.set_corner_radius_all(6)
			style.set_border_width_all(3)
			style.border_color = _gm.get_player_color(_gm.current_player_index)
			chip.add_theme_stylebox_override("normal", style)
			chip.add_theme_stylebox_override("hover", style)
		chip.pressed.connect(_gm.select_throw.bind(i))
		_pool_row.add_child(chip)
	for value in exhausted:
		_pool_row.add_child(_exhausted_chip(value))

## A greyed throw value with a red line through it.
func _exhausted_chip(value: int) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(30, 34)
	chip.tooltip_text = "Exhausted: no pawn could use this throw"
	var label := _label(str(value), 18, Color(0.55, 0.55, 0.6))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(label)
	var strike := ColorRect.new()
	strike.color = Color(0.95, 0.35, 0.3)
	strike.position = Vector2(3, 16)
	strike.size = Vector2(24, 2.5)
	strike.rotation = -0.35
	strike.pivot_offset = strike.size / 2.0
	chip.add_child(strike)
	return chip

func _on_throws_exhausted(player_id: int, values: Array[int]) -> void:
	_hint_label.text = "Exhausted %s: no pawn can use those throws." % _join_values(values)
	_log_line("[color=#f0a54a]%s's %s %s exhausted: no pawn can move by %s (home needs an exact throw; own pawns can't share a normal square).[/color]" % [
		_who(player_id), "throw" if values.size() == 1 else "throws", _join_values(values),
		"that amount" if values.size() == 1 else "any of those amounts"])

func _on_turn_forfeited(player_id: int, values: Array[int]) -> void:
	_hint_label.text = "Three 4/8s in a row: turn forfeited."
	_log_line("[color=#ff6b6b]%s threw 4/8 three times in a row: turn forfeited, %s lost.[/color]" % [_who(player_id), _join_values(values)])

func _on_pawn_moved(pawn: Pawn, from_tile: int, to_tile: int, steps: int) -> void:
	_log_line("%s moved %d from %s to %s." % [_who(pawn.team_id), steps, _describe_tile(from_tile), _describe_tile(to_tile)])
	if _gm.board.is_safe(to_tile) and to_tile != _gm.board.board_data.home_index and _gm.get_homebase_owner(to_tile) < 0:
		_log_line("   Safe house: that pawn can't be captured there.")
	_refresh_players()

func _on_pawn_captured(attacker: Pawn, victim: Pawn) -> void:
	_log_line("[color=#ff6b6b]%s captured %s's pawn — it goes back to its homebase! Extra throw once this turn's throws are used.[/color]" % [_who(attacker.team_id), _who(victim.team_id)])
	_refresh_players()

func _on_pawn_sent_home(pawn: Pawn, from_tile: int) -> void:
	_log_line("%s's pawn was sent from %s back to its homebase." % [_who(pawn.team_id), _describe_tile(from_tile)])
	_refresh_players()

func _on_pawns_swapped(a: Pawn, b: Pawn) -> void:
	_log_line("%s's pawn and %s's pawn swapped places." % [_who(a.team_id), _who(b.team_id)])

func _on_turn_skipped(player_id: int) -> void:
	_log_line("[color=#f0a54a]%s's turn is skipped.[/color]" % _who(player_id))

func _on_inner_ring_unlocked(player_id: int) -> void:
	_log_line("%s unlocked the inner ring — the entry arrow is now open." % _who(player_id))
	_refresh_players()

func _on_pawn_reached_home(pawn: Pawn, pawns_home: int) -> void:
	_log_line("%s brought a pawn home (%d/%d)." % [_who(pawn.team_id), pawns_home, GameConfig.PAWNS_PER_PLAYER])
	_refresh_players()

func _on_bonus_turn(player_id: int, reason: String) -> void:
	roll_button.text = "Throw again"
	_hint_label.text = "Extra throw (%s)." % reason
	_log_line("%s gets an extra throw (%s)." % [_who(player_id), reason])

func _on_move_preview_changed(info: Dictionary) -> void:
	if info.is_empty():
		_preview_label.text = ""
		return
	var tiles: Array[int] = info["tiles"]
	var text := "Moves %d → %s" % [tiles.size(), _describe_tile(tiles.back())]
	match info["end"]:
		TileHighlighter.PreviewEnd.CAPTURE:
			text += "\n[color=#ff6b6b][b]Captures %s's pawn![/b][/color]" % _gm.get_player_name(info["victim"].team_id)
		TileHighlighter.PreviewEnd.SAFE:
			text += "\n[color=#4fd1d9]Lands on a safe house.[/color]"
		TileHighlighter.PreviewEnd.HOME:
			text += "\n[color=#b18cff]Reaches home![/color]"
	_preview_label.text = text

func _on_tile_hovered(tile: int) -> void:
	if tile < 0:
		_tile_label.text = ""
		return
	var text := "[b]Hovering %s[/b]" % _describe_tile(tile)
	var pawns := _gm.get_pawns_at_tile(tile)
	if pawns.is_empty():
		text += "\nEmpty."
	else:
		var counts := {}
		for p in pawns:
			counts[p.team_id] = counts.get(p.team_id, 0) + 1
		var parts: Array[String] = []
		for team in counts:
			parts.append("%s ×%d" % [_who(team), counts[team]])
		text += "\n" + ", ".join(parts)
	_tile_label.text = text

func _on_game_over(winner_id: int) -> void:
	_log_line("[b]%s wins![/b]" % _who(winner_id))
	_winner_label.text = "%s wins!" % _gm.get_player_name(winner_id)
	_winner_label.add_theme_color_override("font_color", _gm.get_player_color(winner_id))
	_winner_overlay.visible = true
	roll_button.disabled = true
