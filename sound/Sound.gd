class_name Sound
extends Node

## The game's sound: one node under the root (like NetSession), so music carries on from
## the menu into the match. Every view plays its own cosmetic sounds through the static
## calls here (Sound.play(&"pawn_step")); nothing here knows about the game.
## What plays is data, not paths in code:
##   - effects: SoundCue resources in sound/cues/ (by id; their variants, level, pitch
##     jitter and how many may play at once). play_cue() / play_stream() play a cue or a
##     stream a resource points at (a villager's SoundCue, a figure's voice).
##   - music: MusicTrack resources in sound/music/ (by id), faded in and crossfaded; a
##     track's layers (MUSIC_LAYERS: "race", "danger") start with it, silent until
##     music_layer() fades them in
##   - ambience: a SoundCue played as an effects-level loop (crickets at dusk, birds at
##     dawn); duck_ambience() hushes it for a moment
## Music and ambience loop through their import settings (Loop on), not code.
## tools/SyncAudio.gd makes the cue and track files for new audio files.
## Two buses, Music and Effects, set from Settings. They're declared in
## res://default_bus_layout.tres, loaded at startup: the web build only wires up buses
## that exist when the game starts (buses added later stay silent there). _add_bus is
## only a fallback. Silent and
## absent when headless (tests). The audio files are made by the AshtaChemmaArt audio
## pipeline (its build.sh --install); a sound designer can replace them, or point the
## cue and track resources at new ones.

const NODE_NAME := "Sound"
const CUE_FOLDER := "res://sound/cues"
const MUSIC_FOLDER := "res://sound/music"
const MUSIC_BUS := &"Music"
const EFFECTS_BUS := &"Effects"
const VOICES := 24
## A stream played without a cue (a figure's voice): the same one at once, at most, and
## its pitch jitter.
const SAME_SOUND_LIMIT := 3
const PITCH_JITTER := 0.04
const SILENT_DB := -60.0
## Layers a music track may have, played in step with it (see music_layer()).
const MUSIC_LAYERS := [&"race", &"danger"]

static var _instance: Sound

var _players: Array[AudioStreamPlayer] = []
var _next := 0
## id -> SoundCue / MusicTrack, loaded once.
var _cues: Dictionary = {}
var _tracks: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_id: StringName = &""
var _ambience: AudioStreamPlayer
var _ambience_id: StringName = &""
## Layer name -> its player (for the current track).
var _layers: Dictionary = {}
var _ambience_level_db := 0.0

static func ensure(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = Sound.new()
		_instance.name = NODE_NAME
		_instance.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(_instance)

static func _ready_instance() -> Sound:
	return _instance if _instance and is_instance_valid(_instance) and _instance.is_inside_tree() else null

func _ready() -> void:
	for cue in ResourceFolder.load_all(CUE_FOLDER, func(r): return r is SoundCue, "Sound"):
		_cues[(cue as SoundCue).id] = cue
	for track in ResourceFolder.load_all(MUSIC_FOLDER, func(r): return r is MusicTrack, "Sound"):
		_tracks[(track as MusicTrack).id] = track
	_add_bus(MUSIC_BUS)
	_add_bus(EFFECTS_BUS)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = EFFECTS_BUS
		add_child(player)
		_players.append(player)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		add_child(player)
		_music.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = EFFECTS_BUS
	add_child(_ambience)
	apply_volumes()

static func _add_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, &"Master")

## Sets the buses from Settings (call after changing a volume).
static func apply_volumes() -> void:
	for pair in [[MUSIC_BUS, Settings.music_volume()], [EFFECTS_BUS, Settings.effects_volume()]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index >= 0:
			var linear: float = pair[1]
			AudioServer.set_bus_mute(index, linear <= 0.001)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))

# --- effects ---
## Plays an effect by its cue id. volume_db: relative loudness; delay: seconds.
static func play(id: StringName, volume_db: float = 0.0, delay: float = 0.0) -> void:
	var sound := _ready_instance()
	if sound:
		play_cue(sound._cues.get(id), volume_db, delay)
	elif _instance and is_instance_valid(_instance) and not _instance.is_inside_tree():
		# Just created (it joins the tree at the end of this frame): play it then
		Sound.play.call_deferred(id, volume_db, delay)

## Plays a cue a resource points at (null does nothing).
static func play_cue(cue: SoundCue, volume_db: float = 0.0, delay: float = 0.0) -> void:
	if cue and not cue.streams.is_empty():
		_start(cue.pick(), cue.id, volume_db + cue.volume_db, cue.pitch_jitter, cue.max_at_once, delay)

## Plays one stream a resource points at, e.g. a figure's voice (null does nothing).
static func play_stream(stream: AudioStream, volume_db: float = 0.0, delay: float = 0.0) -> void:
	if stream:
		_start(stream, StringName(stream.resource_path), volume_db, PITCH_JITTER, SAME_SOUND_LIMIT, delay)

## Is there a cue with this id?
static func has(id: StringName) -> bool:
	var sound := _ready_instance()
	return sound != null and sound._cues.has(id)

static func _start(stream: AudioStream, key: StringName, volume_db: float, jitter: float, limit: int, delay: float) -> void:
	var sound := _ready_instance()
	if sound == null:
		return
	if delay > 0.0:
		sound.get_tree().create_timer(delay).timeout.connect(sound._play.bind(stream, key, volume_db, jitter, limit))
	else:
		sound._play(stream, key, volume_db, jitter, limit)

func _play(stream: AudioStream, key: StringName, volume_db: float, jitter: float, limit: int) -> void:
	var playing_same := 0
	for player in _players:
		if player.playing and player.get_meta("key", &"") == key:
			playing_same += 1
	if playing_same >= limit:
		return
	var player := _free_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	player.set_meta("key", key)
	player.play()

## A free player, else the one that started longest ago.
func _free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var player := _players[(_next + i) % _players.size()]
		if not player.playing:
			_next = (_next + i + 1) % _players.size()
			return player
	var oldest := _players[_next]
	_next = (_next + 1) % _players.size()
	return oldest

# --- music and ambience ---
## Starts a music track (looped), fading in; crossfades from the current one. The same
## track already playing carries on.
static func music(id: StringName, fade: float = 4.0) -> void:
	var sound := _ready_instance()
	if sound == null or sound._music_id == id or not sound._tracks.has(id):
		return
	sound._music_id = id
	var track: MusicTrack = sound._tracks[id]
	var old := sound._music[0]
	var new := sound._music[1]
	sound._music.reverse()
	new.stream = track.stream
	new.volume_db = SILENT_DB
	# The track's layers start in the same frame, silent, so they stay in step with it
	for layer in sound._layers.values():
		sound._fade(layer, SILENT_DB, fade, true)
	sound._layers.clear()
	for layer_name in MUSIC_LAYERS:
		if not track.layers.has(layer_name):
			continue
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.stream = track.layers[layer_name]
		player.volume_db = SILENT_DB
		sound.add_child(player)
		sound._layers[layer_name] = player
	new.play()
	for layer in sound._layers.values():
		layer.play()
	sound._fade(new, 0.0, fade)
	if old.playing:
		sound._fade(old, SILENT_DB, fade, true)

## Fades a layer of the current track to `level` (0..1; 0 = silent).
static func music_layer(layer: StringName, level: float, fade: float = 2.5) -> void:
	var sound := _ready_instance()
	if sound == null or not sound._layers.has(layer):
		return
	var player: AudioStreamPlayer = sound._layers[layer]
	sound._fade(player, linear_to_db(level) if level > 0.01 else SILENT_DB, fade)

## Hushes the ambience (the crickets go quiet), then lets it come back.
static func duck_ambience(seconds: float = 3.0, depth_db: float = -18.0) -> void:
	var sound := _ready_instance()
	if sound == null or not sound._ambience.playing:
		return
	var player := sound._ambience
	if player.has_meta("fade"):
		var old: Tween = player.get_meta("fade")
		if old and old.is_valid():
			old.kill()
	var tween := sound.create_tween()
	tween.tween_property(player, "volume_db", sound._ambience_level_db + depth_db, 0.3)
	tween.tween_interval(seconds)
	tween.tween_property(player, "volume_db", sound._ambience_level_db, 1.5).set_trans(Tween.TRANS_SINE)
	player.set_meta("fade", tween)

static func stop_music(fade: float = 2.0) -> void:
	var sound := _ready_instance()
	if sound == null:
		return
	sound._music_id = &""
	for player in sound._music:
		if player.playing:
			sound._fade(player, SILENT_DB, fade, true)

## A background loop at effects level, by cue id ("" stops it).
static func ambience(id: StringName, fade: float = 3.0) -> void:
	var sound := _ready_instance()
	if sound == null or sound._ambience_id == id:
		return
	sound._ambience_id = id
	var player := sound._ambience
	var cue: SoundCue = sound._cues.get(id)
	if cue == null or cue.streams.is_empty():
		if player.playing:
			sound._fade(player, SILENT_DB, fade, true)
		return
	player.stream = cue.pick()
	sound._ambience_level_db = cue.volume_db
	player.volume_db = SILENT_DB
	player.play()
	sound._fade(player, sound._ambience_level_db, fade)

func _fade(player: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool = false) -> void:
	if player.has_meta("fade"):
		var old: Tween = player.get_meta("fade")
		if old and old.is_valid():
			old.kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, seconds).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tween.tween_callback(player.stop)
	player.set_meta("fade", tween)
