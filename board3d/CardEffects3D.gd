class_name CardEffects3D
extends Node

## Shows on the 3D board what each played card did, on every screen, so a card's effect
## is evident where it happens. It only decorates: the real changes (moves, a pawn sent
## home, a swap, shields, safe squares) are the rules' own and reach the board view
## through GameManager and the card UI's markers. Here: the flourish for each card,
## and the played card landing on the discard pile once it has been read.
##   Sprint      a burst at the pawn as it sets off
##   Tailwind    wind past each of the player's pawns, and "+1" over them
##   Aegis       a golden burst as the shell dome rises (the dome stays while it lasts)
##   Master Key  a ring pulse and burst at home in the player's colour
##   Loaded Shells  the shells glow gold, with "4!" over them
##   Lucky Charm the shells shimmer
##   Banish      a red burst at the pawn before it tumbles home
##   Sanctuary   a burst over the square as its new cross is chalked
##   Switcheroo  (the swap arcs themselves come from the board view)
##   Stall       the skipped player's pawns are sad
## Disabled when headless.

@export var card_manager: CardManager
@export var view: BoardView3D
@export var shells: ShellStage

var _enabled := false

func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless" and card_manager != null and view != null
	if _enabled:
		card_manager.card_played.connect(_on_card_played)

func _on_card_played(player: int, card: CardData, targets: Array) -> void:
	var game := card_manager.game
	var color: Color = GameConfig.lacquer_of(game.players[player].get("color_name", "Red"))["base"]
	match card.id:
		&"sprint":
			_burst_at_pawn(targets, Color(0.5, 1.0, 0.6))
		&"tailwind":
			for fig in view.team_figures(player):
				var at: Vector3 = (fig as Node3D).position
				CardFx.wind(view, at, (-at).normalized() if at.length() > 0.1 else Vector3.FORWARD)
				CardFx.float_text(view, at + Vector3.UP * 0.6, "+1", Color(0.75, 1.0, 0.9))
		&"aegis":
			_burst_at_pawn(targets, CardFx.GOLD)
		&"master_key":
			var home := BoardWorld.square_position(game.board.board_data.home_index)
			CardFx.ring_pulse(view, home, color, 1.6)
			CardFx.burst(view, home + Vector3.UP * 0.2, color, 50)
		&"loaded_shells":
			_glow_shells(Color(1.0, 0.8, 0.3), "4!")
		&"lucky_charm":
			var centre := _glow_shells(Color(0.7, 1.0, 0.6), "")
			CardFx.shimmer(view, centre, Color(0.8, 1.0, 0.6))
		&"banish":
			_burst_at_pawn(targets, Color(1.0, 0.35, 0.25))
		&"sanctuary":
			for target in targets:
				if target is int:
					CardFx.burst(view, BoardWorld.square_position(target) + Vector3.UP * 0.1, Color(0.4, 0.95, 1.0), 30)
		&"stall":
			for target in targets:
				if target is int and target >= 0 and target < game.players.size():
					for fig in view.team_figures(target):
						(fig as PawnFigure).play(PawnFigure.SAD)
	# The card lands on the pile once it has been shown (CardHUD flies it there)
	await get_tree().create_timer(GanjifaHand.PLAY_TIME).timeout
	view.add_discard(card)

func _burst_at_pawn(targets: Array, color: Color) -> void:
	for target in targets:
		if target is Pawn and view.figure_of(target):
			CardFx.burst(view, view.figure_of(target).position + Vector3.UP * 0.25, color, 30)

## Lights the shells with `color` (and floats `text` over them). Returns their centre.
func _glow_shells(color: Color, text: String) -> Vector3:
	var centre := Vector3.ZERO
	if shells == null:
		return centre
	var nodes := shells.shell_nodes()
	for shell in nodes:
		centre += shell.position / maxf(nodes.size(), 1.0)
		CardFx.glow_over(shell, color, 2.0)
	if text != "":
		CardFx.float_text(view, centre + Vector3.UP * 0.5, text, color)
	return centre
