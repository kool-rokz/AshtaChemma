class_name GameConfig
extends RefCounted

## Fixed game constants and helpers. Per-match choices (players, cards) live in
## MatchSetup, handed to each match explicitly.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const PAWNS_PER_PLAYER := 4
const NAME_MAX_LENGTH := 16

## Shown in the menu. Bump when shipping a build.
const GAME_VERSION := "0.8.0"
## Bump whenever online messages or game rules change in a way older builds would
## misread: the host refuses players whose build speaks a different protocol.
const PROTOCOL_VERSION := 6

## How cards are drafted (a lobby setting, A/B testing 2026-11):
##   PRIVATE: each player secretly keeps hand_size cards from their own offer.
##   OPEN: one face-up pool (hand_size + 1 cards per player); players take one card at a
##   time in snake order, everyone seeing every pick; hands are hidden again in play,
##   so the game becomes remembering and predicting what the others hold.
const DRAFT_PRIVATE := "private"
const DRAFT_OPEN := "open"
const DRAFT_MODES := [DRAFT_PRIVATE, DRAFT_OPEN]
const DEFAULT_DRAFT := DRAFT_PRIVATE

## "Skill throws" (a lobby setting): the most a gently released, shaken shell keeps the
## face it showed in the hand. Off = every throw has the plain odds. A harder release
## keeps less (keep x (1 - power)), and quick tosses never keep anything.
const THROW_SKILL_KEEP := {"off": 0.0, "light": 0.15, "strong": 0.3}
const DEFAULT_THROW_SKILL := "light"
## A throw must have been shaken at least this much (ThrowGesture.shaken) to keep any.
const SKILL_MIN_SHAKE := 0.15

## Pawn colour choices, in default assignment order.
const COLORS: Dictionary = {
	"Red": Color(0.91, 0.30, 0.24),
	"Blue": Color(0.29, 0.51, 0.95),
	"Yellow": Color(0.98, 0.80, 0.18),
	"Green": Color(0.30, 0.78, 0.36),
}

## Kondapalli lacquer for each colour choice: the figure's main paint and its second
## colour (cloth, plinth, trim). Gold, black and ivory parts keep their own colours.
const LACQUER: Dictionary = {
	"Red": {"base": Color(0.80, 0.16, 0.09), "accent": Color(0.95, 0.70, 0.12)},
	"Blue": {"base": Color(0.13, 0.22, 0.62), "accent": Color(0.96, 0.55, 0.12)},
	"Yellow": {"base": Color(0.96, 0.74, 0.12), "accent": Color(0.58, 0.10, 0.16)},
	"Green": {"base": Color(0.16, 0.58, 0.22), "accent": Color(0.82, 0.12, 0.14)},
}

## Pawn figures (assets/pawns/<id>.glb), in default assignment order, with display names.
const FIGURES: Dictionary = {
	"elephant": "Elephant",
	"horse": "Horse",
	"parrot": "Parrot",
	"peacock": "Peacock",
	"doll": "Dancer",
	"bullock": "Bullock",
}

## Board sides a player can sit at; pawns enter on that side's safe square.
## 0 = bottom, 1 = right, 2 = top, 3 = left (counter-clockwise, matching movement).
const SEATS_BY_PLAYER_COUNT: Dictionary = {
	2: [0, 2],
	3: [0, 1, 2],
	4: [0, 1, 2, 3],
}

## Where friends can play in a browser (e.g. your itch.io page). Added to copied invites;
## leave "" to share just the room code.
const PLAY_URL := ""

static func default_players(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names := COLORS.keys()
	var figures := FIGURES.keys()
	for i in count:
		result.append({"name": "Player %d" % (i + 1), "color_name": names[i], "figure": figures[i]})
	return result

static func color_of(player: Dictionary) -> Color:
	return COLORS.get(player.get("color_name", "Red"), Color.WHITE)

static func lacquer_of(color_name: String) -> Dictionary:
	return LACQUER.get(color_name, LACQUER["Red"])

## A known figure id ("elephant" for anything unknown).
static func figure_or_default(figure: String) -> String:
	return figure if FIGURES.has(figure) else FIGURES.keys()[0]

static func seats_for(count: int) -> Array:
	return SEATS_BY_PLAYER_COUNT[clampi(count, MIN_PLAYERS, MAX_PLAYERS)]
