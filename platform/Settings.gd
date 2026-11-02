class_name Settings
extends RefCounted

## The player's settings, kept through Platform.storage() (one file, loaded once).
## Every screen reads and writes them here; nothing else touches the settings file.
## Values are small and written at once, so a crash or closed tab loses nothing.

const FILE_NAME := "settings.cfg"

## Sections and keys.
const PLAYER := "player"
const NAME := "name"
const FIGURE := "figure"
const LAST_ADDRESS := "last_address"
const SESSION := "session"
const SESSION_URL := "url"
const SESSION_TOKEN := "token"
const VIEW := "view"
const LIGHT := "light"
const QUALITY := "quality"
const UI_SCALE := "ui_scale"
const AUDIO := "audio"
const MUSIC_VOLUME := "music_volume"
const EFFECTS_VOLUME := "effects_volume"

## Graphics quality: HIGH (shadows, smoothing) or LOW (for phones and handhelds).
const QUALITY_HIGH := "high"
const QUALITY_LOW := "low"
const QUALITIES := [QUALITY_HIGH, QUALITY_LOW]
## UI size steps (1.0 = the 1280x720 layout as designed).
const UI_SCALES := [1.0, 1.15, 1.3, 1.5]

static var _file: ConfigFile

static func _loaded() -> ConfigFile:
	if _file == null:
		_file = ConfigFile.new()
		var text := Platform.storage().read_text(FILE_NAME)
		if text != "":
			_file.parse(text)
	return _file

static func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _loaded().get_value(section, key, default)

## Sets and saves one value.
static func set_value(section: String, key: String, value: Variant) -> void:
	_loaded().set_value(section, key, value)
	Platform.storage().write_text(FILE_NAME, _file.encode_to_text())

## Forget the cached copy (tests, or another window changed the file).
static func reload() -> void:
	_file = null

# --- typed helpers ---
static func light() -> String:
	return get_value(VIEW, LIGHT, BoardWorld.DUSK)

static func quality() -> String:
	var q: String = get_value(VIEW, QUALITY, Platform.default_quality())
	return q if q in QUALITIES else Platform.default_quality()

## Volumes, 0..1.
static func music_volume() -> float:
	return clampf(float(get_value(AUDIO, MUSIC_VOLUME, 0.6)), 0.0, 1.0)

static func effects_volume() -> float:
	return clampf(float(get_value(AUDIO, EFFECTS_VOLUME, 0.85)), 0.0, 1.0)

static func ui_scale() -> float:
	var s := float(get_value(VIEW, UI_SCALE, Platform.default_ui_scale()))
	return clampf(s, UI_SCALES[0], UI_SCALES[-1])
