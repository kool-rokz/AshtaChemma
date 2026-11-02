class_name SoundCue
extends Resource

## One sound effect the game asks for by id (Sound.play(&"pawn_step")): its recordings
## and how to play them. Saved as sound/cues/<id>.tres (Sound scans the folder).
## A sound designer swaps a cue's streams or levels here without touching code.
## tools/SyncAudio.gd makes a cue for each new file in assets/audio/sfx (numbered files
## <id>_1.ogg, <id>_2.ogg... become one cue's variants).

@export var id: StringName
## One is picked at random each time, so repeats don't sound copied.
@export var streams: Array[AudioStream] = []
## Added to the caller's volume.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0
## Each play is pitched up or down at random by up to this much (0.04 = 4%).
@export_range(0.0, 0.3, 0.01) var pitch_jitter: float = 0.04
## The most copies of this cue playing at once (a team cheering together is a chorus,
## not a roar).
@export_range(1, 8) var max_at_once: int = 3

func pick() -> AudioStream:
	return streams[randi() % streams.size()] if not streams.is_empty() else null
