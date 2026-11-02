class_name VillagerData
extends Resource

## One onlooker in the courtyard, built in the Inspector. Save it as a .tres in
## courtyard/data/ and they join the courtyard (Courtyard scans the folder).
##   model      the toy (assets/villagers/<id>.glb, from the AshtaChemmaArt pipeline);
##              needs an "idle" animation, plus whichever animations reactions name
##   reactions  moment (Courtyard.MOMENTS) -> animation; moments left out are ignored
##   sounds     animation -> the SoundCue played with it

@export var id: StringName
@export var display_name: String = ""
@export var model: PackedScene
## Index into Courtyard.SPOTS.
@export var spot: int = 0
@export var scale: float = 2.0
@export var reactions: Dictionary[StringName, String] = {}
@export var sounds: Dictionary[StringName, SoundCue] = {}
