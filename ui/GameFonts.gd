class_name GameFonts
extends RefCounted

## The game's lettering (assets/fonts/, all SIL Open Font License, licences alongside):
##   TITLE  Yatra One: Latin drawn with Devanagari's headline and rhythm, for titles,
##          names and pops ("Chamma! 4")
##   BODY   Laila (Regular / SemiBold): a warm Indian serif for rules, the log, buttons
##   CHALK  Kalam Bold: handwriting, for anything chalked on the mud
##   TELUGU Ramaraja: Telugu script (e.g. చెమ్మ, అష్ట)

const TITLE_PATH := "res://assets/fonts/YatraOne-Regular.ttf"
const BODY_PATH := "res://assets/fonts/Laila-Regular.ttf"
const BODY_BOLD_PATH := "res://assets/fonts/Laila-SemiBold.ttf"
const CHALK_PATH := "res://assets/fonts/Kalam-Bold.ttf"
const TELUGU_PATH := "res://assets/fonts/Ramaraja-Regular.ttf"

static func title() -> Font:
	return load(TITLE_PATH)

static func body() -> Font:
	return load(BODY_PATH)

static func body_bold() -> Font:
	return load(BODY_BOLD_PATH)

static func chalk() -> Font:
	return load(CHALK_PATH)

static func telugu() -> Font:
	return load(TELUGU_PATH)

## Makes the body font the default for every Control (and Label3D) without its own font.
## Called by the first screens (menu, match HUD, labs); safe to call more than once.
static func install() -> void:
	# The engine's default theme carries its own font, which wins over the fallback
	ThemeDB.get_default_theme().default_font = body()
	ThemeDB.fallback_font = body()

## A theme using the body font everywhere (set it on a UI root; children inherit it).
static func theme(font_size: int = 16) -> Theme:
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = font_size
	return t
