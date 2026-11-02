extends Control

## The main menu's shell (the game's first scene). It owns the courtyard stage behind the
## menu, the palm-leaf panel, and the online session; the pages themselves are separate
## MenuScreens from SCREENS (swap one by registering another under its name):
##   home -> join -> connecting -> lobby, and settings / how_to_play / credits.
## Screens only say what the player wants (navigate / action); this shell connects,
## hosts and leaves through NetSession, and moves between screens. When the match
## starts, the stage glides down into the seated view and MainGame takes over.
## Layout: the panel sits in the screen's safe area and scrolls when it doesn't fit
## (small screens, large UI size). Pad / keyboard: every screen offers its first
## control; B / Esc goes back; PageUp / PageDown or the right stick scroll.
## Rejoining: the last room's seat token is saved, so joining the same room again
## mid-match puts you back in your seat.
## Developer command-line options (--host, --join, --bot...): see net/DevFlags.gd.

const MUSIC := &"courtyard_dusk"
const SCREENS := {
	&"home": preload("res://menu/screens/HomeScreen.gd"),
	&"join": preload("res://menu/screens/JoinScreen.gd"),
	&"connecting": preload("res://menu/screens/ConnectingScreen.gd"),
	&"lobby": preload("res://menu/screens/LobbyScreen.gd"),
	&"settings": preload("res://menu/screens/SettingsScreen.gd"),
	&"how_to_play": preload("res://menu/screens/HowToPlayScreen.gd"),
	&"credits": preload("res://menu/screens/CreditsScreen.gd"),
}
const MARGIN := 24.0
const PANEL_MIN_WIDTH := 400.0
const PANEL_MAX_WIDTH := 560.0
const PANEL_SHARE := 0.42
const STICK_SCROLL_SPEED := 900.0

## Screen registry (id -> MenuScreen script); replace entries to plug in other screens.
var screens: Dictionary = SCREENS.duplicate()
var _net: NetSession
var _stage: MenuStage
var _backdrop: ColorRect
var _panel: PanelContainer
var _scroll: ScrollContainer
## Holds the current screen's footer: its main buttons, always in view.
var _footer_slot: VBoxContainer
var _screen: MenuScreen
var _screen_id: StringName
var _autostart: int = 0
var _host_port: int = NetSession.DEFAULT_PORT
## The server URL being joined (to save its seat token once welcomed).
var _join_url: String = ""
## --no-tunnel (DevFlags): host on the local network only, no room code.
var _no_tunnel: bool = false

func _ready() -> void:
	GameFonts.install()
	Settings.reload() # another window on this machine may have changed them
	Display.apply(get_tree())
	GameInput.ensure(get_tree())
	Sound.ensure(get_tree())
	theme = MenuStyle.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = MenuStage.new()
	_stage.name = "Stage"
	add_child(_stage)
	_backdrop = ColorRect.new() # only where there's no 3D courtyard
	_backdrop.color = Color(0.16, 0.11, 0.08)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = not _stage.enabled
	add_child(_backdrop)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_footer_slot = VBoxContainer.new()
	column.add_child(_footer_slot)
	_stage.figure_clicked.connect(func(figure: String):
		if _screen:
			_screen.on_figure_clicked(figure))
	get_viewport().size_changed.connect(_layout)
	_layout()
	Platform.begin_paste_hook(_paste_into_focus)
	# The session lives under the root (survives scene changes); add it once the root is free
	_setup.call_deferred()

func _setup() -> void:
	Sound.music(MUSIC) # carries on into the match
	Sound.ambience(&"")
	_net = NetSession.ensure(get_tree())
	_net.leave() # coming back from a match: start clean
	_net.scene_loader = _launch_match
	# Method callables (not lambdas) so the connections end when this screen is freed
	_net.joined.connect(_on_joined)
	_net.connection_failed.connect(_on_join_failed)
	_net.disconnected.connect(_on_disconnected)
	_net.join_retrying.connect(_on_join_retrying)
	if _apply_dev_flags():
		return
	# Web invite links: .../index.html?room=brave-lemon-kite-maple opens Join with the code filled in
	var invited := Platform.invite_code()
	if invited != "":
		Settings.set_value(Settings.PLAYER, Settings.LAST_ADDRESS, invited)
		show_screen(&"join")
	else:
		show_screen(&"home")

# --- LAYOUT ---
## The panel on the left of the safe area, as tall as it allows; the courtyard is
## framed in the space to its right.
func _layout() -> void:
	var safe := Display.safe_rect(get_viewport())
	var width := clampf(safe.size.x * PANEL_SHARE, minf(PANEL_MIN_WIDTH, safe.size.x - MARGIN * 2.0), PANEL_MAX_WIDTH)
	_panel.position = safe.position + Vector2(MARGIN, MARGIN)
	_panel.size = Vector2(width, safe.size.y - MARGIN * 2.0)
	var screen_width := get_viewport().get_visible_rect().size.x
	_stage.set_view_margin((_panel.position.x + width) / maxf(screen_width, 1.0))

# --- SCREENS ---
## Shows a registered screen. args go to the screen (e.g. {"error": "..."}).
func show_screen(id: StringName, args: Dictionary = {}) -> void:
	if not screens.has(id):
		push_error("StartScreen: no screen called %s" % id)
		return
	if _screen:
		_scroll.remove_child(_screen)
		if _screen.footer.get_parent() == _footer_slot:
			_footer_slot.remove_child(_screen.footer)
		_screen.queue_free()
	_screen_id = id
	_screen = (screens[id] as GDScript).new()
	_screen.name = String(id).to_pascal_case()
	_screen.net = _net
	_screen.stage = _stage
	_screen.args = args
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.navigate.connect(show_screen)
	_screen.action.connect(_on_action)
	_scroll.add_child(_screen)
	_footer_slot.add_child(_screen.footer)
	_scroll.scroll_vertical = 0
	GameInput.offer_focus(get_tree(), _screen.first_focus())

func _on_action(action_name: StringName, args: Dictionary) -> void:
	match action_name:
		&"host":
			_host(_host_port)
		&"join":
			_join(String(args.get("address", "")))
		&"paste":
			Platform.read_clipboard(_paste_address, "Paste the room code (or the whole invite) here:")
		&"cancel_join":
			_net.leave()
			show_screen(&"join")
		&"leave":
			_net.leave()
			show_screen(&"home")

func _unhandled_input(event: InputEvent) -> void:
	if _screen and event.is_action_pressed("pick_cancel"):
		_screen.go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down") or event.is_action_pressed("ui_page_up"):
		_scroll.scroll_vertical += int(_scroll.size.y * 0.8) * (1 if event.is_action_pressed("ui_page_down") else -1)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Pads: the right stick scrolls long pages (credits, rules)
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(stick) > 0.2 and _scroll:
		_scroll.scroll_vertical += int(stick * STICK_SCROLL_SPEED * delta)

# --- PASTE (Platform does the web part) ---
func _exit_tree() -> void:
	Platform.end_paste_hook()

func _input(event: InputEvent) -> void:
	if Platform.is_native_paste_blocked(event) and get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()

## Web: the browser's paste goes into whichever text box has focus (an invite into the
## join box becomes its room code).
func _paste_into_focus(text: String) -> void:
	var edit := get_viewport().gui_get_focus_owner() as LineEdit
	if edit == null or text.strip_edges() == "":
		return
	if _screen is JoinScreen and edit.name == "JoinAddress":
		(_screen as JoinScreen).paste_text(text)
	else:
		edit.insert_text_at_caret(text.strip_edges())

func _paste_address(text: String) -> void:
	if _screen is JoinScreen:
		(_screen as JoinScreen).paste_text(text)

# --- CONNECTING ---
## The name to join with: the platform account's, else the one saved on the home screen.
func _saved_name() -> String:
	var system_name := Platform.system_player_name()
	if system_name != "":
		return system_name
	var saved := String(Settings.get_value(Settings.PLAYER, Settings.NAME, "")).strip_edges()
	return saved if saved != "" else "Player"

func _host(port: int = NetSession.DEFAULT_PORT) -> void:
	_net.local_figure = HomeScreen.saved_figure()
	_host_port = port
	var err := _net.host(_saved_name(), port)
	if err != OK:
		show_screen(&"home", {"error": "Couldn't host on port %d (%s). Is another game already hosting?" % [port, error_string(err)]})
		return
	_show_lobby()
	if _no_tunnel:
		(_screen as LobbyScreen).show_no_room_code("Room code off (--no-tunnel).")
	else:
		_net.open_room_code(port)

func _join(typed: String) -> void:
	var address := _net.transport.find_address(typed)
	var url := _net.transport.to_target(address)
	if url == "":
		show_screen(&"join", {"error": "Type the address the host gave you."})
		return
	Settings.set_value(Settings.PLAYER, Settings.LAST_ADDRESS, address)
	_join_url = url
	# Same room as last time: offer our old seat's token (only used if a match is running)
	var token: String = Settings.get_value(Settings.SESSION, Settings.SESSION_TOKEN, "") \
		if Settings.get_value(Settings.SESSION, Settings.SESSION_URL, "") == url else ""
	_net.local_figure = HomeScreen.saved_figure()
	var err := _net.join(url, _saved_name(), token)
	if err != OK:
		show_screen(&"join", {"error": "Couldn't connect (%s)." % error_string(err)})
		return
	show_screen(&"connecting", {"where": address})

func _show_lobby() -> void:
	show_screen(&"lobby", {"host_port": _host_port, "autostart": _autostart})
	_autostart = 0

func _on_joined(_seat: int) -> void:
	# Remember this seat: joining the same room again (e.g. after a reload) reclaims it
	Settings.set_value(Settings.SESSION, Settings.SESSION_URL, _join_url)
	Settings.set_value(Settings.SESSION, Settings.SESSION_TOKEN, _net.get_token())
	_show_lobby()

func _on_join_failed(reason: String) -> void:
	show_screen(&"join", {"error": reason})

func _on_disconnected(reason: String) -> void:
	show_screen(&"home", {"error": reason})

func _on_join_retrying(attempt: int) -> void:
	if _screen_id == &"connecting":
		show_screen(&"connecting", {"where": Settings.get_value(Settings.PLAYER, Settings.LAST_ADDRESS, ""),
			"note": "Not answering yet, trying again (%d of %d)..." % [attempt, NetSession.JOIN_ATTEMPTS]})

## The match starts (NetSession's scene_loader): the panel fades, the courtyard glides
## down to this player's seat, then MainGame replaces the menu.
func _launch_match(setup: MatchSetup) -> void:
	var sides := GameConfig.seats_for(setup.players.size())
	var seat := maxi(_net.local_seat, 0)
	create_tween().tween_property(_panel, "modulate:a", 0.0, 0.35)
	await _stage.to_match(sides[seat] if seat < sides.size() else 0)
	setup.launch(get_tree())

## Developer command-line options (DevFlags; debug builds only). Returns true if used.
func _apply_dev_flags() -> bool:
	var opts := DevFlags.parse()
	if opts.is_empty():
		return false
	if opts.has("--name"):
		Settings.set_value(Settings.PLAYER, Settings.NAME, opts["--name"])
	DevFlags.apply_tooling(opts, get_tree())
	show_screen(&"home")
	_no_tunnel = opts.has("--no-tunnel")
	if opts.has("--host"):
		_host_port = int(opts.get("--port", NetSession.DEFAULT_PORT))
		_autostart = int(opts.get("--autostart", "0"))
		_host(_host_port)
		if opts.has("--no-cards"):
			_net.set_setting("cards", false)
		if opts.has("--open-draft"):
			_net.set_setting("draft", GameConfig.DRAFT_OPEN)
	else:
		_join(opts["--join"])
	return true
