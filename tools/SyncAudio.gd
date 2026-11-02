extends SceneTree

## Turns the audio files in assets/audio/ into the game's sound resources, so new sounds
## from the audio pipeline (AshtaChemmaArt/audio/build.sh --install) join the game with
## no code or hand edits. Run through tools/sync_audio.sh (it imports first and after).
##   sfx/<id>.ogg, or <id>_1.ogg, <id>_2.ogg...  -> SoundCue sound/cues/<id>.tres
##   ambience/<id>.ogg                           -> SoundCue sound/cues/<id>.tres (looping)
##   music/<id>.ogg (+ <id>_<layer>.ogg)         -> MusicTrack sound/music/<id>.tres (looping)
##   voices/<figure>/<line>.ogg                  -> that FigureData's voices[line]
## A cue's level, pitch jitter and limit are kept when its files change. A cue a sound
## designer pointed at files elsewhere is left alone. Nothing is deleted: cues and tracks
## whose files are gone are listed so they can be removed by hand.
##   -- --loops   only set music and ambience to loop in their import settings (then
##                re-import); sync_audio.sh runs this first

const AUDIO := "res://assets/audio"
const CUES := "res://sound/cues"
const MUSIC := "res://sound/music"
const LOOPING := ["music", "ambience"]
const MANAGED := ["sfx", "ambience"]

func _initialize() -> void:
	if "--loops" in OS.get_cmdline_user_args():
		print("SyncAudio: %d files set to loop" % _set_loops())
	else:
		_sync_cues()
		_sync_music()
		_sync_voices()
	quit(0)

# --- import settings ---
## Loop on in the .import of every music and ambience file. Returns how many changed
## (their imported copies are dropped, so the next import redoes them).
func _set_loops() -> int:
	var changed := 0
	for kind in LOOPING:
		for path: String in _oggs(AUDIO.path_join(kind)):
			var config := ConfigFile.new()
			if config.load(path + ".import") != OK or config.get_value("params", "loop", false):
				continue
			config.set_value("params", "loop", true)
			config.save(path + ".import")
			for dest in config.get_value("deps", "dest_files", []):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(String(dest).get_basename() + ".md5"))
			changed += 1
	return changed

# --- effects and ambience ---
func _sync_cues() -> void:
	DirAccess.make_dir_recursive_absolute(CUES)
	var groups := {} # cue id -> [stream paths]
	for kind in MANAGED:
		for path: String in _oggs(AUDIO.path_join(kind)):
			var id := _cue_id(path.get_file().get_basename())
			groups.get_or_add(id, []).append(path)
	var made := 0
	var updated := 0
	for id in groups:
		var file := CUES.path_join(id + ".tres")
		var cue: SoundCue = load(file) if ResourceLoader.exists(file) else null
		if cue == null:
			cue = SoundCue.new()
			made += 1
		elif not _auto_made(cue):
			continue
		var paths: Array = groups[id]
		paths.sort()
		var streams: Array[AudioStream] = []
		for path in paths:
			streams.append(load(path))
		if cue.id == StringName(id) and _paths(cue.streams) == paths:
			continue
		if cue.resource_path != "":
			updated += 1
		cue.id = StringName(id)
		cue.streams = streams
		ResourceSaver.save(cue, file)
	print("SyncAudio: cues %d new, %d updated, %d in all" % [made, updated, groups.size()])
	for file in _resources(CUES):
		var cue := load(file) as SoundCue
		if cue and _auto_made(cue) and not groups.has(String(cue.id)):
			print("SyncAudio: %s has no files any more (remove it if it's unused)" % file)

## "pawn_step_2" -> "pawn_step" (numbered variants share a cue).
func _cue_id(name: String) -> String:
	var cut := name.rfind("_")
	return name.left(cut) if cut > 0 and name.substr(cut + 1).is_valid_int() else name

## Made by this tool: no streams, or all from the folders it manages.
func _auto_made(cue: SoundCue) -> bool:
	for stream in cue.streams:
		if stream == null or not MANAGED.any(func(kind): return stream.resource_path.begins_with(AUDIO.path_join(kind) + "/")):
			return false
	return true

# --- music ---
func _sync_music() -> void:
	DirAccess.make_dir_recursive_absolute(MUSIC)
	var paths := _oggs(AUDIO.path_join("music"))
	var count := 0
	for path: String in paths:
		var id := path.get_file().get_basename()
		if Sound.MUSIC_LAYERS.any(func(layer): return id.ends_with("_" + String(layer))):
			continue
		var file := MUSIC.path_join(id + ".tres")
		var track: MusicTrack = load(file) if ResourceLoader.exists(file) else MusicTrack.new()
		track.id = StringName(id)
		track.stream = load(path)
		var layers: Dictionary[StringName, AudioStream] = {}
		for layer in Sound.MUSIC_LAYERS:
			var layer_path := path.get_base_dir().path_join("%s_%s.ogg" % [id, layer])
			if layer_path in paths:
				layers[layer] = load(layer_path)
		track.layers = layers
		ResourceSaver.save(track, file)
		count += 1
	print("SyncAudio: %d music tracks" % count)

# --- figure voices ---
func _sync_voices() -> void:
	var root := AUDIO.path_join("voices")
	for folder in DirAccess.get_directories_at(root):
		var figure := Figures.find(folder)
		if figure == null:
			print("SyncAudio: voices/%s has no FigureData in %s" % [folder, Figures.FOLDER])
			continue
		var voices: Dictionary[StringName, AudioStream] = {}
		for path: String in _oggs(root.path_join(folder)):
			voices[StringName(path.get_file().get_basename())] = load(path)
		figure.voices = voices
		ResourceSaver.save(figure, figure.resource_path)
		print("SyncAudio: %s: %d voice lines" % [folder, voices.size()])

# --- helpers ---
func _oggs(folder: String) -> Array:
	var found := []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == "ogg":
			found.append(folder.path_join(file))
	found.sort()
	return found

func _resources(folder: String) -> Array:
	var found := []
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == "tres":
			found.append(folder.path_join(file))
	return found

func _paths(streams: Array[AudioStream]) -> Array:
	return streams.map(func(s): return s.resource_path if s else "")
