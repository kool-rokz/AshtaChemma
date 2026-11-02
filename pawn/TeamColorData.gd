class_name TeamColorData
extends Resource

## One colour a player can choose, built in the Inspector. Save it as a .tres in
## pawn/colors/ and it joins the lobby (TeamColors scans the folder). The id is what the
## lobby saves and the network sends ("Red").
##   ui      the colour for text, badges and chalk marks
##   base    the figure's main lacquer (its "Base" material slot)
##   accent  its second colour: cloth, plinth, trim ("Accent" slot); gold, black and
##           ivory parts keep their own colours

@export var id: StringName
@export var display_name: String = ""
@export var ui: Color = Color.WHITE
@export var base: Color = Color.WHITE
@export var accent: Color = Color.WHITE
## Default assignment order (lower first); also the order of the lobby's swatches.
@export var order: int = 0
