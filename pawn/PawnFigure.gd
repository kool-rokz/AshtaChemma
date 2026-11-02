class_name PawnFigure
extends Node3D

## A Kondapalli wooden figure (assets/pawns/<figure>.glb, built in the AshtaChemmaArt
## project) painted in a player's lacquer. It idles on its own; play() runs one of the
## reaction animations and then goes back to idling.
## Model rules: materials named Base / Accent are repainted per player, origin at the
## base centre, facing -Z, about 0.5 units tall (one board square is about 1 unit).

const MODEL_PATH := "res://assets/pawns/%s.glb"
const IDLE := "idle"
const ATTACK := "attack"
const CELEBRATE := "celebrate"
const SAD := "sad"
## Not an animation: the voice for escaping a near miss (see relieve()).
const RELIEF := "relief"
const BLEND_TIME := 0.15

var figure: String = ""
var _player: AnimationPlayer
var _model: Node3D

static func create(figure_id: String, color_name: String) -> PawnFigure:
	var node := PawnFigure.new()
	node.figure = GameConfig.figure_or_default(figure_id)
	node.name = node.figure.capitalize()
	var scene: PackedScene = load(MODEL_PATH % node.figure)
	node._model = scene.instantiate()
	node.add_child(node._model)
	node.paint(color_name)
	var players := node._model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		node._player = players[0]
		node._player.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
		node._player.animation_finished.connect(node._on_finished)
	return node

func _ready() -> void:
	if _player:
		_player.play(IDLE)
		# Start each figure at a different point so a row of them doesn't move in step
		_player.seek(randf() * _player.current_animation_length, true)

## Repaints the Base and Accent parts in a colour choice's lacquer (GameConfig.LACQUER).
func paint(color_name: String) -> void:
	var lacquer := GameConfig.lacquer_of(color_name)
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
	Sound.play(StringName("%s_%s" % [figure, animation]), volume_db, delay)

## A near miss: the figure flinches back from the danger, trembles, then sags with a
## big exhale and settles, while saying its RELIEF line. Moves the model only (the
## figure node stays where the board view puts it), so it works mid-idle anywhere.
func relieve(delay: float = 0.0) -> void:
	if _model == null:
		return
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(voice.bind(RELIEF))
	t.tween_property(_model, "rotation:x", -0.38, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 5:
		t.tween_property(_model, "rotation:z", 0.09 if i % 2 == 0 else -0.09, 0.06)
	t.tween_property(_model, "rotation:z", 0.0, 0.06)
	t.tween_property(_model, "rotation:x", 0.08, 0.25).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_model, "scale", Vector3(1.12, 0.84, 1.12), 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_property(_model, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_model, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func current_animation() -> String:
	return String(_player.current_animation) if _player else ""

func _on_finished(animation: StringName) -> void:
	if animation != IDLE:
		_player.play(IDLE, BLEND_TIME * 2.0)
