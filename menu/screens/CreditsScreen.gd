class_name CreditsScreen
extends MenuScreen

## Who made what, from CONTENT_PATH, followed by the Godot Engine's licence and its
## third-party notices (which a shipped game must include), read from the engine itself.

const CONTENT_PATH := "res://menu/content/credits.json"

var _back: Button

func _ready() -> void:
	var content := HowToPlayScreen.load_content(CONTENT_PATH)
	add_child(MenuStyle.title(String(content.get("title", "Credits")), 36))
	var text := ""
	for section in content.get("sections", []):
		text += "[b]%s[/b]\n%s\n\n" % [String(section.get("title", "")), String(section.get("body", ""))]
	if content.get("engine_licence", true):
		text += "[b]Godot Engine[/b]\n%s\n\n" % Engine.get_license_text().strip_edges()
		text += "[b]Godot's third-party parts[/b]\n"
		for part in Engine.get_copyright_info():
			var notes: Array = []
			for entry in part.get("parts", []):
				notes.append(String(entry.get("license", "")))
			text += "%s (%s)\n" % [String(part.get("name", "")), ", ".join(notes)]
	var body := RichTextLabel.new()
	body.name = "CreditsText"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_font_size_override("bold_font_size", 17)
	body.custom_minimum_size = Vector2(320, 0)
	body.text = text
	add_child(body)
	_back = MenuStyle.button("Back", 180)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(go_back)
	add_child(_back)

func first_focus() -> Control:
	return _back
