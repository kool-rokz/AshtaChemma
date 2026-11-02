class_name SettingsScreen
extends MenuScreen

## This player's own settings (never sent to anyone): light, graphics, UI size, music
## and effects volume. Each change is saved and applied at once.

var _first: Control

func _ready() -> void:
	add_child(MenuStyle.title("Settings", 38))
	_first = _choice("Light", ["Dusk", "Dawn"], [BoardWorld.DUSK, BoardWorld.DAWN], Settings.light(), Settings.LIGHT,
		func(mode): stage.set_light(mode))
	_choice("Graphics", ["High (shadows)", "Low (faster)"], Settings.QUALITIES, Settings.quality(), Settings.QUALITY)
	var sizes: Array = Settings.UI_SCALES.map(func(s: float): return "%d%%" % roundi(s * 100))
	_choice("UI size", sizes, Settings.UI_SCALES, Settings.ui_scale(), Settings.UI_SCALE,
		func(_v): Display.apply(get_tree()))
	add_child(MenuStyle.row("Music", MenuStyle.volume_slider(Settings.MUSIC_VOLUME, &"ui_click")))
	add_child(MenuStyle.row("Effects", MenuStyle.volume_slider(Settings.EFFECTS_VOLUME, &"turn_yours")))
	add_child(MenuStyle.note("Graphics: Low turns off shadows and edge smoothing (for phones and handhelds). It applies from the next match."))
	var back := MenuStyle.button("Back", 180)
	back.pressed.connect(go_back)
	add_footer([back])

func first_focus() -> Control:
	return _first

## A choice saved to Settings.VIEW/key; `after` gets the new value.
func _choice(title: String, labels: Array, values: Array, current: Variant, key: String, after := Callable()) -> OptionButton:
	var picker := MenuStyle.options(labels, values.find(current))
	picker.name = title.replace(" ", "")
	picker.item_selected.connect(func(i: int):
		Settings.set_value(Settings.VIEW, key, values[i])
		if after.is_valid():
			after.call(values[i]))
	add_child(MenuStyle.row(title, picker))
	return picker
