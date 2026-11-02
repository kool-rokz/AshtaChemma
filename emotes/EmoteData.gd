class_name EmoteData
extends Resource

## One emote in the wheel, built in the Inspector. Save it as a .tres in emotes/data/ and
## it appears in the wheel (Emotes scans the folder). Cosmetic only.
##   gesture  what every figure of the sender acts out (PawnFigure.gesture: "taunt",
##            "laugh", "plead" or any animation)
##   voice    which of the sender's figure voices to say (a key of FigureData.voices)
##   phrase   optional words shown above them (Telugu), with `reading` under it

@export var id: StringName
@export var label: String = ""
@export var gesture: String = ""
@export var voice: String = ""
@export var phrase: String = ""
@export var reading: String = ""
## Position in the wheel (lower first).
@export var order: int = 0
