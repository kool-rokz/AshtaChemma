class_name FigureData
extends Resource

## One pawn figure players can pick, built in the Inspector. Save it as a .tres in
## pawn/figures/ and it joins the game (Figures scans the folder).
##   model   the Kondapalli toy (assets/pawns/<id>.glb, from the AshtaChemmaArt pipeline);
##           needs the animations idle, attack, celebrate, sad, relief, taunt, laugh, plead
##   voices  animation (or voice line: relief, taunt...) -> its sound; tools/SyncAudio.gd
##           fills it from assets/audio/voices/<id>/<line>.ogg

@export var id: StringName
@export var display_name: String = ""
@export var model: PackedScene
## Default assignment order (lower first); also the order in the menu's lineup.
@export var order: int = 0
@export var voices: Dictionary[StringName, AudioStream] = {}
