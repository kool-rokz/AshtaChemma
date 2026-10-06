class_name DevLobby
extends Control

## Developer-only lobby for testing online play in separate windows until the real
## lobby (phase 2) exists. The start screen shows it when launched with:
##   -- --host [--port=9080] [--name=Ana] [--autostart=2] [--no-cards]
##   -- --join=ws://127.0.0.1:9080 [--name=Ben]
## Add --bot to either to let that instance play its seat by itself.
## (Godot: Debug > Customize Run Instances lets each instance get its own arguments.)

var _net: NetSession
var _status: Label
var _roster: Label
var _start: Button
var _cards: bool = true
var _autostart: int = 0

## Parses the command line; returns {} when no network flags were given.
static func from_args(args: PackedStringArray) -> Dictionary:
	var opts := {}
	for arg in args:
		if arg == "--host":
			opts["host"] = true
		elif arg.begins_with("--join="):
			opts["join"] = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			opts["port"] = int(arg.get_slice("=", 1))
		elif arg.begins_with("--name="):
			opts["name"] = arg.get_slice("=", 1)
		elif arg.begins_with("--autostart="):
			opts["autostart"] = int(arg.get_slice("=", 1))
		elif arg == "--no-cards":
			opts["no_cards"] = true
		elif arg == "--bot":
			opts["bot"] = true
	return opts if opts.has("host") or opts.has("join") else {}

func setup(opts: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.16, 0.19)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(60, 60)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(_label("Online test lobby (developer)", 30))
	_status = _label("", 18)
	box.add_child(_status)
	_roster = _label("", 18)
	box.add_child(_roster)
	_start = Button.new()
	_start.text = "Start match"
	_start.custom_minimum_size = Vector2(240, 48)
	_start.visible = false
	_start.pressed.connect(func(): _net.start_match(_cards))
	box.add_child(_start)

	_cards = not opts.get("no_cards", false)
	_autostart = opts.get("autostart", 0)
	_net = NetSession.ensure(get_tree())
	if opts.get("bot", false):
		_net.auto_draft = true
		var bot := DevBot.new()
		bot.name = "DevBot"
		get_tree().root.add_child.call_deferred(bot)
	_net.roster_changed.connect(_on_roster)
	_net.joined.connect(func(seat): _status.text = "Connected. You are seat %d. Waiting for the host to start..." % (seat + 1))
	_net.connection_failed.connect(func(reason): _status.text = "Connection failed: " + reason)
	_net.disconnected.connect(func(reason): _status.text = reason)
	var player_name: String = opts.get("name", "Host" if opts.has("host") else "Guest")
	if opts.has("host"):
		var port: int = opts.get("port", NetSession.DEFAULT_PORT)
		var err := _net.host(player_name, port)
		_status.text = "Hosting on ws://127.0.0.1:%d (cards %s)" % [port, "on" if _cards else "off"] if err == OK else "Couldn't host: %s" % error_string(err)
		_start.visible = err == OK
	else:
		var err := _net.join(opts["join"], player_name)
		_status.text = "Connecting to %s..." % opts["join"] if err == OK else "Couldn't connect: %s" % error_string(err)

func _on_roster(list: Array) -> void:
	var lines: Array[String] = ["Players:"]
	for entry in list:
		lines.append("  %d. %s (%s)%s" % [entry["seat"] + 1, entry["name"], entry["color_name"], "" if entry["connected"] else " - disconnected"])
	_roster.text = "\n".join(lines)
	if _net.is_host():
		_start.disabled = list.size() < GameConfig.MIN_PLAYERS
		if _autostart > 0 and list.size() >= _autostart:
			_net.start_match(_cards)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
