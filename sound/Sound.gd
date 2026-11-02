class_name Sound
extends Node

## The game's sound: one node under the root (like NetSession), so music carries on from
## the menu into the match. Every view plays its own cosmetic sounds through the static
## calls here (Sound.play(&"pawn_step")); nothing here knows about the game.
##   - effects: res://assets/audio/sfx/<id>.ogg, or numbered variants <id>_1.ogg, <id>_2.ogg...
##     (one picked at random, with a slight change of pitch, so repeats don't sound copied)
##   - music: res://assets/audio/music/<id>.ogg, looped, faded in and crossfaded
##   - ambience: an effects-level loop (crickets at dusk, birds at dawn)
## Two buses, Music and Effects, set from Settings. They're declared in
## res://default_bus_layout.tres, loaded at startup: the web build only wires up buses
## that exist when the game starts (buses added later stay silent there). _add_bus is
## only a fallback. Silent and
## absent when headless (tests). The audio files are made by the AshtaChemmaArt audio
## pipeline (its build.sh --install), and can be swapped for a sound designer's files
## with the same names.

const NODE_NAME := "Sound"
const SFX_PATH := "res://assets/audio/sfx/%s.ogg"
const SFX_VARIANT_PATH := "res://assets/audio/sfx/%s_%d.ogg"
const MUSIC_PATH := "res://assets/audio/music/%s.ogg"
const MUSIC_BUS := &"Music"
const EFFECTS_BUS := &"Effects"
const VOICES := 24
## The same sound at once, at most (a team cheering together is a chorus, not a roar).
const SAME_SOUND_LIMIT := 3
const PITCH_JITTER := 0.04
const SILENT_DB := -60.0

static var _instance: Sound

var _players: Array[AudioStreamPlayer] = []
var _next := 0
## id -> Array of streams (its variants); an empty array = no such sound.
var _streams: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_id: StringName = &""
var _ambience: AudioStreamPlayer
var _ambience_id: StringName = &""

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
## Plays an effect (a random variant). volume_db: relative loudness; delay: seconds.
static func play(id: StringName, volume_db: float = 0.0, delay: float = 0.0) -> void:
	var sound := _ready_instance()
	if sound == null:
		# Just created (it joins the tree at the end of this frame): play it then
		if _instance and is_instance_valid(_instance) and not _instance.is_inside_tree():
			Sound.play.call_deferred(id, volume_db, delay)
		return
	if delay > 0.0:
		sound.get_tree().create_timer(delay).timeout.connect(sound._play.bind(id, volume_db))
	else:
		sound._play(id, volume_db)

## Is there a sound with this id (any variant)?
static func has(id: StringName) -> bool:
	var sound := _ready_instance()
	return sound != null and not sound._variants(id).is_empty()

func _play(id: StringName, volume_db: float) -> void:
	var variants := _variants(id)
	if variants.is_empty():
		return
	var playing_same := 0
	for player in _players:
		if player.playing and player.get_meta("id", &"") == id:
			playing_same += 1
	if playing_same >= SAME_SOUND_LIMIT:
		return
	var player := _free_player()
	player.stream = variants[randi() % variants.size()]
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	player.set_meta("id", id)
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

func _variants(id: StringName) -> Array:
	if _streams.has(id):
		return _streams[id]
	var found: Array = []
	if ResourceLoader.exists(SFX_PATH % id):
		found.append(load(SFX_PATH % id))
	else:
		var n := 1
		while ResourceLoader.exists(SFX_VARIANT_PATH % [id, n]):
			found.append(load(SFX_VARIANT_PATH % [id, n]))
			n += 1
	_streams[id] = found
	return found

# --- music and ambience ---
## Starts a music track (looped), fading in; crossfades from the current one. The same
## track already playing carries on.
static func music(id: StringName, fade: float = 4.0) -> void:
	var sound := _ready_instance()
	if sound == null or sound._music_id == id or not ResourceLoader.exists(MUSIC_PATH % id):
		return
	sound._music_id = id
	var stream: AudioStream = load(MUSIC_PATH % id)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old := sound._music[0]
	var new := sound._music[1]
	sound._music.reverse()
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	sound._fade(new, 0.0, fade)
	if old.playing:
		sound._fade(old, SILENT_DB, fade, true)

static func stop_music(fade: float = 2.0) -> void:
	var sound := _ready_instance()
	if sound == null:
		return
	sound._music_id = &""
	for player in sound._music:
		if player.playing:
			sound._fade(player, SILENT_DB, fade, true)

## A background loop at effects level ("" stops it).
static func ambience(id: StringName, fade: float = 3.0) -> void:
	var sound := _ready_instance()
	if sound == null or sound._ambience_id == id:
		return
	sound._ambience_id = id
	var player := sound._ambience
	if id == &"" or not ResourceLoader.exists(SFX_PATH % id):
		if player.playing:
			sound._fade(player, SILENT_DB, fade, true)
		return
	var stream: AudioStream = load(SFX_PATH % id)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	sound._fade(player, 0.0, fade)

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
