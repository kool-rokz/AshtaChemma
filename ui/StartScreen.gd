extends Control

## Main menu (the game's first screen): pick your name, then Host a game or Join one.
## Both lead to the lobby: players and their colours, the host's card setting, and
## the host's Start button. Online only; the match itself is MainGame.tscn.
## Developer command-line options (--host, --join, --bot...): see net/DevFlags.gd.

const SETTINGS_PATH := "user://settings.cfg"
const MUTED := Color(0.7, 0.7, 0.75)
const ERROR_COLOR := Color(0.95, 0.45, 0.4)

enum Screen { HOME, JOIN, CONNECTING, LOBBY }

var _screen: Screen = Screen.HOME
var _content: VBoxContainer
var _net: NetSession
var _settings := ConfigFile.new()
var _name_edit: LineEdit
var _error: Label
var _autostart: int = 0
var _host_port: int = NetSession.DEFAULT_PORT
## --no-tunnel (DevFlags): host on the local network only, no room code.
var _no_tunnel: bool = false

# Lobby widgets (rebuilt on roster changes)
var _players_box: VBoxContainer
var _swatches_box: HBoxContainer
var _cards_toggle: CheckBox
var _start_button: Button
var _lobby_status: Label
var _room_code_label: Label
var _room_status: Label
var _copy_button: Button

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
	_content.add_theme_constant_override("separation", 16)
	panel.add_child(_content)

	_settings.load(SETTINGS_PATH)
	# The session lives under the root (survives scene changes); add it once the root is free
	_setup.call_deferred()

func _setup() -> void:
	_net = NetSession.ensure(get_tree())
	_net.leave() # coming back from a match: start clean
	# Method callables (not lambdas) so the connections end when this screen is freed
	_net.roster_changed.connect(_on_roster_changed)
	_net.settings_changed.connect(_on_settings_changed)
	_net.joined.connect(_on_joined)
	_net.connection_failed.connect(_on_join_failed)
	_net.disconnected.connect(_show_home)
	_net.join_retrying.connect(_on_join_retrying)
	_net.room_status.connect(_on_room_status)
	_net.room_code_ready.connect(_on_room_code_ready)
	_net.room_code_failed.connect(_on_room_code_failed)
	if _apply_dev_flags():
		return
	# Web invite links: .../index.html?room=brave-lemon-kite-maple opens Join with the code filled in
	var invited := _room_from_page_url()
	if invited != "":
		_settings.set_value("player", "last_address", invited)
		_show_join()
	else:
		_show_home()

func _on_roster_changed(_roster: Array) -> void:
	_refresh_lobby()

func _on_settings_changed(_settings_now: Dictionary) -> void:
	_refresh_lobby()

func _on_joined(_seat: int) -> void:
	_show_lobby()

func _on_join_failed(reason: String) -> void:
	_show_join(reason)

func _on_join_retrying(attempt: int) -> void:
	if _screen == Screen.CONNECTING:
		_show_connecting(_settings.get_value("player", "last_address", ""), "Not answering yet, trying again (%d of %d)..." % [attempt, NetSession.JOIN_ATTEMPTS])

func _on_room_status(text: String) -> void:
	if _screen == Screen.LOBBY and _room_status and is_instance_valid(_room_status):
		_room_status.text = text

func _on_room_code_ready(code: String, live: bool) -> void:
	if _screen == Screen.LOBBY and _room_code_label and is_instance_valid(_room_code_label):
		_room_code_label.text = code
		_room_status.text = "Share this code. Friends pick Join a game and type it in (PC or browser)." if live \
			else "Cloudflare is slow to confirm this code; it may take a minute before friends can join."
		_copy_button.visible = true

func _on_room_code_failed(reason: String) -> void:
	if _screen == Screen.LOBBY and _room_code_label and is_instance_valid(_room_code_label):
		_room_code_label.text = "No room code"
		_room_status.text = reason + " Friends on your network can still use the address below."

## Copies the code, plus the game's web page if one is set (GameConfig.PLAY_URL).
func _copy_invite() -> void:
	var code := _net.room_code
	var text := "Join my Ashta Chemma game! Room code: %s" % code
	if GameConfig.PLAY_URL != "":
		text = "Join my Ashta Chemma game: %s  (Join a game, room code: %s)" % [GameConfig.PLAY_URL, code]
	DisplayServer.clipboard_set(text)
	_room_status.text = "Copied! Paste it to your friends."

## Web builds: the room code from the page address, if the invite link carried one.
func _room_from_page_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var room: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
	return str(room).strip_edges() if room != null else ""

# --- SCREENS ---
func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()
	_players_box = null

func _show_home(error: String = "") -> void:
	_clear()
	_screen = Screen.HOME
	_content.add_child(_label("Ashta Chemma", 44))
	_content.add_child(_label("Online with friends", 18, MUTED))

	_content.add_child(_label("Your name", 16, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = LineEdit.new()
	_name_edit.name = "PlayerName"
	_name_edit.max_length = GameConfig.NAME_MAX_LENGTH
	_name_edit.placeholder_text = "Player"
	_name_edit.text = _settings.get_value("player", "name", "")
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_content.add_child(_name_edit)

	var host := _button("Host a game")
	host.name = "HostGame"
	host.pressed.connect(_host)
	# Browsers can't accept connections, so only desktop builds can host
	host.visible = not OS.has_feature("web")
	_content.add_child(host)
	var join := _button("Join a game")
	join.name = "JoinGame"
	join.pressed.connect(_show_join)
	_content.add_child(join)
	_add_error(error)
	_content.add_child(_label("v" + GameConfig.GAME_VERSION, 12, Color(0.45, 0.45, 0.5)))

func _show_join(error: String = "") -> void:
	_remember_name()
	_clear()
	_screen = Screen.JOIN
	_content.add_child(_label("Join a game", 32))
	_content.add_child(_label("Type the room code the host gave you (or an address like 192.168.1.23:9080 on the same network).", 15, MUTED))
	var address := LineEdit.new()
	address.name = "JoinAddress"
	address.placeholder_text = "room code, e.g. brave-lemon-kite-maple"
	address.text = _settings.get_value("player", "last_address", "")
	address.custom_minimum_size = Vector2(0, 44)
	address.add_theme_font_size_override("font_size", 18)
	_content.add_child(address)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var back := _button("Back", Vector2(140, 48))
	back.pressed.connect(func(): _show_home())
	actions.add_child(back)
	var go := _button("Join")
	go.name = "JoinConfirm"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func(): _join(address.text))
	address.text_submitted.connect(func(text): _join(text))
	actions.add_child(go)
	_content.add_child(actions)
	_add_error(error)

func _show_connecting(where: String, note: String = "") -> void:
	_clear()
	_screen = Screen.CONNECTING
	_content.add_child(_label("Connecting...", 28))
	_content.add_child(_label(where, 15, MUTED))
	if note != "":
		_content.add_child(_label(note, 15, MUTED))
	var cancel := _button("Cancel", Vector2(160, 48))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func():
		_net.leave()
		_show_join())
	_content.add_child(cancel)

func _show_lobby() -> void:
	_clear()
	_screen = Screen.LOBBY
	_content.add_child(_label("Lobby", 32))
	if _net.is_host():
		_content.add_child(_label("Room code", 15, MUTED))
		_room_code_label = _label(_net.room_code if _net.room_code != "" else "...", 30, Color(1.0, 0.85, 0.4))
		_room_code_label.name = "RoomCode"
		_content.add_child(_room_code_label)
		_room_status = _label("Getting a room code...", 14, MUTED)
		_content.add_child(_room_status)
		_copy_button = _button("Copy invite", Vector2(220, 40))
		_copy_button.name = "CopyInvite"
		_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_copy_button.visible = _net.room_code != ""
		_copy_button.pressed.connect(_copy_invite)
		_content.add_child(_copy_button)
		var addresses := _label("Same network: " + ", ".join(_lan_addresses()), 13, MUTED)
		addresses.name = "HostAddresses"
		_content.add_child(addresses)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	_content.add_child(_players_box)

	_content.add_child(_label("Your colour", 15, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_swatches_box = HBoxContainer.new()
	_swatches_box.add_theme_constant_override("separation", 12)
	_content.add_child(_swatches_box)

	_cards_toggle = CheckBox.new()
	_cards_toggle.name = "PlayWithCards"
	_cards_toggle.text = "Play with cards"
	_cards_toggle.add_theme_font_size_override("font_size", 18)
	_cards_toggle.disabled = not _net.is_host()
	_cards_toggle.toggled.connect(func(on): _net.set_setting("cards", on))
	_content.add_child(_cards_toggle)

	_lobby_status = _label("", 15, MUTED)
	_content.add_child(_lobby_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var leave := _button("Leave", Vector2(140, 48))
	leave.pressed.connect(func():
		_net.leave()
		_show_home())
	actions.add_child(leave)
	_start_button = _button("Start game")
	_start_button.name = "StartGame"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.visible = _net.is_host()
	_start_button.pressed.connect(_net.start_match)
	actions.add_child(_start_button)
	_content.add_child(actions)
	_refresh_lobby()

func _refresh_lobby() -> void:
	if _players_box == null or not is_instance_valid(_players_box):
		return
	for child in _players_box.get_children():
		child.queue_free()
	for entry in _net.roster:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.color = GameConfig.COLORS.get(entry["color_name"], Color.WHITE)
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var tags: Array[String] = []
		if entry["seat"] == 0:
			tags.append("host")
		if entry["seat"] == _net.local_seat:
			tags.append("you")
		if not entry["connected"]:
			tags.append("disconnected")
		var text: String = entry["name"] + ("  (%s)" % ", ".join(tags) if not tags.is_empty() else "")
		var name_label := _label(text, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		# Wrapping labels have no minimum width; let the name take the row
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		_players_box.add_child(row)

	# Colour swatches: yours outlined, other players' colours unavailable
	for child in _swatches_box.get_children():
		child.queue_free()
	var mine: String = _net.local_entry().get("color_name", "")
	for color_name in GameConfig.COLORS:
		var taken: bool = _net.roster.any(func(e): return e["color_name"] == color_name and e["seat"] != _net.local_seat)
		var button := Button.new()
		button.name = "Color" + color_name
		button.tooltip_text = color_name + (" (taken)" if taken else "")
		button.custom_minimum_size = Vector2(44, 44)
		button.disabled = taken
		button.pressed.connect(_net.request_color.bind(color_name))
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = GameConfig.COLORS[color_name]
			if color_name != mine:
				style.bg_color = style.bg_color.darkened(0.75 if taken else (0.25 if state == "hover" else 0.45))
			style.set_corner_radius_all(22)
			style.set_border_width_all(4 if color_name == mine else 0)
			style.border_color = Color.WHITE
			button.add_theme_stylebox_override(state, style)
		_swatches_box.add_child(button)

	_cards_toggle.set_pressed_no_signal(bool(_net.settings.get("cards", true)))
	var count := _net.roster.size()
	if _net.is_host():
		_start_button.disabled = count < GameConfig.MIN_PLAYERS
		_lobby_status.text = "Waiting for players (2-4)." if count < GameConfig.MIN_PLAYERS else "%d players in. Start when everyone's here." % count
		if _autostart > 0 and count >= _autostart:
			_autostart = 0
			_net.start_match()
	else:
		_lobby_status.text = "Waiting for the host to start..."

# --- ACTIONS ---
func _player_name() -> String:
	var typed := _name_edit.text.strip_edges() if _name_edit and is_instance_valid(_name_edit) else ""
	return typed if typed != "" else "Player"

func _remember_name() -> void:
	if _name_edit and is_instance_valid(_name_edit):
		_settings.set_value("player", "name", _name_edit.text.strip_edges())
		_settings.save(SETTINGS_PATH)

func _host(port: int = NetSession.DEFAULT_PORT) -> void:
	_remember_name()
	_host_port = port
	var err := _net.host(_player_name(), port)
	if err != OK:
		_show_home("Couldn't host on port %d (%s). Is another game already hosting?" % [port, error_string(err)])
		return
	_show_lobby()
	if not _no_tunnel:
		_net.open_room_code(port)
	else:
		_on_room_code_failed("Room code off (--no-tunnel).")

func _join(address: String) -> void:
	var url := NetSession.address_to_url(address)
	if url == "":
		_show_join("Type the address the host gave you.")
		return
	_settings.set_value("player", "last_address", address.strip_edges())
	_settings.save(SETTINGS_PATH)
	var err := _net.join(url, _settings.get_value("player", "name", "Player"))
	if err != OK:
		_show_join("Couldn't connect (%s)." % error_string(err))
		return
	_show_connecting(address.strip_edges())

## This PC's addresses on the local network, for friends on the same Wi-Fi.
func _lan_addresses() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append("%s:%d" % [ip, _host_port])
	if result.is_empty():
		result.append("127.0.0.1:%d (this PC only)" % _host_port)
	return result

## Developer command-line options (DevFlags; debug builds only). Returns true if used.
func _apply_dev_flags() -> bool:
	var opts := DevFlags.parse()
	if opts.is_empty():
		return false
	if opts.has("--name"):
		_settings.set_value("player", "name", opts["--name"])
	DevFlags.apply_tooling(opts, get_tree())
	_show_home()
	_no_tunnel = opts.has("--no-tunnel")
	if opts.has("--host"):
		_host_port = int(opts.get("--port", NetSession.DEFAULT_PORT))
		_autostart = int(opts.get("--autostart", "0"))
		_host(_host_port)
		if opts.has("--no-cards"):
			_net.set_setting("cards", false)
	else:
		_join(opts["--join"])
	return true

# --- WIDGETS ---
func _label(text: String, font_size: int, color: Color = Color(0.92, 0.92, 0.95), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, min_size := Vector2(0, 52)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 20)
	return button

func _add_error(text: String) -> void:
	_error = _label(text, 15, ERROR_COLOR)
	_error.visible = text != ""
	_content.add_child(_error)
