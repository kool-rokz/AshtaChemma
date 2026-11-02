class_name JoinScreen
extends MenuScreen

## Join a room: type or paste the room code (an invite message or link works too).
## Actions: "join" {"address"}. The shell fills in pasted text (paste_text).

var _address_edit: LineEdit

func _ready() -> void:
	add_child(MenuStyle.title("Join a game", 36))
	add_child(MenuStyle.note("Type or paste the room code the host gave you (or an address like 192.168.1.23:9080 on the same network)."))
	_address_edit = MenuStyle.line_edit(Settings.get_value(Settings.PLAYER, Settings.LAST_ADDRESS, ""), "room code, e.g. brave-lemon-kite-maple")
	_address_edit.name = "JoinAddress"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.text_submitted.connect(func(text: String): action.emit(&"join", {"address": text}))
	var paste := MenuStyle.button("Paste", 110)
	paste.name = "PasteAddress"
	paste.focus_mode = Control.FOCUS_NONE # keep the caret in the box
	paste.pressed.connect(func(): action.emit(&"paste", {}))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_address_edit)
	row.add_child(paste)
	add_child(row)
	var back := MenuStyle.button("Back", 140)
	back.pressed.connect(go_back)
	var go := MenuStyle.button("Join")
	go.name = "JoinConfirm"
	go.pressed.connect(func(): action.emit(&"join", {"address": _address_edit.text}))
	add_child(MenuStyle.button_row([back, go]))
	add_child(MenuStyle.error(String(args.get("error", ""))))
	stage.show_lineup(HomeScreen.saved_figure())

func first_focus() -> Control:
	return _address_edit

## Puts pasted text (or an invite reduced to its room code) into the address box.
func paste_text(text: String) -> void:
	if text.strip_edges() != "":
		_address_edit.text = net.transport.find_address(text)
		_address_edit.caret_column = _address_edit.text.length()
