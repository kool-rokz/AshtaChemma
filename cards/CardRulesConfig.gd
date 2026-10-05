class_name CardRulesConfig
extends Resource

## Balance knobs for the card layer, in one place (cards/CardRules.tres).

@export_range(1, 10) var hand_size: int = 5
## Cards each player is offered privately at the draft (they keep hand_size).
@export_range(1, 30) var offer_size: int = 10
@export_range(1, 5) var cards_per_turn: int = 1
## 0 = different draft offers every game; any other value repeats them.
@export var rng_seed: int = 0
@export_dir var card_folder: String = "res://cards/data"
