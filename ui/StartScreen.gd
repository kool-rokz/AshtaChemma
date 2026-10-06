extends Control

## Main menu (the game's first screen): pick your name, then Host a game or Join one.
## Both lead to the lobby (LobbyView). Online only; the match itself is MainGame.tscn.
## Rejoining: the last room's seat token is saved, so joining the same room again
## mid-match puts you back in your seat.
## Developer command-line options (--host, --join, --bot...): see net/DevFlags.gd.

const SETTINGS_PATH := "user://settings.cfg"

enum Screen { HOME, JOIN, CONNECTING, LOBBY }

var _screen: Screen = Screen.HOME
var _content: VBoxContainer
var _net: NetSession
var _settings := ConfigFile.new()
var _name_edit: LineEdit
var _address_edit: LineEdit
var _lobby: LobbyView
var _autostart: int = 0
var _host_port: int = NetSession.DEFAULT_PORT
## The server URL being joined (to save its seat token once welcomed).
var _join_url: String = ""
## --no-tunnel (DevFlags): host on the local network only, no room code.
var _no_tunnel: bool = false
## Web: kept alive while JavaScript may call them.
var _web_paste_callback: JavaScriptObject
var _web_clipboard_callbacks: Array[JavaScriptObject] = []

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
	_hook_web_paste()
	# The session lives under the root (survives scene changes); add it once the root is free
	_setup.call_deferred()

func _setup() -> void:
	_net = NetSession.ensure(get_tree())
	_net.leave() # coming back from a match: start clean
	# Method callables (not lambdas) so the connections end when this screen is freed
	_net.joined.connect(_on_joined)
	_net.connection_failed.connect(_on_join_failed)
	_net.disconnected.connect(_show_home)
	_net.join_retrying.connect(_on_join_retrying)
	if _apply_dev_flags():
		return
	# Web invite links: .../index.html?room=brave-lemon-kite-maple opens Join with the code filled in
	var invited := _room_from_page_url()
	if invited != "":
		_settings.set_value("player", "last_address", invited)
		_show_join()
	else:
		_show_home()

func _on_joined(_seat: int) -> void:
	# Remember this seat: joining the same room again (e.g. after a reload) reclaims it
	_settings.set_value("session", "url", _join_url)
	_settings.set_value("session", "token", _net.get_token())
	_settings.save(SETTINGS_PATH)
	_show_lobby()

func _on_join_failed(reason: String) -> void:
	_show_join(reason)

func _on_join_retrying(attempt: int) -> void:
	if _screen == Screen.CONNECTING:
		_show_connecting(_settings.get_value("player", "last_address", ""), "Not answering yet, trying again (%d of %d)..." % [attempt, NetSession.JOIN_ATTEMPTS])

## Web builds: the room code from the page address, if the invite link carried one.
func _room_from_page_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var room: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
	return str(room).strip_edges() if room != null else ""

# --- PASTE ---
## Browsers don't let Godot read the clipboard on Ctrl+V, but they do hand the text
## to a "paste" event: put it into whichever text field has focus.
func _hook_web_paste() -> void:
	if not OS.has_feature("web"):
		return
	_web_paste_callback = JavaScriptBridge.create_callback(_on_web_paste)
	JavaScriptBridge.get_interface("window").addEventListener("paste", _web_paste_callback)

func _on_web_paste(args: Array) -> void:
	var data: Variant = args[0].clipboardData
	if data != null:
		_paste_into_focus(str(data.getData("text")))

## Web: let the browser's paste event do the pasting (Godot's own Ctrl+V would paste
## its internal clipboard, which is usually empty or stale there).
func _input(event: InputEvent) -> void:
	if OS.has_feature("web") and event is InputEventKey and event.pressed \
			and event.keycode == KEY_V and (event.ctrl_pressed or event.meta_pressed) \
			and get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()

func _paste_into_focus(text: String) -> void:
	var edit := get_viewport().gui_get_focus_owner() as LineEdit
	if edit and text != "":
		edit.insert_text_at_caret(text.strip_edges())

## The Paste button next to the address field (also for phones, which have no Ctrl+V).
func _paste_address() -> void:
	if not OS.has_feature("web"):
		_address_edit.text = DisplayServer.clipboard_get().strip_edges()
		return
	var clipboard: Variant = JavaScriptBridge.get_interface("navigator").clipboard
	if clipboard == null:
		_show_join("This browser can't paste from a button. Click the box and press Ctrl+V.")
		return
	var on_text := JavaScriptBridge.create_callback(func(args: Array):
		if _address_edit and is_instance_valid(_address_edit):
			_address_edit.text = str(args[0]).strip_edges())
	var on_error := JavaScriptBridge.create_callback(func(_args: Array):
		_show_join("The browser didn't allow pasting. Click the box and press Ctrl+V."))
	_web_clipboard_callbacks = [on_text, on_error]
	clipboard.readText().then(on_text, on_error)

# --- SCREENS ---
func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()
	_lobby = null
	_address_edit = null

func _show_home(error: String = "") -> void:
	_clear()
	_screen = Screen.HOME
	_content.add_child(MenuWidgets.label("Ashta Chemma", 44))
	_content.add_child(MenuWidgets.label("Online with friends", 18, MenuWidgets.MUTED))

	_content.add_child(MenuWidgets.label("Your name", 16, MenuWidgets.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit = MenuWidgets.line_edit(_settings.get_value("player", "name", ""), "Player")
	_name_edit.name = "PlayerName"
	_name_edit.max_length = GameConfig.NAME_MAX_LENGTH
	_content.add_child(_name_edit)

	var host := MenuWidgets.button("Host a game")
	host.name = "HostGame"
	host.pressed.connect(_host)
	# Browsers can't accept connections, so only desktop builds can host
	host.visible = not OS.has_feature("web")
	_content.add_child(host)
	var join := MenuWidgets.button("Join a game")
	join.name = "JoinGame"
	join.pressed.connect(_show_join)
	_content.add_child(join)
	_add_error(error)
	_content.add_child(MenuWidgets.label("v" + GameConfig.GAME_VERSION, 12, Color(0.45, 0.45, 0.5)))

func _show_join(error: String = "") -> void:
	_remember_name()
	_clear()
	_screen = Screen.JOIN
	_content.add_child(MenuWidgets.label("Join a game", 32))
	_content.add_child(MenuWidgets.label("Type or paste the room code the host gave you (or an address like 192.168.1.23:9080 on the same network).", 15, MenuWidgets.MUTED))
	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 8)
	_address_edit = MenuWidgets.line_edit(_settings.get_value("player", "last_address", ""), "room code, e.g. brave-lemon-kite-maple")
	_address_edit.name = "JoinAddress"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.text_submitted.connect(_join)
	address_row.add_child(_address_edit)
	var paste := MenuWidgets.button("Paste", Vector2(96, 44))
	paste.name = "PasteAddress"
	paste.focus_mode = Control.FOCUS_NONE # keep the caret in the box
	paste.pressed.connect(_paste_address)
	address_row.add_child(paste)
	_content.add_child(address_row)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var back := MenuWidgets.button("Back", Vector2(140, 48))
	back.pressed.connect(func(): _show_home())
	actions.add_child(back)
	var go := MenuWidgets.button("Join")
	go.name = "JoinConfirm"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func(): _join(_address_edit.text))
	actions.add_child(go)
	_content.add_child(actions)
	_add_error(error)

func _show_connecting(where: String, note: String = "") -> void:
	_clear()
	_screen = Screen.CONNECTING
	_content.add_child(MenuWidgets.label("Connecting...", 28))
	_content.add_child(MenuWidgets.label(where, 15, MenuWidgets.MUTED))
	if note != "":
		_content.add_child(MenuWidgets.label(note, 15, MenuWidgets.MUTED))
	var cancel := MenuWidgets.button("Cancel", Vector2(160, 48))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func():
		_net.leave()
		_show_join())
	_content.add_child(cancel)

func _show_lobby() -> void:
	_clear()
	_screen = Screen.LOBBY
	_lobby = LobbyView.new(_net, _host_port, _autostart)
	_autostart = 0
	_lobby.left.connect(func():
		_net.leave()
		_show_home())
	_content.add_child(_lobby)

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
	if _no_tunnel:
		_lobby.show_no_room_code("Room code off (--no-tunnel).")
	else:
		_net.open_room_code(port)

func _join(typed: String) -> void:
	var address := NetSession.find_address(typed)
	var url := NetSession.address_to_url(address)
	if url == "":
		_show_join("Type the address the host gave you.")
		return
	_settings.set_value("player", "last_address", address)
	_settings.save(SETTINGS_PATH)
	_join_url = url
	# Same room as last time: offer our old seat's token (only used if a match is running)
	var token: String = _settings.get_value("session", "token", "") if _settings.get_value("session", "url", "") == url else ""
	var err := _net.join(url, _settings.get_value("player", "name", "Player"), token)
	if err != OK:
		_show_join("Couldn't connect (%s)." % error_string(err))
		return
	_show_connecting(address)

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

func _add_error(text: String) -> void:
	var error := MenuWidgets.label(text, 15, MenuWidgets.ERROR)
	error.visible = text != ""
	_content.add_child(error)
