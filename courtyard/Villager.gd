class_name Villager
extends AudienceMember

## A villager watching the game: a Kondapalli toy from assets/villagers/<id>.glb (built
## by the AshtaChemmaArt pipeline: villagers/*.py), idling until a big moment, then
## playing that moment's animation (and sound), a beat after the others so a crowd
## doesn't move as one. Who they are and what they do per moment: a VillagerData resource.

const IDLE := "idle"

var data: VillagerData
var _player: AnimationPlayer

static func create(villager: VillagerData) -> Villager:
	var node := Villager.new()
	node.data = villager
	node.name = String(villager.id).capitalize()
	node.scale = Vector3.ONE * villager.scale
	if villager.model:
		var model: Node3D = villager.model.instantiate()
		node.add_child(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			node._player = players[0]
			node._player.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
			node._player.animation_finished.connect(node._on_finished)
	return node

func _ready() -> void:
	if _player:
		_player.play(IDLE)
		_player.seek(randf() * _player.current_animation_length, true)

func react(moment: StringName) -> void:
	var animation: String = data.reactions.get(moment, "")
	if animation == "" or _player == null or not _player.has_animation(animation):
		return
	get_tree().create_timer(randf_range(0.15, 0.5)).timeout.connect(func():
		_player.play(animation, 0.15)
		Sound.play_cue(data.sounds.get(StringName(animation)), -4.0))

func current_animation() -> String:
	return String(_player.current_animation) if _player else ""

func _on_finished(animation: StringName) -> void:
	if animation != IDLE:
		_player.play(IDLE, 0.3)
