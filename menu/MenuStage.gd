class_name MenuStage
extends Node3D

## The courtyard behind the menu: the chalk board on the mud at dusk or dawn, the lamp,
## and the Kondapalli figures. A view the menu shell and screens drive through these
## calls only, so another stage (2D art, a lighter one for small devices) can replace it:
##   show_lineup(figure)     all six figures in a row, the player's choice stepped forward
##   show_gathering(entries) the lobby: each player's figure at their side of the board
##   show_lesson(key)        How to play: chalk marks for "home", "path", "safe", "gate", "shells"
##   set_light(mode)         dusk / dawn
##   set_view_margin(f)      the left share of the screen the menu panel covers
##   to_match(side)          glide down into the seated match view (await it)
## signal figure_clicked(figure): a lineup figure was clicked or tapped.
## Off when headless (every call does nothing), like all views.

signal figure_clicked(figure: String)

## The camera at rest: low over the board, drifting slowly side to side.
const PITCH := 30.0
const DISTANCE := 9.2
const FOV := 40.0
const AIM := Vector3(0.0, 0.25, 0.7)
const DRIFT_DEGREES := 12.0
const DRIFT_SPEED := 0.06
const LINEUP_Z := 2.05
const LINEUP_GAP := 0.78
const LINEUP_SCALE := 1.45
const CHOSEN_SCALE := 1.85
const SEAT_RADIUS := 3.25
const PICK_RADIUS := 0.45
const BOARD_DATA_PATH := "res://board/data/board_layout_standard.tres"

var enabled := false
var camera: Camera3D
var _lights: Dictionary
var _lineup: Dictionary = {} # figure id -> PawnFigure
var _chosen := ""
## Lobby: seat -> {"node": PawnFigure, "label": Label3D, "key": what it shows}
var _gathered: Dictionary = {}
var _lesson_root: Node3D
var _view_margin := 0.0
var _time := 0.0
## While gliding into the match, the camera follows _glide instead of drifting.
var _glide: Dictionary = {}

func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	BoardWorld.add_floor(self)
	BoardWorld.add_chalk_board(self)
	_lights = BoardWorld.add_lighting(self, Settings.light())
	BoardWorld.apply_quality(_lights, get_viewport(), Settings.quality())
	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	camera.make_current()
	_lesson_root = Node3D.new()
	add_child(_lesson_root)
	var colors := GameConfig.COLORS.keys()
	var figures := GameConfig.FIGURES.keys()
	for i in figures.size():
		var fig := PawnFigure.create(figures[i], colors[i % colors.size()])
		fig.position = _lineup_position(i, figures.size())
		fig.scale = Vector3.ONE * LINEUP_SCALE
		fig.rotation.y = PI
		fig.visible = false
		add_child(fig)
		_lineup[figures[i]] = fig
	_update_camera(0.0)

func _process(delta: float) -> void:
	if enabled:
		_time += delta
		_update_camera(delta)

func _update_camera(_delta: float) -> void:
	var view := {"pitch": PITCH, "yaw": sin(_time * DRIFT_SPEED * TAU) * DRIFT_DEGREES,
		"distance": DISTANCE, "aim": AIM, "fov": FOV, "h_offset": _h_offset(FOV, DISTANCE)}
	if not _glide.is_empty():
		var k: float = _glide["k"]
		var to: Dictionary = _glide["to"]
		for key in view:
			view[key] = lerp(view[key], to[key], k) if key != "yaw" else lerpf(view[key], to[key], k)
	_place_camera(view)

func _place_camera(view: Dictionary) -> void:
	var pitch := deg_to_rad(view["pitch"])
	var yaw := deg_to_rad(view["yaw"])
	var aim: Vector3 = view["aim"]
	camera.fov = view["fov"]
	camera.h_offset = view["h_offset"]
	camera.position = aim + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(view["distance"])
	camera.look_at(aim, Vector3.UP)

## Shifts the picture so the board sits in the part of the screen the panel leaves free.
func _h_offset(fov: float, distance: float) -> float:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var aspect := size.x / maxf(size.y, 1.0)
	var half_width := distance * tan(deg_to_rad(fov) / 2.0) * aspect
	# not quite the panel's whole share: the board stays clear of the screen's edge
	return -_view_margin * half_width * 0.8

# --- the interface ---
func set_view_margin(left_fraction: float) -> void:
	_view_margin = clampf(left_fraction, 0.0, 0.8)

func set_light(mode: String) -> void:
	if enabled:
		BoardWorld.set_light(_lights, mode)

func show_lineup(figure: String) -> void:
	if not enabled:
		return
	_show_gathering_nodes(false)
	clear_lesson()
	for id in _lineup:
		(_lineup[id] as Node3D).visible = true
	select_figure(figure, false)

func select_figure(figure: String, react: bool = true) -> void:
	if not enabled or not _lineup.has(figure):
		return
	var changed := figure != _chosen
	_chosen = figure
	var ids := _lineup.keys()
	for i in ids.size():
		var fig: PawnFigure = _lineup[ids[i]]
		var chosen: bool = ids[i] == figure
		var to := _lineup_position(i, ids.size()) + (Vector3(0, 0, 0.45) if chosen else Vector3.ZERO)
		var t := fig.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(fig, "position", to, 0.35)
		t.tween_property(fig, "scale", Vector3.ONE * (CHOSEN_SCALE if chosen else LINEUP_SCALE), 0.35)
	if react and changed:
		(_lineup[figure] as PawnFigure).play(PawnFigure.CELEBRATE)

func _lineup_position(i: int, count: int) -> Vector3:
	return Vector3((i - (count - 1) / 2.0) * LINEUP_GAP, 0.0, LINEUP_Z)

## The lobby: entries = [{"seat", "side", "name", "color_name", "figure"}]. Newcomers
## walk in from beyond the board's edge; players who left walk away.
func show_gathering(entries: Array) -> void:
	if not enabled:
		return
	clear_lesson()
	for id in _lineup:
		(_lineup[id] as Node3D).visible = false
	_show_gathering_nodes(true)
	var present := {}
	for entry in entries:
		var seat := int(entry["seat"])
		present[seat] = true
		var key := [entry["figure"], entry["color_name"], entry["name"], int(entry["side"])]
		if _gathered.has(seat) and _gathered[seat]["key"] == key:
			continue
		if _gathered.has(seat):
			_dismiss(seat, false)
		_arrive(seat, entry, key)
	for seat in _gathered.keys():
		if not present.has(seat):
			_dismiss(seat, true)

func _side_vector(side: int) -> Vector3:
	var a := side * PI / 2.0
	return Vector3(sin(a), 0.0, cos(a))

func _arrive(seat: int, entry: Dictionary, key: Array) -> void:
	var side_dir := _side_vector(int(entry["side"]))
	var fig := PawnFigure.create(String(entry["figure"]), String(entry["color_name"]))
	fig.scale = Vector3.ONE * LINEUP_SCALE
	fig.position = side_dir * (SEAT_RADIUS + 3.0)
	fig.rotation.y = atan2(side_dir.x, side_dir.z) + PI
	add_child(fig)
	var name_label := Label3D.new()
	name_label.text = String(entry["name"])
	name_label.font = GameFonts.title()
	name_label.font_size = 40
	name_label.pixel_size = 0.0028
	name_label.modulate = GameConfig.lacquer_of(String(entry["color_name"]))["base"].lightened(0.25)
	name_label.outline_modulate = Color(0.1, 0.05, 0.02)
	name_label.outline_size = 12
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 0.62 * LINEUP_SCALE / fig.scale.x + 0.15, 0)
	fig.add_child(name_label)
	_gathered[seat] = {"node": fig, "key": key}
	var t := fig.create_tween()
	t.tween_property(fig, "position", side_dir * SEAT_RADIUS, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(fig.play.bind(PawnFigure.CELEBRATE))

func _dismiss(seat: int, walk_away: bool) -> void:
	var fig: Node3D = _gathered[seat]["node"]
	_gathered.erase(seat)
	if not walk_away:
		fig.queue_free()
		return
	var t := fig.create_tween()
	t.tween_property(fig, "position", fig.position * 2.5, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(fig.queue_free)

func _show_gathering_nodes(on: bool) -> void:
	for seat in _gathered:
		(_gathered[seat]["node"] as Node3D).visible = on

## How to play: chalk marks for one lesson ("" clears them). The lineup steps aside.
func show_lesson(key: String) -> void:
	if not enabled:
		return
	clear_lesson()
	for id in _lineup:
		(_lineup[id] as Node3D).visible = key == ""
	var path: Array[int] = (load(BOARD_DATA_PATH) as BoardData).get_seat_path(0)
	match key:
		"home":
			_mark(12, Color(1.0, 0.85, 0.4), 0.9)
			_mark(path[0], Color(0.95, 0.4, 0.3), 0.7)
			_chalk_text(BoardWorld.square_position(12), "home")
			_chalk_text(BoardWorld.square_position(path[0]), "start")
		"path":
			for i in path.size():
				_chalk_text(BoardWorld.square_position(path[i]), str(i + 1))
		"safe":
			for tile in BoardWorld.SAFE:
				_mark(tile, Color(0.4, 0.9, 0.95), 0.75)
		"gate":
			_mark(path[GameManager.OUTER_RING_STEPS - 1], Color(1.0, 0.85, 0.4), 0.6)
			_mark(path[GameManager.OUTER_RING_STEPS], Color(0.95, 0.35, 0.3), 0.75)
			_chalk_text(BoardWorld.square_position(path[GameManager.OUTER_RING_STEPS]), "shut")
		"shells":
			for i in 4:
				var shell := BoardWorld.add_shell(_lesson_root, Vector3(-0.6 + i * 0.4, 0, 1.0 + (0.08 if i % 2 else -0.05)), i < 3, i * 1.3)
				shell.scale = Vector3.ONE * 1.6

func clear_lesson() -> void:
	if not enabled:
		return
	for child in _lesson_root.get_children():
		child.queue_free()

func _mark(tile: int, color: Color, size: float) -> void:
	var mark := CardFx.chalk_mark(_lesson_root, BoardWorld.square_position(tile), color, true, 0.6)
	mark.scale = Vector3.ONE * size

func _chalk_text(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = GameFonts.chalk()
	label.font_size = 96
	label.pixel_size = 0.0035
	label.outline_size = 0
	label.modulate = Color(0.95, 0.93, 0.88, 0.9)
	label.rotation = Vector3(-PI / 2.0, 0, 0)
	label.double_sided = true
	label.position = at + Vector3.UP * 0.01
	_lesson_root.add_child(label)

## Glides down into the match's seated view from `side` (as BoardView3D frames it), the
## menu's figures stepping off. Returns when the camera is there.
func to_match(side: int) -> void:
	if not enabled:
		return
	clear_lesson()
	for node in _lineup.values() + _gathered.values().map(func(e): return e["node"]):
		var fig: Node3D = node
		fig.create_tween().tween_property(fig, "scale", Vector3.ZERO, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	var yaw := side * 90.0
	var drift := sin(_time * DRIFT_SPEED * TAU) * DRIFT_DEGREES
	yaw = drift + wrapf(yaw - drift, -180.0, 180.0)
	var toward := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	_glide = {"k": 0.0, "to": {"pitch": BoardView3D.PITCH, "yaw": yaw, "distance": BoardView3D.DISTANCE,
		"aim": toward * BoardView3D.AIM_SHIFT, "fov": BoardView3D.FOV, "h_offset": 0.0}}
	var t := create_tween()
	t.tween_method(func(k: float): _glide["k"] = k, 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

# --- picking a figure in the courtyard ---
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _lineup.values().any(func(f): return (f as Node3D).visible):
		return
	var from := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)
	if absf(dir.y) < 0.0001:
		return
	var hit := from + dir * (-from.y / dir.y)
	var best := ""
	var best_d := PICK_RADIUS
	for id in _lineup:
		var at: Vector3 = (_lineup[id] as Node3D).position
		# aim a little above the feet: people click the figure's body
		var d := Vector2(at.x - hit.x, at.z + 0.25 - hit.z).length()
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		get_viewport().set_input_as_handled()
		figure_clicked.emit(best)
