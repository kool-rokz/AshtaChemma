class_name MusicTrack
extends Resource

## A music track (Sound.music(&"courtyard_dusk")) and its layers. Saved as
## sound/music/<id>.tres (Sound scans the folder). Streams loop through their import
## settings (Loop on), not code.
##   layers  layer name (Sound.MUSIC_LAYERS: race, danger) -> a stream the track's
##           length, started with it and kept silent until Sound.music_layer() fades it in

@export var id: StringName
@export var stream: AudioStream
@export var layers: Dictionary[StringName, AudioStream] = {}
