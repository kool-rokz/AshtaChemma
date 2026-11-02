class_name Courtyard
extends Node3D

## The people around the board: villagers sitting and standing at the courtyard's edge
## who watch the game and react to its big moments. A view, owned by whichever stage
## shows the board (BoardView3D in a match, MenuStage in the menu), fed moments by it.
##   cast    who's there, in which spot, and what they do for each moment: VillagerData
##           resources in courtyard/data/ (models in assets/villagers/)
##   SPOTS   places round the board, on the far side and the edges from the viewer
## Members are AudienceMembers, so other kinds (an online spectator) can take a spot.
## The whole courtyard turns to face the viewer's side (face_side), so the onlookers
## are always across the board from you.

## The match moments members react to.
const MOMENTS := [&"capture", &"near_miss", &"big_throw", &"home", &"gate", &"forfeit", &"win"]

## Spots (board units, as seen from side 0, the bottom): the far corners and the edges.
const SPOTS := [
	Vector3(-3.0, 0.0, -2.75),  # 0: far left corner
	Vector3(3.35, 0.0, -2.2),   # 1: far right, by the lamp
	Vector3(1.6, 0.0, -3.1),    # 2: far edge, right of the middle (clear of the lamp's glare)
	Vector3(-3.4, 0.0, -1.6),   # 3: left edge (clear of a lobby figure's seat)
	Vector3(3.6, 0.0, 0.2),     # 4: right edge
]

## Where the cast comes from: every VillagerData .tres in this folder (one file per
## onlooker; a new villager = a new file, no code).
const CAST_FOLDER := "res://courtyard/data"

var _members: Array[AudienceMember] = []

func _ready() -> void:
	for res in ResourceFolder.load_all(CAST_FOLDER, func(r): return r is VillagerData, "Courtyard"):
		var data := res as VillagerData
		add_member(Villager.create(data), data.spot)

## Puts a member in a spot, facing the board's middle.
func add_member(member: AudienceMember, spot: int) -> void:
	var at: Vector3 = SPOTS[spot % SPOTS.size()]
	member.position = at
	member.rotation.y = atan2(-at.x, -at.z) # face the middle (toys face -Z)
	add_child(member)
	_members.append(member)

func members() -> Array[AudienceMember]:
	return _members

## Everyone reacts to a big moment (one of MOMENTS).
func moment(name: StringName) -> void:
	for member in _members:
		if is_instance_valid(member):
			member.react(name)

## Turns the courtyard so the onlookers sit across the board from `side` (a board side,
## 0 = bottom), as the board view sees it.
func face_side(side: int) -> void:
	rotation.y = side * PI / 2.0
