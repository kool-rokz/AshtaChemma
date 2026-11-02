class_name GameConfig
extends RefCounted

## Fixed game constants and helpers. Per-match choices (players, cards) live in
## MatchSetup, handed to each match explicitly.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const PAWNS_PER_PLAYER := 4
const NAME_MAX_LENGTH := 16

## Shown in the menu. Bump when shipping a build.
const GAME_VERSION := "0.9.0"
## Bump whenever online messages or game rules change in a way older builds would
## misread: the host refuses players whose build speaks a different protocol.
const PROTOCOL_VERSION := 7

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
	var names := TeamColors.ids()
	var figures := Figures.ids()
	for i in count:
		result.append({"name": "Player %d" % (i + 1), "color_name": names[i % names.size()], "figure": figures[i % figures.size()]})
	return result

## A player's colour for text, badges and chalk (TeamColorData.ui).
static func color_of(player: Dictionary) -> Color:
	return TeamColors.of(player.get("color_name", "")).ui

static func seats_for(count: int) -> Array:
	return SEATS_BY_PLAYER_COUNT[clampi(count, MIN_PLAYERS, MAX_PLAYERS)]
