class_name ShellsView
extends Control

## The last throw in the side panel, as the same 3D shells that were thrown: four in a
## row, open-side-up ones ringed in gold. Before a throw they show faint and face down.
## ShellStage flies the thrown shells into slot_screen_positions(), hidden here until
## they arrive (revealed = false), so the hand-over is seamless.

const SIZE := Vector2(184, 60)
const SLOT_GAP := 44.0
## Hovering spins the shells slowly so both sides can be seen.
const HOVER_SPIN := 1.2

var shells: Array[bool] = []:
	set(value):
		shells = value
		_refresh()

## false while ShellStage is still flying the shells here.
var revealed: bool = true:
	set(value):
		revealed = value
		_refresh()

var _shells_3d: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _hovered: bool = false
var _spin: float = 0.0

func _init() -> void:
	custom_minimum_size = SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_entered.connect(func(): _hovered = true)
	mouse_exited.connect(func(): _hovered = false)

func _ready() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := ShellModel.make_viewport()
	container.add_child(viewport)
	# Local coordinates: the view's own rect, so slot i sits at _slot_local(i)
	viewport.add_child(ShellModel.make_camera(Rect2(Vector2.ZERO, SIZE)))
	ShellModel.add_lighting(viewport)
	for i in 4:
		var shell := ShellModel.make_shell()
		viewport.add_child(shell)
		_shells_3d.append(shell)
		var ring := ShellModel.make_ring()
		viewport.add_child(ring)
		_rings.append(ring)
	_refresh()

func _process(delta: float) -> void:
	if not _hovered and is_zero_approx(_spin):
		return
	# Spin while hovered, then ease back to the resting row
	_spin = _spin + delta * HOVER_SPIN if _hovered else move_toward(fmod(_spin, TAU), 0.0, delta * 3.0)
	_refresh()

## Where each shell rests, in screen pixels (where ShellStage should land them).
func slot_screen_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in 4:
		result.append(get_global_rect().position + _slot_local(i))
	return result

func _slot_local(i: int) -> Vector2:
	return Vector2(SIZE.x / 2.0 + (i - 1.5) * SLOT_GAP, SIZE.y / 2.0)

func _refresh() -> void:
	if _shells_3d.is_empty():
		return
	for i in 4:
		var thrown := i < shells.size()
		var open_up := thrown and shells[i]
		var shell := _shells_3d[i]
		var pos := ShellModel.screen_to_ground(_slot_local(i), ShellModel.rest_height(open_up))
		shell.transform = Transform3D(Basis(Vector3.UP, _spin) * ShellModel.resting_basis(open_up, 0.0), pos)
		shell.material_override = null if thrown else ShellModel.ghost_material()
		shell.visible = revealed
		_rings[i].position = Vector3(pos.x, 0.01, pos.z)
		_rings[i].visible = revealed and open_up
