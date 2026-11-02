class_name HUD
extends CanvasLayer

## Match UI over the 3D board, in the courtyard look (HudStyle, GameFonts):
##   - player badges along the top: figure portrait, name, pawns home, a padlock while the
##     inner ring is closed, cards held, a note ("skips a turn"...), "away" when dropped;
##     the current player's badge lights up in their colour
##   - the throw panel by your hand (bottom right): whose turn, what to do, the throw pool
##     (click a throw to use it; the chosen one is ringed, exhausted ones struck through)
##     and a preview of the hovered move. There is no Throw button: you throw with your
##     shells (ShellStage). `throw_allowed` says when this screen may throw.
##   - the newest event as a toast, and the full log on a palm-leaf scroll (Log / Tab)
##   - the winner / notice overlay
##   - the Menu (MatchMenu: volume, Leave match), from its button, Esc, F10 or pad Start;
##     no throwing while it's open
## Board highlights come from its BoardPresenter; keyboard / pad picking from its
## PadCursor. Laid out inside the screen's safe area (Display) and again whenever the
## window changes size. Every action works without a pointer: throw_prev / throw_next
## switch throws, log_toggle opens the log (GameInput). Listens to GameManager signals
## and turns them into plain-language messages; never changes game state.

const START_SCREEN_PATH := "res://ui/StartScreen.tscn"
const THROW_HINT := "Hold on the board, shake, then flick to throw. A click on your shells is a quick toss (Space / gamepad A works too)."
const THROW_HINT_TOUCH := "Hold on the board, shake, then flick to throw. A tap on your shells is a quick toss."
const THROW_HINT_PAD := "Hold Space / A and shake with the arrows / stick, then let go to throw."
const MAX_LOG_LINES := 60
const MARGIN := 16.0
const THROW_PANEL_WIDTH := 300.0
const LOG_WIDTH := 340.0
const TOAST_TIME := 3.2
## Above the card UI (layer 5) and everything else.
const OVERLAY_LAYER := 20

## A throw chip was clicked (index into the pool); MatchController turns it into an intent.
signal throw_chip_pressed(index: int)
## throw_allowed changed.
signal throw_allowed_changed(allowed: bool)

## The match this HUD shows (binds once its players exist).
@export var game: GameManager

## May this screen throw now (its turn, waiting for a throw, nothing covering the match)?
var throw_allowed: bool = false:
	set(value):
		if value != throw_allowed:
			throw_allowed = value
			throw_allowed_changed.emit(value)
## Online: the seat this screen plays (set by MatchController). -1 = offline, every seat local.
var local_seat: int = -1
var presenter: BoardPresenter
var cursor: PadCursor

var _gm: GameManager
## A notice or the winner screen covers the match: no more throwing.
var _closed: bool = false
var _root: Control
var _badges: Array[Dictionary] = []
var _badge_row: HBoxContainer
var _turn_label: Label
var _hint_label: Label
var _pool_row: HBoxContainer
var _preview_label: RichTextLabel
var _throw_panel: PanelContainer
var _toast: PanelContainer
var _toast_label: RichTextLabel
var _toast_tween: Tween
var _log_panel: PanelContainer
var _log: RichTextLabel
var _log_open := false
var _menu: MatchMenu
var _menu_button: Button
var _winner_overlay: Control
var _winner_label: Label
## Online: players whose connection dropped (player id -> true).
var _disconnected: Dictionary = {}
## player id -> cards held (set by the card UI; -1 = not shown)
var _cards_held: Dictionary = {}
var _notes: Dictionary = {}
## The throw pool as last shown (index of the throw in use, -1 = none).
var _pool_selected: int = -1
var _pool_size: int = 0

func _init() -> void:
	# Built here (not in _ready) so other nodes can use the HUD in their _ready.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_throw_panel()
	_build_toast_and_log()
	_build_winner_overlay()
	_menu = MatchMenu.new()
	_menu.name = "MatchMenu"
	add_child(_menu)
	_menu.closed.connect(_update_throw_allowed)
	_menu.leave_requested.connect(_back_to_menu)

func _ready() -> void:
	GameFonts.install()
	Display.apply(get_tree())
	GameInput.ensure(get_tree())
	_layout()
	get_viewport().size_changed.connect(_layout)
	if game:
		game.setup_done.connect(bind.bind(game))

## The area the HUD lays out in: the safe part of the screen (clear of notches).
func _screen() -> Vector2:
	var viewport := get_viewport()
	return Display.safe_rect(viewport).size if viewport else Vector2(1280, 720)

## The throw hint for the device in use.
static func throw_hint() -> String:
	return GameInput.pick(THROW_HINT, THROW_HINT_TOUCH, THROW_HINT_PAD)

## Once the match's players exist.
func bind(gm: GameManager) -> void:
	_gm = gm
	_build_badges()
	presenter = BoardPresenter.new()
	presenter.name = "BoardPresenter"
	add_child(presenter)
	presenter.bind(gm, self)
	presenter.preview_changed.connect(_on_move_preview_changed)
	cursor = PadCursor.new()
	cursor.name = "PadCursor"
	add_child(cursor)
	cursor.bind(gm)
	gm.state_changed.connect(_on_state_changed)
	gm.turn_changed.connect(_on_turn_changed)
	gm.roll_result.connect(_on_roll_result)
	gm.movable_pawns_changed.connect(_on_moves_available)
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
	gm.game_over.connect(_on_game_over)
	gm.snapshot_loaded.connect(func(): _on_turn_changed(gm.current_player_index))
	Sound.ensure(get_tree())
	Sound.play(&"match_start", 0.0, 0.3) # the conch
	_log_line("Game started with %d players." % gm.players.size())
	var keep: float = GameConfig.THROW_SKILL_KEEP.get(gm.setup.throw_skill, 0.0)
	if keep > 0.0:
		_log_line("Skill throws (%s): shake, then let go gently, and each shell may land the way it lay in your hand (up to %d%%)." % [
			gm.setup.throw_skill, roundi(keep * 100)])

# --- LAYOUT ---
func _build_badges() -> void:
	_badge_row = HBoxContainer.new()
	_badge_row.position = Vector2(MARGIN, 12)
	_badge_row.add_theme_constant_override("separation", 10)
	_badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_badge_row)
	for i in _gm.players.size():
		var player: Dictionary = _gm.players[i]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge_row.add_child(panel)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		box.add_child(HudStyle.figure_portrait(player.get("figure", ""), player.get("color_name", "Red")))
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 1)
		box.add_child(text)
		var name_label := HudStyle.label(_gm.get_player_name(i), 18, HudStyle.TEXT, true)
		text.add_child(name_label)
		var marks := Control.new()
		marks.custom_minimum_size = Vector2(122, 20)
		marks.draw.connect(_draw_badge_marks.bind(marks, i))
		text.add_child(marks)
		var note := HudStyle.label("", 12, HudStyle.WARN)
		note.visible = false
		text.add_child(note)
		_badges.append({"panel": panel, "name": name_label, "marks": marks, "note": note})
	_refresh_players()

## Pips for pawns home, a padlock while the inner ring is closed, and card backs held.
func _draw_badge_marks(marks: Control, player: int) -> void:
	var color: Color = GameConfig.lacquer_of(_gm.players[player].get("color_name", "Red"))["base"]
	var home := _gm.count_pawns_home(player)
	for i in GameConfig.PAWNS_PER_PLAYER:
		var c := Vector2(7 + i * 15, 10)
		if i < home:
			marks.draw_circle(c, 5.5, color.lightened(0.2))
		else:
			marks.draw_arc(c, 5.0, 0, TAU, 16, HudStyle.MUTED, 1.5, true)
	var x := 66.0
	if not _gm.player_has_killed[player]:
		marks.draw_arc(Vector2(x + 6, 8), 4.0, PI, TAU, 10, HudStyle.MUTED, 2.0, true)
		marks.draw_rect(Rect2(x, 8, 12, 9), HudStyle.MUTED)
		x += 20.0
	for i in mini(int(_cards_held.get(player, 0)), 5):
		marks.draw_circle(Vector2(x + 6 + i * 6, 10), 6.0, GanjifaCard.BACK_COLOR)
		marks.draw_arc(Vector2(x + 6 + i * 6, 10), 6.0, 0, TAU, 16, Ganjifa.GOLD, 1.2, true)

func _build_throw_panel() -> void:
	_throw_panel = PanelContainer.new()
	_throw_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	_throw_panel.custom_minimum_size.x = THROW_PANEL_WIDTH
	_root.add_child(_throw_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_throw_panel.add_child(box)
	_turn_label = HudStyle.label("", 22, HudStyle.TEXT, true)
	box.add_child(_turn_label)
	_hint_label = HudStyle.label("", 14, HudStyle.MUTED)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size.x = THROW_PANEL_WIDTH - 20.0
	box.add_child(_hint_label)
	_preview_label = RichTextLabel.new()
	_preview_label.bbcode_enabled = true
	_preview_label.fit_content = true
	_preview_label.scroll_active = false
	# Rich text measures its height from its width: give it the panel's
	_preview_label.custom_minimum_size.x = THROW_PANEL_WIDTH - 20.0
	_preview_label.add_theme_font_size_override("normal_font_size", 14)
	_preview_label.add_theme_font_size_override("bold_font_size", 14)
	_preview_label.visible = false
	box.add_child(_preview_label)
	var pool_box := HBoxContainer.new()
	pool_box.add_theme_constant_override("separation", 6)
	pool_box.custom_minimum_size = Vector2(0, 36)
	var pool_title := HudStyle.label("Throws:", 15, HudStyle.MUTED)
	pool_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pool_box.add_child(pool_title)
	_pool_row = HBoxContainer.new()
	_pool_row.add_theme_constant_override("separation", 6)
	pool_box.add_child(_pool_row)
	box.add_child(pool_box)
	_throw_panel.resized.connect(_layout)

func _build_toast_and_log() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", HudStyle.panel())
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast_label = RichTextLabel.new()
	_toast_label.bbcode_enabled = true
	_toast_label.fit_content = true
	_toast_label.scroll_active = false
	_toast_label.custom_minimum_size.x = 300
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override("normal_font_size", 16)
	_toast_label.add_theme_font_size_override("bold_font_size", 16)
	_toast.add_child(_toast_label)
	_root.add_child(_toast)
	var log_button := HudStyle.button("Log", Vector2(64, 40))
	log_button.name = "LogButton"
	log_button.pressed.connect(toggle_log)
	_root.add_child(log_button)
	_menu_button = HudStyle.button("Menu", Vector2(76, 40))
	_menu_button.name = "MenuButton"
	_menu_button.pressed.connect(open_menu)
	_root.add_child(_menu_button)
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", HudStyle.leaf())
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_color_override("default_color", HudStyle.LEAF_TEXT)
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	_log_panel.add_child(_log)
	_root.add_child(_log_panel)
	_log_panel.set_meta("button", log_button)

## Places the panels for the screen size (the throw panel grows upwards).
func _layout() -> void:
	var screen := _screen()
	var viewport := get_viewport()
	if viewport:
		_root.position = Display.safe_rect(viewport).position
	_root.size = screen
	_throw_panel.reset_size()
	_throw_panel.position = screen - _throw_panel.size - Vector2(MARGIN, MARGIN)
	var log_button: Button = _log_panel.get_meta("button")
	log_button.position = Vector2(screen.x - MARGIN - 64, 14)
	_menu_button.position = Vector2(log_button.position.x - 10 - 76, 14)
	_log_panel.size = Vector2(LOG_WIDTH, screen.y - 66 - _throw_panel.size.y - MARGIN * 2.0)
	_log_panel.position = Vector2(screen.x - MARGIN - LOG_WIDTH if _log_open else screen.x + 10, 64)

func toggle_log() -> void:
	_log_open = not _log_open
	var screen := _screen()
	var x := screen.x - MARGIN - LOG_WIDTH if _log_open else screen.x + 10
	create_tween().tween_property(_log_panel, "position:x", x, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The in-match menu (volume, leave).
func open_menu() -> void:
	if not _menu.visible:
		_menu.open()
		_update_throw_allowed()

## Back to the main menu (it closes any online session on arrival).
func _back_to_menu() -> void:
	get_tree().change_scene_to_file(START_SCREEN_PATH)

func _unhandled_input(event: InputEvent) -> void:
	# Esc / B that nothing else wanted (no card to cancel, no shells in hand), or F10 / Start
	if event.is_action_pressed("menu_toggle") or (event.is_action_pressed("pick_cancel") and not _winner_overlay.visible):
		open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("log_toggle"):
		toggle_log()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("throw_next", true) or event.is_action_pressed("throw_prev", true):
		if _step_throw(1 if event.is_action_pressed("throw_next", true) else -1):
			get_viewport().set_input_as_handled()

## Keyboard / pad: switch to the next throw some pawn can use (like clicking its chip).
func _step_throw(step: int) -> bool:
	if _gm == null or _gm.current_state != GameManager.GameState.SELECTING_PIECE or not is_local_turn() or _pool_size < 2:
		return false
	for k in range(1, _pool_size):
		var i := wrapi(_pool_selected + step * k, 0, _pool_size)
		if _gm.can_use_throw(_gm.throw_pool[i]):
			throw_chip_pressed.emit(i)
			return true
	return false

func _build_winner_overlay() -> void:
	_winner_overlay = ColorRect.new()
	(_winner_overlay as ColorRect).color = Color(0.05, 0.03, 0.02, 0.7)
	_winner_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_winner_overlay.visible = false
	# Its own top layer, so it covers every panel (including the card hand)
	var top := CanvasLayer.new()
	top.layer = OVERLAY_LAYER
	add_child(top)
	top.add_child(_winner_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_winner_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_winner_label = HudStyle.label("", 44, HudStyle.TEXT, true)
	_winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.custom_minimum_size = Vector2(760, 0) # wrapping labels need a width
	box.add_child(_winner_label)
	var back := HudStyle.button("Back to menu", Vector2(220, 48))
	back.name = "BackToMenu"
	back.focus_mode = Control.FOCUS_ALL # pad players press it with A
	back.add_theme_font_size_override("font_size", 20)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The menu closes any online session on arrival
	back.pressed.connect(_back_to_menu)
	box.add_child(back)

# --- PUBLIC (for add-on systems such as the card UI) ---
## Adds a line (BBCode) to the log; `toast` also shows it as the newest event.
func log_message(bbcode: String, toast: bool = false) -> void:
	_log_line(bbcode, toast)

## Player name in their colour, bold (BBCode).
func who(player_id: int) -> String:
	return _who(player_id)

## Replaces the hint in the throw panel.
func set_hint(text: String) -> void:
	_hint_label.text = text
	_layout()

## A note on a player's badge ("" hides it).
func set_player_note(player_id: int, text: String) -> void:
	_notes[player_id] = text
	if player_id >= 0 and player_id < _badges.size():
		_badges[player_id]["note"].text = text
		_badges[player_id]["note"].visible = text != ""

## How many cards a player holds, shown as card backs on their badge (the card UI says).
func set_player_cards(player_id: int, count: int) -> void:
	_cards_held[player_id] = count
	if player_id >= 0 and player_id < _badges.size():
		(_badges[player_id]["marks"] as Control).queue_redraw()

## Screen centre of a player's badge (cards played by others fly in from there).
func badge_centre(player_id: int) -> Vector2:
	if player_id < 0 or player_id >= _badges.size():
		return _screen() / 2.0
	var panel: PanelContainer = _badges[player_id]["panel"]
	return panel.global_position + panel.size / 2.0

func describe_tile(tile: int) -> String:
	return _describe_tile(tile)

## Online: show whether a player is connected (badge + log).
func set_player_connected(player_id: int, connected: bool) -> void:
	if connected == not _disconnected.has(player_id):
		return
	if connected:
		_disconnected.erase(player_id)
		_log_line("%s reconnected." % _who(player_id), true)
	else:
		_disconnected[player_id] = true
		_log_line("[color=#f0a54a]%s lost connection.[/color]" % _who(player_id), true)
	_refresh_players()

## A full-screen message with a "Back to menu" button (e.g. the host left).
func show_notice(text: String) -> void:
	_winner_label.text = text
	_winner_label.add_theme_color_override("font_color", HudStyle.TEXT)
	_open_overlay()

func _open_overlay() -> void:
	_open_overlay()
	GameInput.offer_focus(get_tree(), _winner_overlay.find_child("BackToMenu", true, false))

func set_local_seat(seat: int) -> void:
	local_seat = seat

## Is it this screen's turn to act (always true offline)?
func is_local_turn() -> bool:
	return local_seat < 0 or local_seat == _gm.current_player_index

func _online() -> bool:
	return local_seat >= 0

## Text for players watching someone else's turn.
func _waiting(what: String) -> String:
	return "%s %s" % [_gm.get_player_name(_gm.current_player_index), what]

# --- TEXT HELPERS ---
func _who(player_id: int) -> String:
	# Names come from other players: escape "[" so a name can't inject BBCode into the log
	var safe_name := _gm.get_player_name(player_id).replace("[", "[lb]")
	return "[b][color=#%s]%s[/color][/b]" % [_text_color(player_id).to_html(false), safe_name]

## A player's colour, deepened enough to read on the palm leaf and the dark panels.
func _text_color(player_id: int) -> Color:
	return _gm.get_player_color(player_id).darkened(0.15)

func _describe_tile(tile: int) -> String:
	var data := _gm.board.board_data
	if tile == data.home_index:
		return "home (centre)"
	var home_owner := _gm.get_homebase_owner(tile)
	if home_owner >= 0:
		return "%s's homebase (safe)" % _gm.get_player_name(home_owner)
	var n := data.get_grid_size()
	@warning_ignore("integer_division")
	var where := "square %d,%d" % [tile % n + 1, tile / n + 1]
	return where + (" (safe house)" if _gm.board.is_safe(tile) else "")

func _join_values(values: Array[int]) -> String:
	var parts: Array[String] = []
	for v in values:
		parts.append(str(v))
	return ", ".join(parts)

func _log_line(bbcode: String, toast: bool = false) -> void:
	_log.append_text(bbcode + "\n")
	if _log.get_paragraph_count() > MAX_LOG_LINES:
		_log.remove_paragraph(0)
	if toast:
		_show_toast(bbcode)

func _show_toast(bbcode: String) -> void:
	_toast_label.text = bbcode
	_toast.reset_size()
	var screen := _screen()
	_toast.position = Vector2(_menu_button.position.x - 12 - _toast.size.x, 4)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.parallel().tween_property(_toast, "position:y", 14.0, 0.25).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)

func _refresh_players() -> void:
	for i in _badges.size():
		var badge: Dictionary = _badges[i]
		var is_turn := i == _gm.current_player_index
		var tags := ""
		if _online() and i == local_seat:
			tags += " (you)"
		if _disconnected.has(i):
			tags += " (away)"
		badge["name"].text = _gm.get_player_name(i) + tags
		var color: Color = GameConfig.lacquer_of(_gm.players[i].get("color_name", "Red"))["base"]
		(badge["panel"] as PanelContainer).add_theme_stylebox_override("panel",
			HudStyle.panel(color if is_turn else Color(HudStyle.BORDER, 0.45), 3 if is_turn else 1))
		(badge["panel"] as PanelContainer).modulate = Color(1, 1, 1, 0.55 if _disconnected.has(i) else 1.0)
		(badge["marks"] as Control).queue_redraw()

# --- SIGNAL HANDLERS ---
func _on_state_changed(_state: GameManager.GameState) -> void:
	_update_throw_allowed()

## May this screen throw: its turn, waiting for a throw, nothing covering the match.
func _update_throw_allowed() -> void:
	throw_allowed = _gm != null and not _closed and not _menu.visible \
		and _gm.current_state == GameManager.GameState.WAITING_FOR_ROLL and is_local_turn() and not _gm.is_game_finished()

func _on_turn_changed(player_id: int) -> void:
	var mine := _online() and is_local_turn()
	_turn_label.text = "Your turn" if mine else "%s's turn" % _gm.get_player_name(player_id)
	_turn_label.add_theme_color_override("font_color", _gm.get_player_color(player_id).lightened(0.15))
	set_hint(throw_hint() if is_local_turn() else _waiting("is about to throw..."))
	if is_local_turn() and not _gm.is_game_finished():
		Sound.play(&"turn_yours", -2.0, 0.25)
	_on_move_preview_changed({})
	_refresh_players()

func _on_roll_result(value: int) -> void:
	var open_up := 0 if value == 8 else value
	var term: String = {0: " (ashta, all face down)", 4: " (chamma, all face up)"}.get(open_up, "")
	_log_line("%s threw [b]%d[/b]: %d of 4 shells open side up%s." % [_who(_gm.current_player_index), value, open_up, term])
	if value in GameManager.BONUS_THROWS and _gm.throw_pool.size() < GameManager.MAX_BONUS_CHAIN:
		var term_name := "Chamma" if value == 4 else "Ashta"
		if is_local_turn():
			set_hint("%s! Throw again before moving. (Three 4/8s in a row loses the throws.)" % term_name)
		else:
			set_hint(_waiting("threw a %s and throws again..." % term_name.to_lower()))

func _on_moves_available(pawns: Array[Pawn]) -> void:
	if pawns.is_empty():
		return
	if not is_local_turn():
		set_hint(_waiting("is choosing a move (throw of %d)..." % _gm.current_roll))
		return
	set_hint("Using a throw of %d: pick a ringed pawn (%d can move). %s" % [_gm.current_roll, pawns.size(), GameInput.pick(
		"Click another throw to switch; point at a pawn to see its move.",
		"Tap another throw to switch; tap a pawn to see its move, tap again to move it.",
		"Left / Right to choose a pawn, A / Enter to move it, Up / Down to switch throws.")])

func _on_throw_pool_changed(pool: Array[int], exhausted: Array[int], selected: int) -> void:
	for child in _pool_row.get_children():
		child.queue_free()
	var choosing := _gm.current_state == GameManager.GameState.SELECTING_PIECE
	_pool_selected = selected if choosing else -1
	_pool_size = pool.size()
	for i in pool.size():
		var chosen := i == selected and choosing
		var chip := HudStyle.button(str(pool[i]), Vector2(34, 34))
		chip.add_theme_font_size_override("font_size", 18)
		chip.add_theme_stylebox_override("normal", HudStyle.panel(Ganjifa.GOLD if chosen else Color(HudStyle.BORDER, 0.4), 3 if chosen else 1))
		var usable := choosing and is_local_turn() and _gm.can_use_throw(pool[i])
		chip.disabled = not usable
		chip.tooltip_text = "Use this throw" if usable else "No pawn can use this throw right now"
		chip.pressed.connect(throw_chip_pressed.emit.bind(i))
		_pool_row.add_child(chip)
	for value in exhausted:
		_pool_row.add_child(_exhausted_chip(value))
	_layout()

## A greyed throw value with a line through it.
func _exhausted_chip(value: int) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(30, 34)
	chip.tooltip_text = "Exhausted: no pawn could use this throw"
	var label := HudStyle.label(str(value), 18, Color(HudStyle.MUTED, 0.6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(label)
	var strike := ColorRect.new()
	strike.color = HudStyle.WARN
	strike.position = Vector2(3, 16)
	strike.size = Vector2(24, 2.5)
	strike.rotation = -0.35
	strike.pivot_offset = strike.size / 2.0
	chip.add_child(strike)
	return chip

func _on_throws_exhausted(player_id: int, values: Array[int]) -> void:
	Sound.play(&"throws_lost", -8.0)
	set_hint("Exhausted %s: no pawn can use those throws." % _join_values(values))
	_log_line("[color=#c8602a]%s's %s %s exhausted: no pawn can move by %s (home needs an exact throw; own pawns can't share a normal square).[/color]" % [
		_who(player_id), "throw" if values.size() == 1 else "throws", _join_values(values),
		"that amount" if values.size() == 1 else "any of those amounts"], true)

func _on_turn_forfeited(player_id: int, values: Array[int]) -> void:
	Sound.play(&"throws_lost", -3.0)
	set_hint("Three 4/8s in a row: the throws are lost.")
	_log_line("[color=#c0392b]%s threw 4/8 three times in a row: %s lost.[/color]" % [_who(player_id), _join_values(values)], true)

func _on_pawn_moved(pawn: Pawn, from_tile: int, to_tile: int, steps: int) -> void:
	_log_line("%s moved %d from %s to %s." % [_who(pawn.team_id), steps, _describe_tile(from_tile), _describe_tile(to_tile)])
	_refresh_players()

func _on_pawn_captured(attacker: Pawn, victim: Pawn) -> void:
	_log_line("[color=#c0392b]%s captured %s's pawn! It goes back to its homebase. Extra throw once this turn's throws are used.[/color]" % [_who(attacker.team_id), _who(victim.team_id)], true)
	_refresh_players()

func _on_pawn_sent_home(pawn: Pawn, from_tile: int) -> void:
	_log_line("%s's pawn was sent from %s back to its homebase." % [_who(pawn.team_id), _describe_tile(from_tile)], true)
	_refresh_players()

func _on_pawns_swapped(a: Pawn, b: Pawn) -> void:
	_log_line("%s's pawn and %s's pawn swapped places." % [_who(a.team_id), _who(b.team_id)], true)

func _on_turn_skipped(player_id: int) -> void:
	_log_line("[color=#c8602a]%s's turn is skipped.[/color]" % _who(player_id), true)

func _on_inner_ring_unlocked(player_id: int) -> void:
	Sound.play(&"gate_open")
	_log_line("%s unlocked the inner ring: the entry arrow is open." % _who(player_id), true)
	_refresh_players()

func _on_pawn_reached_home(pawn: Pawn, pawns_home: int) -> void:
	Sound.play(&"pawn_home")
	_log_line("%s brought a pawn home (%d/%d)." % [_who(pawn.team_id), pawns_home, GameConfig.PAWNS_PER_PLAYER], true)
	_refresh_players()

func _on_bonus_turn(player_id: int, reason: String) -> void:
	Sound.play(&"extra_throw", -2.0, 0.6)
	set_hint("Extra throw (%s)." % reason if is_local_turn() else _waiting("gets an extra throw (%s)..." % reason))
	_log_line("%s gets an extra throw (%s)." % [_who(player_id), reason])

func _on_move_preview_changed(info: Dictionary) -> void:
	if info.is_empty():
		_preview_label.text = ""
		_preview_label.visible = false
		_layout()
		return
	var tiles: Array[int] = info["tiles"]
	var text := "Moves %d to %s" % [tiles.size(), _describe_tile(tiles.back())]
	match info["end"]:
		GameManager.MoveEnd.CAPTURE:
			text += "\n[color=#ff7b6b][b]Captures %s's pawn![/b][/color]" % _gm.get_player_name(info["victim"].team_id)
		GameManager.MoveEnd.SAFE:
			text += "\n[color=#6fd8de]Lands on a safe house.[/color]"
		GameManager.MoveEnd.HOME:
			text += "\n[color=#c3a2ff]Reaches home![/color]"
	_preview_label.text = text
	_preview_label.visible = true
	_layout()

func _on_game_over(winner_id: int) -> void:
	Sound.play(&"match_win")
	_log_line("[b]%s wins![/b]" % _who(winner_id))
	_winner_label.text = "%s wins!" % _gm.get_player_name(winner_id)
	_winner_label.add_theme_color_override("font_color", _gm.get_player_color(winner_id).lightened(0.2))
	_winner_overlay.visible = true
	_closed = true
	throw_allowed = false
