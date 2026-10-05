class_name CardData
extends Resource

## One card, built entirely in the Inspector: what it targets and what it does.
## Save it as a .tres in cards/data/ and it joins the deck (CardLibrary scans the folder).
##   targets: what the player picks, in order (effects refer to them by index)
##   effects: run in order when the card is played

@export var id: StringName
@export var title: String = "New card"
## Short: it's printed on a ~90px wide card. Keep it under ~80 characters.
@export_multiline var description: String = ""
@export var color: Color = Color(0.35, 0.38, 0.5)
@export var icon: Texture2D
## Relative chance of appearing in a draft offer (0 = never offered).
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0
@export var targets: Array[CardTarget] = []
@export var effects: Array[CardEffect] = []
