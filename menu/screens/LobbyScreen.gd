class_name LobbyScreen
extends MenuScreen

## The lobby, for the host and for guests: the room code on a slate (host), who's in
## (their figures gather round the board in the courtyard as they join), lacquer pots to
## choose your colour, the room's rules (host chooses, everyone sees) and Start.
## Reads and changes the room only through NetSession. args: {"host_port", "autostart"}
## (developer --autostart: start as soon as that many players are in). Actions: "leave".

const SKILL_LEVELS := ["off", "light", "strong"]
const SKILL_LABELS := ["Off", "Light", "Strong"]
const DRAFT_LABELS := ["Private pick", "Open draft"]

var _autostart := 0
var _players_box: VBoxContainer
var _pots: HBoxContainer
var _cards_toggle: CheckBox
var _skill_picker: OptionButton
var _draft_picker: OptionButton
var _draft_note: Label
var _start_button: Button
var _leave_button: Button
var _status: Label
var _room_code_label: Label
var _room_status: Label
var _copy_button: Button

func _ready() -> void:
	_autostart = int(args.get("autostart", 0))
	add_child(MenuStyle.title("Lobby", 38))
	if net.is_host():
		_build_room_code()
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	add_child(_players_box)

	add_child(MenuStyle.label("Your colour", 16, MenuStyle.INK_MUTED))
	_pots = HBoxContainer.new()
	_pots.add_theme_constant_override("separation", 12)
	add_child(_pots)

	add_child(MenuStyle.label("Room rules" + ("" if net.is_host() else " (the host chooses)"), 16, MenuStyle.INK_MUTED))
	_cards_toggle = CheckBox.new()
	_cards_toggle.name = "PlayWithCards"
	_cards_toggle.text = "Play with cards"
	_cards_toggle.disabled = not net.is_host()
	_cards_toggle.toggled.connect(func(on: bool): net.set_setting("cards", on))
	add_child(_cards_toggle)
	_skill_picker = MenuStyle.options(SKILL_LEVELS.map(func(level: String):
		var keep: float = GameConfig.THROW_SKILL_KEEP[level]
		var label: String = SKILL_LABELS[SKILL_LEVELS.find(level)]
		return label if keep == 0.0 else "%s (up to %d%%)" % [label, roundi(keep * 100)]), 0)
	_skill_picker.name = "SkillThrows"
	_skill_picker.disabled = not net.is_host()
	_skill_picker.item_selected.connect(func(i: int): net.set_setting("throw_skill", SKILL_LEVELS[i]))
	add_child(MenuStyle.row("Skill throws", _skill_picker))
	add_child(MenuStyle.note("Shake, then let go gently: shells may land as they lay in your hand. Off = pure luck."))
	_draft_picker = MenuStyle.options(DRAFT_LABELS, 0)
	_draft_picker.name = "CardDraft"
	_draft_picker.item_selected.connect(func(i: int): net.set_setting("draft", GameConfig.DRAFT_MODES[i]))
	add_child(MenuStyle.row("Card draft", _draft_picker))
	_draft_note = MenuStyle.note("")
	add_child(_draft_note)

	_status = MenuStyle.label("", 16, MenuStyle.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_status)
	_leave_button = MenuStyle.button("Leave", 140)
	_leave_button.pressed.connect(go_back)
	_start_button = MenuStyle.button("Start game")
	_start_button.name = "StartGame"
	_start_button.visible = net.is_host()
	_start_button.pressed.connect(net.start_match)
	add_footer([_leave_button, _start_button])

	# Method callables (not lambdas) so the connections end when this screen is freed
	net.roster_changed.connect(_on_roster_changed)
	net.settings_changed.connect(_on_settings_changed)
	net.room_status.connect(_on_room_status)
	net.room_code_ready.connect(_on_room_code_ready)
	net.room_code_failed.connect(show_no_room_code)
	_refresh()

func first_focus() -> Control:
	return _start_button if _start_button.visible else _leave_button

func go_back() -> void:
	action.emit(&"leave", {})

# --- the room code (host) ---
func _build_room_code() -> void:
	var slate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.12)
	style.border_color = Color(0.45, 0.3, 0.15)
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	slate.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	slate.add_child(box)
	box.add_child(MenuStyle.label("Room code", 15, Color(0.85, 0.83, 0.78), HORIZONTAL_ALIGNMENT_CENTER))
	_room_code_label = MenuStyle.label(net.room_code if net.room_code != "" else "...", 30, Color(0.97, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_room_code_label.add_theme_font_override("font", GameFonts.chalk())
	_room_code_label.name = "RoomCode"
	box.add_child(_room_code_label)
	_room_status = MenuStyle.label("Getting a room code...", 14, Color(0.8, 0.78, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_room_status)
	add_child(slate)
	_copy_button = MenuStyle.button("Copy invite", 220)
	_copy_button.name = "CopyInvite"
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_copy_button.visible = net.room_code != ""
	_copy_button.pressed.connect(_copy_invite)
	add_child(_copy_button)
	var addresses := MenuStyle.note("Same network: " + ", ".join(_lan_addresses()))
	addresses.name = "HostAddresses"
	add_child(addresses)

## Host: no room code this time (it failed, or --no-tunnel).
func show_no_room_code(reason: String) -> void:
	if _room_code_label == null:
		return
	_room_code_label.text = "No room code"
	_room_status.text = reason + " Friends on your network can still use the address below."

func _on_room_status(text: String) -> void:
	if _room_status:
		_room_status.text = text

func _on_room_code_ready(code: String, live: bool) -> void:
	if _room_code_label == null:
		return
	_room_code_label.text = code
	_room_status.text = "Share this code. Friends pick Join a game and type it in." if live \
		else "Slow to confirm: it may take a minute before friends can join."
	_copy_button.visible = true

## Copies the code, plus the game's web page if one is set (GameConfig.PLAY_URL).
func _copy_invite() -> void:
	var code := net.room_code
	var text := "Join my Ashta Chemma game! Room code: %s" % code
	if GameConfig.PLAY_URL != "":
		text = "Join my Ashta Chemma game: %s  (Join a game, room code: %s)" % [GameConfig.PLAY_URL, code]
	DisplayServer.clipboard_set(text)
	_room_status.text = "Copied! Paste it to your friends."

## This machine's addresses on the local network, for friends on the same Wi-Fi.
func _lan_addresses() -> Array[String]:
	var port := int(args.get("host_port", NetSession.DEFAULT_PORT))
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append("%s:%d" % [ip, port])
	if result.is_empty():
		result.append("127.0.0.1:%d (this machine only)" % port)
	return result

# --- who's in, colours, rules ---
func _on_roster_changed(_roster: Array) -> void:
	_refresh()

func _on_settings_changed(_settings: Dictionary) -> void:
	_refresh()

func _refresh() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	for entry in net.roster:
		_players_box.add_child(_player_row(entry))
	_refresh_pots()
	var cards_on := bool(net.settings.get("cards", true))
	_cards_toggle.set_pressed_no_signal(cards_on)
	var skill := String(net.settings.get("throw_skill", GameConfig.DEFAULT_THROW_SKILL))
	_skill_picker.select(maxi(0, SKILL_LEVELS.find(skill)))
	var draft := String(net.settings.get("draft", GameConfig.DEFAULT_DRAFT))
	_draft_picker.select(maxi(0, GameConfig.DRAFT_MODES.find(draft)))
	_draft_picker.disabled = not net.is_host() or not cards_on
	_draft_note.text = "Each player secretly keeps 5 of their own 10 cards." if draft == GameConfig.DRAFT_PRIVATE \
		else "Take turns picking from one face-up pool: everyone sees every pick. Remember who took what."
	var count := net.roster.size()
	if net.is_host():
		_start_button.disabled = count < GameConfig.MIN_PLAYERS
		_status.text = "Waiting for players (%d-%d)." % [GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS] \
			if count < GameConfig.MIN_PLAYERS else "%d players in. Start when everyone's here." % count
		if _autostart > 0 and count >= _autostart:
			_autostart = 0
			net.start_match()
	else:
		_status.text = "Waiting for the host to start..."
	_gather()

## The courtyard: each player's figure at their side of the board.
func _gather() -> void:
	var sides := GameConfig.seats_for(net.roster.size())
	var entries: Array = []
	for entry in net.roster:
		var seat := int(entry["seat"])
		entries.append({"seat": seat, "side": sides[seat] if seat < sides.size() else seat % 4,
			"name": entry["name"], "color_name": entry["color_name"],
			"figure": GameConfig.figure_or_default(String(entry.get("figure", "")))})
	stage.show_gathering(entries)

func _player_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var dot := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = GameConfig.lacquer_of(entry["color_name"])["base"]
	style.set_corner_radius_all(11)
	dot.add_theme_stylebox_override("panel", style)
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var tags: Array[String] = []
	if entry["seat"] == 0:
		tags.append("host")
	if entry["seat"] == net.local_seat:
		tags.append("you")
	if not entry["connected"]:
		tags.append("away")
	var figure: String = GameConfig.FIGURES.get(entry.get("figure", ""), "")
	var text: String = entry["name"] + ("  · " + figure if figure != "" else "") \
		+ ("  (%s)" % ", ".join(tags) if not tags.is_empty() else "")
	var name_label := MenuStyle.label(text, 18)
	# Wrapping labels have no minimum width; let the name take the row
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row

## Lacquer pots, one per colour: yours ringed, others' colours taken. Keeps pad focus
## on the same pot across refreshes.
func _refresh_pots() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_name: String = String(focused.name) if focused and focused.get_parent() == _pots else ""
	for child in _pots.get_children():
		_pots.remove_child(child)
		child.queue_free()
	var mine: String = net.local_entry().get("color_name", "")
	for color_name in GameConfig.COLORS:
		var taken: bool = net.roster.any(func(e): return e["color_name"] == color_name and e["seat"] != net.local_seat)
		var pot := _pot(color_name, color_name == mine, taken)
		_pots.add_child(pot)
		if String(pot.name) == focused_name:
			pot.grab_focus.call_deferred()

func _pot(color_name: String, mine: bool, taken: bool) -> Button:
	var pot := Button.new()
	pot.name = "Color" + color_name
	pot.tooltip_text = color_name + (" (taken)" if taken else "")
	pot.custom_minimum_size = Vector2(52, 52)
	pot.disabled = taken
	pot.focus_mode = Control.FOCUS_ALL
	pot.pressed.connect(func():
		Sound.play(&"ui_click")
		net.request_color(color_name))
	var lacquer: Color = GameConfig.lacquer_of(color_name)["base"]
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = lacquer if not taken else lacquer.darkened(0.7)
		if state == "hover" and not mine:
			style.bg_color = lacquer.lightened(0.15)
		style.set_corner_radius_all(26)
		style.set_border_width_all(5 if mine else 2)
		style.border_color = MenuStyle.GOLD if mine else MenuStyle.LEAF_EDGE
		pot.add_theme_stylebox_override(state, style)
	return pot
