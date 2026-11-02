extends Node3D

## Test level for the pawn figures and their reactions. Run labs/FigureLab.tscn (F6).
## Six figures in a row on the mud: the left three are one team, the right three another.
##   Buttons: play one animation on every figure, or act out a game event the way the
##   match does (BoardView3D): a capture, a 4/8 throw, losing the throws to three 4/8s
##   in a row, a win. Colours cycles the lacquer, Dusk / dawn switches the lighting.
##   Drag to orbit the camera, scroll to zoom. Labels show what each figure is playing.

const SPACING := 0.95
const TEAM_SIZE := 3

var _figures: Array[PawnFigure] = []
var _labels: Array[Label3D] = []
var _homes: Array[Vector3] = []
var _team_colors := [0, 1] # indices into GameConfig.COLORS
var _lights: Dictionary
var _light := BoardWorld.DUSK
var _camera: Camera3D
var _yaw := 0.0
var _pitch := 28.0
var _distance := 6.5
var _dragging := false
var _busy := false

func _ready() -> void:
	GameFonts.install()
	BoardWorld.add_floor(self)
	_lights = BoardWorld.add_lighting(self, _light)
	var figures := GameConfig.FIGURES.keys()
	for i in figures.size():
		var fig := PawnFigure.create(figures[i], _color_for(i))
		var home := Vector3((i - (figures.size() - 1) / 2.0) * SPACING, 0, 0)
		fig.position = home
		fig.rotation.y = PI # models face -Z; turn them to the camera
		add_child(fig)
		_figures.append(fig)
		_homes.append(home)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.pixel_size = 0.004
		label.outline_size = 8
		label.position = home + Vector3(0, 0.75, 0)
		add_child(label)
		_labels.append(label)
	_camera = Camera3D.new()
	_camera.fov = 40
	add_child(_camera)
	_place_camera()
	_build_ui()

func _color_for(i: int) -> String:
	return GameConfig.COLORS.keys()[_team_colors[0 if i < TEAM_SIZE else 1]]

func _team(team: int) -> Array[PawnFigure]:
	var out: Array[PawnFigure] = []
	for i in _figures.size():
		if (i < TEAM_SIZE) == (team == 0):
			out.append(_figures[i])
	return out

func _process(_delta: float) -> void:
	for i in _figures.size():
		_labels[i].text = "%s\n%s" % [GameConfig.FIGURES[_figures[i].figure], _figures[i].current_animation()]
		_labels[i].position = _figures[i].position + Vector3(0, 0.75, 0)

# --- buttons ---
func _play_all(animation: String) -> void:
	for fig in _figures:
		fig.play(animation)

## A capture, as in a match: the attacker hops onto the victim's square and attacks,
## the victim is sad and slides back to its homebase. Then both return to their places.
func _capture() -> void:
	if _busy:
		return
	_busy = true
	var attacker := _figures[TEAM_SIZE - 1]
	var victim := _figures[TEAM_SIZE]
	var target := victim.position
	attacker.rotation.y = atan2(-(target - attacker.position).x, -(target - attacker.position).z)
	var hop := create_tween()
	hop.tween_property(attacker, "position", target + Vector3.UP * 0.25, 0.22).set_trans(Tween.TRANS_SINE)
	hop.tween_property(attacker, "position", target - Vector3(0.45, 0, 0), 0.18).set_trans(Tween.TRANS_SINE)
	await hop.finished
	attacker.play(PawnFigure.ATTACK)
	victim.play(PawnFigure.SAD)
	var slide := create_tween()
	slide.tween_property(victim, "position", target + Vector3(0, 0, -1.6), 0.6).set_delay(0.5)
	await slide.finished
	# The attacker steps onto the square it took
	var step := create_tween()
	step.tween_property(attacker, "position", target, 0.25).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(1.8).timeout
	var back := create_tween().set_parallel()
	back.tween_property(attacker, "position", _homes[TEAM_SIZE - 1], 0.5)
	back.tween_property(attacker, "rotation:y", PI, 0.5)
	back.tween_property(victim, "position", _homes[TEAM_SIZE], 0.5)
	await back.finished
	_busy = false

func _bonus_throw() -> void:
	for fig in _team(0):
		fig.play(PawnFigure.CELEBRATE)

func _throws_lost() -> void:
	for fig in _team(0):
		fig.play(PawnFigure.SAD)

func _win() -> void:
	for fig in _team(0):
		fig.play(PawnFigure.CELEBRATE)
	for fig in _team(1):
		fig.play(PawnFigure.SAD)

func _cycle_colours() -> void:
	var count := GameConfig.COLORS.size()
	_team_colors = [(_team_colors[0] + 1) % count, (_team_colors[1] + 1) % count]
	for i in _figures.size():
		_figures[i].paint(_color_for(i))

func _toggle_light() -> void:
	_light = BoardWorld.DAWN if _light == BoardWorld.DUSK else BoardWorld.DUSK
	BoardWorld.set_light(_lights, _light)

# --- camera ---
func _place_camera() -> void:
	var dir := Vector3(sin(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)), sin(deg_to_rad(_pitch)),
		cos(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)))
	var target := Vector3(0, 0.25, 0)
	_camera.position = target + dir * _distance
	_camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(1.5, _distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(15.0, _distance * 1.1)
		_place_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.3
		_pitch = clampf(_pitch + event.relative.y * 0.3, 5.0, 89.0)
		_place_camera()

# --- UI ---
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "Figure lab — drag to orbit, scroll to zoom. Left three = team A, right three = team B."
	panel.add_child(title)
	_row(panel, "Every figure:", [["Idle", _play_all.bind(PawnFigure.IDLE)], ["Attack", _play_all.bind(PawnFigure.ATTACK)],
		["Celebrate", _play_all.bind(PawnFigure.CELEBRATE)], ["Sad", _play_all.bind(PawnFigure.SAD)]])
	_row(panel, "Game events:", [["Capture (A takes B)", _capture], ["Team A throws 4/8", _bonus_throw],
		["Team A loses throws (three 4/8s)", _throws_lost], ["Team A wins", _win]])
	_row(panel, "Look:", [["Colours", _cycle_colours], ["Dusk / dawn", _toggle_light]])

func _row(parent: Control, label_text: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110
	row.add_child(label)
	for entry in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		row.add_child(button)
	parent.add_child(row)
