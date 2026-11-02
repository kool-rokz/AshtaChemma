extends Node3D

## Test level for the match camera and the look. Run labs/CameraLab.tscn (F6).
## A mid-game board in chalk on mud with four players' figures and a set of shells.
## (The HUD, cards and throw it used to mock now live in the match itself.)
##   1-6   camera presets (see PRESETS), 7 = free orbit (drag to orbit, scroll to zoom)
##   S     view from the next player's seat (each player sees the board from their side)
##   Space act out a capture        D  draw the board in       L  dusk / dawn
##   F     swap which figure each player has                   R  reset the board

## pitch: degrees above the board (90 = straight down); yaw: degrees round from the bottom
## seat; size: orthographic view height in units; fov: perspective field of view.
const PRESETS := [
	{"name": "Top-down", "ortho": true, "pitch": 90.0, "yaw": 0.0, "size": 6.6, "distance": 20.0},
	{"name": "Steep 65°", "ortho": false, "pitch": 65.0, "yaw": 0.0, "fov": 32.0, "distance": 11.5},
	{"name": "Seated 50° (the match)", "ortho": false, "pitch": BoardView3D.PITCH, "yaw": 0.0, "fov": BoardView3D.FOV, "distance": BoardView3D.DISTANCE},
	{"name": "Low 35°, close (the match's push-in)", "ortho": false, "pitch": BoardView3D.CLOSE_PITCH, "yaw": 0.0, "fov": 44.0, "distance": BoardView3D.CLOSE_DISTANCE},
	{"name": "Diorama (isometric)", "ortho": true, "pitch": 35.0, "yaw": 45.0, "size": 6.4, "distance": 20.0},
	{"name": "Corner 55°", "ortho": false, "pitch": 55.0, "yaw": 30.0, "fov": 36.0, "distance": 10.0},
]
const TRANSITION := 0.6
## Homebase square per seat (bottom, right, top, left).
const HOMEBASE := [22, 14, 2, 10]
const SEAT_COLORS := ["Red", "Blue", "Yellow", "Green"]
## Where each seat's four pawns stand in this mid-game layout.
const LAYOUT := [[22, 22, 23, 18], [14, 14, 9, 4], [2, 2, 2, 1], [10, 10, 15, 21]]

var _camera: Camera3D
var _view := {"ortho": true, "pitch": 90.0, "yaw": 0.0, "size": 6.6, "fov": 40.0, "distance": 20.0}
var _preset := 0
var _seat := 0
var _free := false
var _dragging := false
var _light := BoardWorld.DUSK
var _figure_offset := 0
var _lights: Dictionary
var _board: MeshInstance3D
## [seat][pawn] -> PawnFigure, and the square each stands on
var _figures: Array = []
var _squares: Array = []
var _info: Label
var _busy := false

func _ready() -> void:
	GameFonts.install()
	BoardWorld.add_floor(self)
	_board = BoardWorld.add_chalk_board(self)
	_lights = BoardWorld.add_lighting(self, _light)
	_spawn_figures()
	for i in 4:
		BoardWorld.add_shell(self, Vector3(3.3 + (i % 2 - 0.5) * 0.3, 0, 1.6 + (floorf(i / 2.0) - 0.5) * 0.26), i % 3 == 0, i * 1.3)
	_camera = Camera3D.new()
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(16, 650)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	layer.add_child(_info)
	_select(2, false)

func _spawn_figures() -> void:
	for seat in _figures:
		for fig in seat:
			fig.queue_free()
	_figures.clear()
	_squares.clear()
	var ids := GameConfig.FIGURES.keys()
	for seat in 4:
		var row: Array = []
		for pawn in 4:
			var fig := PawnFigure.create(ids[(seat + _figure_offset) % ids.size()], SEAT_COLORS[seat])
			add_child(fig)
			row.append(fig)
		_figures.append(row)
		_squares.append((LAYOUT[seat] as Array).duplicate())
	_layout_all()

## Spread pawns that share a square, like GameManager._layout_tile (in squares, not pixels).
func _layout_all() -> void:
	var by_square := {}
	for seat in 4:
		for pawn in 4:
			by_square.get_or_add(_squares[seat][pawn], []).append(_figures[seat][pawn])
	for square in by_square:
		var group: Array = by_square[square]
		for i in group.size():
			group[i].position = _spot(square, i, group.size())
			group[i].scale = Vector3.ONE * (0.75 if group.size() > 1 else 1.0)
	_face_viewer()

func _spot(square: int, i: int, count: int) -> Vector3:
	if count <= 1:
		return BoardWorld.square_position(square)
	var angle := TAU * i / count - PI / 4.0
	return BoardWorld.square_position(square) + Vector3(cos(angle), 0, sin(angle)) * 0.22

## Figures turn to the viewer's side, each a little differently so a group looks natural.
func _face_viewer() -> void:
	for seat in _figures.size():
		for pawn in 4:
			var fig: PawnFigure = _figures[seat][pawn]
			fig.rotation.y = deg_to_rad(_view["yaw"]) + PI + deg_to_rad((seat * 4 + pawn) % 5 * 12.0 - 24.0)

# --- camera ---
func _select(index: int, animate: bool = true) -> void:
	_free = index >= PRESETS.size()
	if _free:
		_update_info()
		return
	_preset = index
	var target: Dictionary = PRESETS[index].duplicate()
	target["yaw"] = target["yaw"] + _seat * 90.0
	_go_to(target, animate)

func _go_to(target: Dictionary, animate: bool) -> void:
	_view["ortho"] = target["ortho"]
	var from := _view.duplicate()
	if not animate:
		for key in target:
			_view[key] = target[key]
		_apply_camera()
		return
	# Turn the short way round
	target["yaw"] = from["yaw"] + wrapf(target["yaw"] - from["yaw"], -180.0, 180.0)
	var tween := create_tween()
	tween.tween_method(func(t: float):
		for key in ["pitch", "yaw", "distance"]:
			_view[key] = lerpf(from[key], target[key], t)
		if target.has("size"):
			_view["size"] = lerpf(from.get("size", target["size"]), target["size"], t)
		if target.has("fov"):
			_view["fov"] = lerpf(from.get("fov", target["fov"]), target["fov"], t)
		_apply_camera(), 0.0, 1.0, TRANSITION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Aimed like the match camera (a little towards the viewer, so the board sits above
## the hand of cards).
func _apply_camera() -> void:
	var pitch := deg_to_rad(clampf(_view["pitch"], 5.0, 89.9))
	var yaw := deg_to_rad(_view["yaw"])
	var toward_viewer := Vector3(sin(yaw), 0, cos(yaw))
	var aim := toward_viewer * BoardView3D.AIM_SHIFT
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if _view["ortho"] else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = _view["size"]
	_camera.fov = _view["fov"]
	_camera.position = aim + dir * float(_view["distance"])
	_camera.look_at(aim, -toward_viewer if _view["pitch"] > 89.0 else Vector3.UP)
	_face_viewer()
	_update_info()

func _update_info() -> void:
	if _info == null:
		return
	var title: String = "Free orbit" if _free else PRESETS[_preset]["name"]
	var lens: String = "orthographic, height %.1f" % _view["size"] if _view["ortho"] else "perspective, fov %d°" % _view["fov"]
	_info.text = "%d  %s   —   pitch %d°, %s, seat %d (%s), %s\n1-6 presets · 7 orbit · S seat · Space capture · D draw board · L dusk/dawn · F figures · R reset" % [
		(PRESETS.size() + 1) if _free else _preset + 1, title, roundi(_view["pitch"]), lens, _seat + 1, SEAT_COLORS[_seat], _light]

# --- actions ---
## Green's pawn on square 21 hops two squares towards 23 and takes Red's pawn there: it
## stops just short to attack, Red's pawn is sad and is knocked back to its homebase,
## then the attacker steps onto the middle of the square it took. R puts it all back.
func _capture() -> void:
	var victim_square := 23
	var attacker: PawnFigure = _figures[3][3]
	var victim: PawnFigure = _figures[0][2]
	if _busy or _squares[3][3] != 21 or _squares[0][2] != victim_square:
		return
	_busy = true
	var target := BoardWorld.square_position(victim_square)
	await CardFx.hop_along(attacker, [BoardWorld.square_position(22), target + Vector3(-0.42, 0, 0)])
	attacker.play(PawnFigure.ATTACK)
	victim.play(PawnFigure.SAD)
	await get_tree().create_timer(0.9).timeout
	_squares[0][2] = HOMEBASE[0]
	_squares[3][3] = victim_square
	await CardFx.knock_home(victim, _spot(HOMEBASE[0], 2, 3))
	await CardFx.hop_along(attacker, [target], 0.25)
	_layout_all()
	_busy = false

func _draw_board() -> void:
	var mat := _board.material_override as ShaderMaterial
	var tween := create_tween()
	tween.tween_method(func(v: float): mat.set_shader_parameter("drawn", v), 0.0, 1.0, 1.6)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				_select(event.keycode - KEY_1)
			KEY_S:
				_seat = (_seat + 1) % 4
				if _free:
					_view["yaw"] += 90.0
					_apply_camera()
				else:
					_select(_preset)
			KEY_SPACE:
				_capture()
			KEY_D:
				_draw_board()
			KEY_L:
				_light = BoardWorld.DAWN if _light == BoardWorld.DUSK else BoardWorld.DUSK
				BoardWorld.set_light(_lights, _light)
				_update_info()
			KEY_F:
				_figure_offset += 1
				_spawn_figures()
			KEY_R:
				_spawn_figures()
	elif _free and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_view["distance"] = maxf(3.0, _view["distance"] * 0.92)
			_view["size"] = maxf(2.0, _view["size"] * 0.92)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_view["distance"] = minf(30.0, _view["distance"] * 1.08)
			_view["size"] = minf(15.0, _view["size"] * 1.08)
		_apply_camera()
	elif _free and _dragging and event is InputEventMouseMotion:
		_view["yaw"] -= event.relative.x * 0.3
		_view["pitch"] = clampf(_view["pitch"] + event.relative.y * 0.3, 5.0, 89.9)
		_apply_camera()
