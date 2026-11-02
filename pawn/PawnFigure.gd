class_name PawnFigure
extends Node3D

## A Kondapalli wooden figure (assets/pawns/<figure>.glb, built in the AshtaChemmaArt
## project) painted in a player's lacquer. It idles on its own; play() runs one of the
## reaction animations and then goes back to idling.
## Model rules: materials named Base / Accent are repainted per player, origin at the
## base centre, facing -Z, about 0.5 units tall (one board square is about 1 unit).
## Besides the model's own animations it can act out moves made in code, each with this
## figure's voice: relieve() (a near miss), gesture() ("taunt", "laugh", "plead", or any
## animation), and set_nervous() (fidgeting and glancing round while in danger).
## Layers: this node (placed by the board view) > _pivot (nervousness) > _model (gestures).

const IDLE := "idle"
const ATTACK := "attack"
const CELEBRATE := "celebrate"
const SAD := "sad"
## Not an animation: the voice for escaping a near miss (see relieve()).
const RELIEF := "relief"
const BLEND_TIME := 0.15
## Every figure's height with its plinth (see height()).
const HEIGHT := 0.58
## Nervousness: how often (seconds) a worried figure glances round, at most.
const GLANCE_EVERY := 2.4

var figure: String = ""
var data: FigureData
var _player: AnimationPlayer
var _pivot: Node3D
var _model: Node3D
var _gesture_tween: Tween
var _nervous := 0.0
var _glance_in := 0.0
var _time := 0.0

static func create(figure_id: String, color_name: String) -> PawnFigure:
	var node := PawnFigure.new()
	node.figure = Figures.or_default(figure_id)
	node.data = Figures.find(node.figure)
	node.name = node.figure.capitalize()
	node._pivot = Node3D.new()
	node._pivot.name = "Pivot"
	node.add_child(node._pivot)
	node._model = node.data.model.instantiate()
	node._pivot.add_child(node._model)
	node.paint(color_name)
	var players := node._model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		node._player = players[0]
		node._player.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
		node._player.animation_finished.connect(node._on_finished)
	return node

func _ready() -> void:
	set_process(false) # only while nervous
	if _player:
		_player.play(IDLE)
		# Start each figure at a different point so a row of them doesn't move in step
		_player.seek(randf() * _player.current_animation_length, true)

## Repaints the Base and Accent parts in a colour choice's lacquer (TeamColorData).
func paint(color_name: String) -> void:
	var colors := TeamColors.of(color_name)
	var lacquer := {"base": colors.base, "accent": colors.accent}
	for mesh_node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null:
				continue
			var slot := source.resource_name.to_lower()
			if slot == "base" or slot == "accent":
				var mat := source.duplicate() as BaseMaterial3D
				mat.albedo_color = lacquer[slot]
				mi.set_surface_override_material(i, mat)

## Plays a reaction (ATTACK, CELEBRATE, SAD) once, then idles again, with this figure's
## voice for it (or another of its voices, e.g. RELIEF). Several figures reacting
## together start a moment apart, like a chorus.
func play(animation: String, voice_as: String = "") -> void:
	if _player and _player.has_animation(animation):
		_player.play(animation, BLEND_TIME)
		voice(voice_as if voice_as != "" else animation, randf() * 0.12)

## This figure's sound for an animation (IDLE is a little hello when it's picked).
func voice(animation: String, delay: float = 0.0, volume_db: float = 0.0) -> void:
	Sound.play_stream(data.voices.get(StringName(animation)), volume_db, delay)

# --- moves made in code (on _model, so the board view keeps placing this node) ---
func _new_gesture(delay: float) -> Tween:
	if _gesture_tween and _gesture_tween.is_valid():
		_gesture_tween.kill()
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	_model.scale = Vector3.ONE
	_gesture_tween = create_tween()
	if delay > 0.0:
		_gesture_tween.tween_interval(delay)
	return _gesture_tween

## A near miss: the figure flinches back from the danger, trembles, then sags with a
## big exhale and settles, while saying its RELIEF line.
func relieve(delay: float = 0.0) -> void:
	if _model == null:
		return
	var t := _new_gesture(delay)
	t.tween_callback(voice.bind(RELIEF))
	t.tween_property(_model, "rotation:x", -0.38, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 5:
		t.tween_property(_model, "rotation:z", 0.09 if i % 2 == 0 else -0.09, 0.06)
	t.tween_property(_model, "rotation:z", 0.0, 0.06)
	t.tween_property(_model, "rotation:x", 0.08, 0.25).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_model, "scale", Vector3(1.12, 0.84, 1.12), 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_property(_model, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_model, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## An emote or a taunt, with its voice line (voice_as, default: the gesture's name):
##   "taunt"  leans in, wags side to side, a cheeky hop
##   "laugh"  shakes and bobs with laughter
##   "plead"  bows low, trembling a little, and comes back up slowly
##   anything else: the model's own animation of that name (celebrate, sad, attack)
func gesture(kind: String, voice_as: String = "", delay: float = 0.0) -> void:
	if _model == null:
		return
	var line := voice_as if voice_as != "" else kind
	if not kind in ["taunt", "laugh", "plead"]:
		if delay > 0.0:
			get_tree().create_timer(delay).timeout.connect(play.bind(kind, line))
		else:
			play(kind, line)
		return
	var t := _new_gesture(delay)
	t.tween_callback(voice.bind(line))
	match kind:
		"taunt":
			t.tween_property(_model, "rotation:x", 0.3, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			for i in 4:
				t.tween_property(_model, "rotation:z", 0.16 if i % 2 == 0 else -0.16, 0.11).set_trans(Tween.TRANS_SINE)
			t.tween_property(_model, "rotation:z", 0.0, 0.08)
			t.tween_property(_model, "position:y", 0.12, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(_model, "rotation:x", 0.0, 0.2)
			t.tween_property(_model, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"laugh":
			for i in 8:
				t.tween_property(_model, "position:y", 0.05 if i % 2 == 0 else 0.0, 0.07)
				t.parallel().tween_property(_model, "rotation:z", 0.07 if i % 4 < 2 else -0.07, 0.07)
			t.tween_property(_model, "rotation:x", -0.18, 0.15)
			t.tween_property(_model, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
			t.parallel().tween_property(_model, "rotation:z", 0.0, 0.25)
			t.parallel().tween_property(_model, "position:y", 0.0, 0.2)
		"plead":
			t.tween_property(_model, "rotation:x", 0.45, 0.35).set_trans(Tween.TRANS_SINE)
			for i in 4:
				t.tween_property(_model, "rotation:z", 0.04 if i % 2 == 0 else -0.04, 0.12)
			t.tween_property(_model, "rotation:z", 0.0, 0.1)
			t.tween_property(_model, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)

## In danger (0 = safe, 1 = very likely to be captured next throw): the figure fidgets,
## more the likelier it is, and now and then glances round.
func set_nervous(level: float) -> void:
	_nervous = clampf(level, 0.0, 1.0)
	set_process(_nervous > 0.0)
	if _nervous <= 0.0 and _pivot:
		create_tween().tween_property(_pivot, "rotation", Vector3.ZERO, 0.3)

func is_nervous() -> bool:
	return _nervous > 0.0

func _process(delta: float) -> void:
	_time += delta
	var strength := 0.3 + 0.7 * _nervous
	_pivot.rotation.z = sin(_time * 26.0) * 0.022 * strength + sin(_time * 7.0) * 0.012 * strength
	_glance_in -= delta
	if _glance_in <= 0.0:
		_glance_in = GLANCE_EVERY * randf_range(0.6, 1.4) / strength
		var t := create_tween()
		var look := randf_range(0.45, 0.75) * (1.0 if randf() < 0.5 else -1.0)
		t.tween_property(_pivot, "rotation:y", look, 0.18).set_trans(Tween.TRANS_SINE)
		t.tween_interval(0.25)
		t.tween_property(_pivot, "rotation:y", -look * 0.7, 0.2).set_trans(Tween.TRANS_SINE)
		t.tween_interval(0.2)
		t.tween_property(_pivot, "rotation:y", 0.0, 0.25).set_trans(Tween.TRANS_SINE)

## How tall the figure stands (local units). The art pipeline makes every figure about
## half a unit tall with its plinth (AshtaChemmaArt/kondapalli.py); measuring meshes
## doesn't work here, since an animated (skinned) mesh's bounds are oversized.
func height() -> float:
	return HEIGHT

func current_animation() -> String:
	return String(_player.current_animation) if _player else ""

func _on_finished(animation: StringName) -> void:
	if animation != IDLE:
		_player.play(IDLE, BLEND_TIME * 2.0)
