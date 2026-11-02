class_name ConnectingScreen
extends MenuScreen

## Waiting to get into a room. args: {"where", "note"}. Actions: "cancel_join".

var _cancel: Button

func _ready() -> void:
	add_child(MenuStyle.title("Connecting...", 34))
	add_child(MenuStyle.label(String(args.get("where", "")), 17, MenuStyle.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var note := String(args.get("note", ""))
	if note != "":
		add_child(MenuStyle.note(note))
	_cancel = MenuStyle.button("Cancel", 180)
	_cancel.pressed.connect(go_back)
	add_footer([_cancel])

func first_focus() -> Control:
	return _cancel

func go_back() -> void:
	action.emit(&"cancel_join", {})
