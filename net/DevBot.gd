class_name DevBot
extends Node

## Developer flag --bot: this instance plays its own seat automatically (random legal
## moves, auto draft), so online play can be tested from a single window.
## Lives under the scene-tree root so it survives the lobby -> match scene change.

const THINK_TIME := 0.6

var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var scene := get_tree().current_scene
	var ctrl := scene.get_node_or_null("MatchController") as MatchController if scene else null
	if ctrl == null or ctrl.game == null or ctrl.game.is_game_finished() or not ctrl.is_local_turn():
		return
	var gm := ctrl.game
	if gm.is_settled() or (ctrl.card_manager and ctrl.card_manager.is_targeting()):
		_cooldown = THINK_TIME
		RandomBot.step(gm, ctrl, _rng)
