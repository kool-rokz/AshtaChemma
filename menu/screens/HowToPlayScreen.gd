class_name HowToPlayScreen
extends MenuScreen

## The rules as palm-leaf pages, read from CONTENT_PATH (text only, so it can be
## rewritten or translated without touching code). Each page may name a "lesson" the
## courtyard chalks on the board (MenuStage.show_lesson). Back / Next step the pages.

const CONTENT_PATH := "res://menu/content/how_to_play.json"

var _pages: Array = []
var _page := 0
var _heading: Label
var _body: RichTextLabel
var _counter: Label
var _prev: Button
var _next: Button

func _ready() -> void:
	var content := load_content(CONTENT_PATH)
	_pages = content.get("pages", [])
	add_child(MenuStyle.title(String(content.get("title", "How to play")), 36))
	_heading = MenuStyle.label("", 24, MenuStyle.INK_RED)
	_heading.add_theme_font_override("font", GameFonts.title())
	add_child(_heading)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_font_size_override("bold_font_size", 18)
	_body.custom_minimum_size = Vector2(320, 0)
	add_child(_body)
	_counter = MenuStyle.label("", 15, MenuStyle.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_counter)
	_prev = MenuStyle.button("◀ Back")
	_prev.pressed.connect(_step.bind(-1))
	_next = MenuStyle.button("Next ▶")
	_next.name = "NextPage"
	_next.pressed.connect(_step.bind(1))
	add_child(MenuStyle.button_row([_prev, _next]))
	_show_page()

func first_focus() -> Control:
	return _next

func _exit_tree() -> void:
	stage.show_lesson("")

## Reads a JSON content file ({} if missing or broken).
static func load_content(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	return parsed if parsed is Dictionary else {}

func _step(step: int) -> void:
	if _page + step < 0:
		go_back()
		return
	if _page + step >= _pages.size():
		go_back() # past the last page: done
		return
	_page += step
	_show_page()

func _show_page() -> void:
	if _pages.is_empty():
		_heading.text = "No pages found."
		return
	var page: Dictionary = _pages[_page]
	_heading.text = String(page.get("title", ""))
	_body.text = String(page.get("body", ""))
	_counter.text = "%d / %d" % [_page + 1, _pages.size()]
	_prev.text = "◀ Back" if _page > 0 else "◀ Menu"
	_next.text = "Next ▶" if _page < _pages.size() - 1 else "Done"
	stage.show_lesson(String(page.get("lesson", "")))
