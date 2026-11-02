class_name Tension
extends Node

## How tense the match is right now, worked out from the game after every change
## (a view: it reads GameManager, never changes it):
##   danger  {Pawn: 0..1}  the chance an opponent's next throw captures that pawn
##   race    0..1          how close anyone is to bringing a pawn home (pawns that can
##                         still turn inward), plus a push when someone has 3 home
## The board view makes endangered figures nervous from `danger`; this node sets the
## music's layers itself (Sound.music_layer): "race" (a busier tabla) and "danger" (a
## dark drone under everything) fade in and out with the match.

signal changed(danger: Dictionary, race: float)

## Chance of each throw value with four fair cowries (Binomial(4, 1/2), 0 up counts 8).
const ODDS := {1: 0.25, 2: 0.375, 3: 0.25, 4: 0.0625, 8: 0.0625}
## A pawn this many steps from home (or fewer) makes the race tense.
const RACE_STEPS := 6
const RACE_LAYER := &"race"
const DANGER_LAYER := &"danger"

var danger: Dictionary = {}
var race := 0.0
var _game: GameManager
var _queued := false

func watch(game: GameManager) -> void:
	_game = game
	for sig in [game.pawn_moved, game.pawn_captured, game.pawn_sent_home, game.pawns_swapped,
			game.turn_changed, game.inner_ring_unlocked, game.pawn_reached_home]:
		sig.connect(func(_a = null, _b = null, _c = null, _d = null): _refresh_soon())
	game.snapshot_loaded.connect(_refresh_soon)
	game.setup_done.connect(_refresh_soon)
	game.game_over.connect(func(_w): _calm())
	_refresh_soon()

func _refresh_soon() -> void:
	if not _queued:
		_queued = true
		_refresh.call_deferred()

func _refresh() -> void:
	_queued = false
	if _game == null or _game.players.is_empty() or _game.is_game_finished():
		return
	danger.clear()
	var threats := _game.get_threats()
	var worst := 0.0
	for pawn in threats:
		var chance := 0.0
		for value in threats[pawn]:
			chance += ODDS.get(value, 0.0)
		danger[pawn] = clampf(chance, 0.0, 1.0)
		worst = maxf(worst, danger[pawn])
	race = 0.0
	for pawn in _game.get_all_pawns():
		if not _game.is_unlocked(pawn.team_id):
			continue # still circling the outer ring: not near home yet
		var path := _game.board.board_data.get_seat_path(_game.player_seats[pawn.team_id])
		var left := path.size() - 1 - path.find(pawn.current_tile_index)
		if left > 0:
			race = maxf(race, 1.0 - float(left - 1) / RACE_STEPS)
	for player in _game.players.size():
		if _game.count_pawns_home(player) >= GameConfig.PAWNS_PER_PLAYER - 1:
			race = maxf(race, 0.8)
	race = clampf(race, 0.0, 1.0)
	Sound.music_layer(RACE_LAYER, race)
	Sound.music_layer(DANGER_LAYER, clampf(worst * 1.8, 0.0, 1.0))
	changed.emit(danger, race)

func _calm() -> void:
	danger.clear()
	race = 0.0
	Sound.music_layer(RACE_LAYER, 0.0)
	Sound.music_layer(DANGER_LAYER, 0.0)
	changed.emit(danger, race)

func _exit_tree() -> void:
	Sound.music_layer(RACE_LAYER, 0.0, 1.0)
	Sound.music_layer(DANGER_LAYER, 0.0, 1.0)
