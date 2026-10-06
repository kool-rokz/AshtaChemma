class_name MatchSetup
extends RefCounted

## Everything one match needs to start, decided before MainGame loads (lobby, tests).
## Handed to the scene explicitly (GameManager.setup) instead of living in globals,
## so two matches in one process (tests) can never share or leak settings.

const GAME_SCENE_PATH := "res://MainGame.tscn"

## One {"name", "color_name"} entry per player, in seat order.
var players: Array[Dictionary] = []
## Experimental card layer (cards/CardManager). false = the plain game.
var cards_enabled: bool = false
## Rejoin: a MatchController snapshot to continue from instead of starting a new match.
var resume: Dictionary = {}

static func make(player_list: Array, cards: bool = false) -> MatchSetup:
	var setup := MatchSetup.new()
	for p in player_list:
		setup.players.append({"name": String(p["name"]), "color_name": String(p["color_name"])})
	setup.cards_enabled = cards
	return setup

## Default for running MainGame.tscn on its own (F6): two local players, no cards.
static func default_setup() -> MatchSetup:
	return make(GameConfig.default_players(GameConfig.MIN_PLAYERS))

## Loads MainGame with this setup in place of the current scene.
func launch(tree: SceneTree) -> void:
	var main: Node = load(GAME_SCENE_PATH).instantiate()
	apply_to(main)
	var old := tree.current_scene
	tree.root.add_child(main)
	tree.current_scene = main
	if old:
		old.queue_free()

## Hands this setup to an instantiated (not yet added) MainGame.
func apply_to(main: Node) -> void:
	(main.get_node("GameManager") as GameManager).setup = self
