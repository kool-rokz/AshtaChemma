class_name LobbyView
extends VBoxContainer

## The lobby, for the host and for guests: the room code (host), who's in, colour
## swatches, the host's card setting and Start button. Built by StartScreen once
## connected; reads and changes the room only through NetSession.

## The player pressed Leave.
signal left

var _net: NetSession
var _host_port: int
## Developer --autostart: start as soon as this many players are in (0 = off).
var _autostart: int

var _players_box: VBoxContainer
var _swatches_box: HBoxContainer
var _cards_toggle: CheckBox
var _start_button: Button
var _lobby_status: Label
var _room_code_label: Label
var _room_status: Label
var _copy_button: Button

func _init(net: NetSession, host_port: int, autostart: int = 0) -> void:
	_net = net
	_host_port = host_port
	_autostart = autostart
	add_theme_constant_override("separation", 16)

func _ready() -> void:
	add_child(MenuWidgets.label("Lobby", 32))
	if _net.is_host():
		_build_room_code()

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	add_child(_players_box)

	add_child(MenuWidgets.label("Your colour", 15, MenuWidgets.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_swatches_box = HBoxContainer.new()
	_swatches_box.add_theme_constant_override("separation", 12)
	add_child(_swatches_box)

	_cards_toggle = CheckBox.new()
	_cards_toggle.name = "PlayWithCards"
	_cards_toggle.text = "Play with cards"
	_cards_toggle.add_theme_font_size_override("font_size", 18)
	_cards_toggle.disabled = not _net.is_host()
	_cards_toggle.toggled.connect(func(on): _net.set_setting("cards", on))
	add_child(_cards_toggle)

	_lobby_status = MenuWidgets.label("", 15, MenuWidgets.MUTED)
	add_child(_lobby_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var leave := MenuWidgets.button("Leave", Vector2(140, 48))
	leave.pressed.connect(left.emit)
	actions.add_child(leave)
	_start_button = MenuWidgets.button("Start game")
	_start_button.name = "StartGame"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.visible = _net.is_host()
	_start_button.pressed.connect(_net.start_match)
	actions.add_child(_start_button)
	add_child(actions)

	# Method callables (not lambdas) so the connections end when this view is freed
	_net.roster_changed.connect(_on_roster_changed)
	_net.settings_changed.connect(_on_settings_changed)
	_net.room_status.connect(_on_room_status)
	_net.room_code_ready.connect(_on_room_code_ready)
	_net.room_code_failed.connect(show_no_room_code)
	_refresh()

func _build_room_code() -> void:
	add_child(MenuWidgets.label("Room code", 15, MenuWidgets.MUTED))
	_room_code_label = MenuWidgets.label(_net.room_code if _net.room_code != "" else "...", 30, MenuWidgets.HIGHLIGHT)
	_room_code_label.name = "RoomCode"
	add_child(_room_code_label)
	_room_status = MenuWidgets.label("Getting a room code...", 14, MenuWidgets.MUTED)
	add_child(_room_status)
	_copy_button = MenuWidgets.button("Copy invite", Vector2(220, 40))
	_copy_button.name = "CopyInvite"
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_copy_button.visible = _net.room_code != ""
	_copy_button.pressed.connect(_copy_invite)
	add_child(_copy_button)
	var addresses := MenuWidgets.label("Same network: " + ", ".join(_lan_addresses()), 13, MenuWidgets.MUTED)
	addresses.name = "HostAddresses"
	add_child(addresses)

## Host: no room code this time (Cloudflare failed, or --no-tunnel).
func show_no_room_code(reason: String) -> void:
	if _room_code_label == null:
		return
	_room_code_label.text = "No room code"
	_room_status.text = reason + " Friends on your network can still use the address below."

func _on_roster_changed(_roster: Array) -> void:
	_refresh()

func _on_settings_changed(_settings: Dictionary) -> void:
	_refresh()

func _on_room_status(text: String) -> void:
	if _room_status:
		_room_status.text = text

func _on_room_code_ready(code: String, live: bool) -> void:
	if _room_code_label == null:
		return
	_room_code_label.text = code
	_room_status.text = "Share this code. Friends pick Join a game and type it in (PC or browser)." if live \
		else "Cloudflare is slow to confirm this code; it may take a minute before friends can join."
	_copy_button.visible = true

## Copies the code, plus the game's web page if one is set (GameConfig.PLAY_URL).
func _copy_invite() -> void:
	var code := _net.room_code
	var text := "Join my Ashta Chemma game! Room code: %s" % code
	if GameConfig.PLAY_URL != "":
		text = "Join my Ashta Chemma game: %s  (Join a game, room code: %s)" % [GameConfig.PLAY_URL, code]
	DisplayServer.clipboard_set(text)
	_room_status.text = "Copied! Paste it to your friends."

## This PC's addresses on the local network, for friends on the same Wi-Fi.
func _lan_addresses() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append("%s:%d" % [ip, _host_port])
	if result.is_empty():
		result.append("127.0.0.1:%d (this PC only)" % _host_port)
	return result

func _refresh() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	for entry in _net.roster:
		_players_box.add_child(_player_row(entry))

	# Colour swatches: yours outlined, other players' colours unavailable
	for child in _swatches_box.get_children():
		child.queue_free()
	var mine: String = _net.local_entry().get("color_name", "")
	for color_name in GameConfig.COLORS:
		var taken: bool = _net.roster.any(func(e): return e["color_name"] == color_name and e["seat"] != _net.local_seat)
		_swatches_box.add_child(_swatch(color_name, color_name == mine, taken))

	_cards_toggle.set_pressed_no_signal(bool(_net.settings.get("cards", true)))
	var count := _net.roster.size()
	if _net.is_host():
		_start_button.disabled = count < GameConfig.MIN_PLAYERS
		_lobby_status.text = "Waiting for players (%d-%d)." % [GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS] \
			if count < GameConfig.MIN_PLAYERS else "%d players in. Start when everyone's here." % count
		if _autostart > 0 and count >= _autostart:
			_autostart = 0
			_net.start_match()
	else:
		_lobby_status.text = "Waiting for the host to start..."

func _player_row(entry: Dictionary) -> HBoxContainer:
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
	var name_label := MenuWidgets.label(text, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	# Wrapping labels have no minimum width; let the name take the row
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row

func _swatch(color_name: String, mine: bool, taken: bool) -> Button:
	var button := Button.new()
	button.name = "Color" + color_name
	button.tooltip_text = color_name + (" (taken)" if taken else "")
	button.custom_minimum_size = Vector2(44, 44)
	button.disabled = taken
	button.pressed.connect(_net.request_color.bind(color_name))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = GameConfig.COLORS[color_name]
		if not mine:
			style.bg_color = style.bg_color.darkened(0.75 if taken else (0.25 if state == "hover" else 0.45))
		style.set_corner_radius_all(22)
		style.set_border_width_all(4 if mine else 0)
		style.border_color = Color.WHITE
		button.add_theme_stylebox_override(state, style)
	return button
