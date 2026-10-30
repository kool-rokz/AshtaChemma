class_name ShellStage
extends Node

## The shells in 3D over the board: holding and shaking them, the throw, the result.
##   Hold the mouse (or touch) on the board, shake, let go: throw_released(gesture).
##   Gamepad / keyboard: hold A or Space, shake with the left stick or arrows, let go.
##   A quick click, or the Throw button: a gentle toss (ThrowGesture.quick).
## MatchController turns throw_released into a THROW intent; once the throw is decided
## (by the host, online) it awaits show_throw(), which plans a flight that lands on
## exactly those faces (ShellSim), plays it, holds the result, and returns. The shells
## then fly into the side panel's ShellsView. Headless runs skip all of it.
## Online, the hand is streamed while shaking (shake_changed) and other players' hands
## are shown (show_remote_shake); their throw then starts from what was on screen.

signal throw_released(gesture: ThrowGesture)
## This screen's hand while shaking, about 10 times a second ({holding: false} = put down).
signal shake_changed(state: Dictionary)

## Height of the hand above the board, stage units.
const HAND_HEIGHT := 0.9
## Where a player's quick toss and gamepad hand start: this far from the board's edge
## on their side, screen pixels (negative = just inside the edge, clear of the card
## strip under the board).
const SIDE_DISTANCE := -36.0
## Cursor acceleration (px/s²) that counts as full-strength shaking.
const FULL_SHAKE_ACCEL := 22000.0
## Shell face flips per second at full shake.
const FLIPS_PER_SECOND := 4.0
## Seconds of full shaking for `shaken` to reach 1.
const SHAKE_TO_FULL := 1.2
## Release speed (px/s) for full power; slower than MIN is a gentle drop.
const MIN_RELEASE_SPEED := 120.0
const FULL_RELEASE_SPEED := 2000.0
## Shorter, shake-free holds count as a click (a quick toss).
const CLICK_TIME := 0.2
const RESULT_HOLD := 0.85
const GATHER_TIME := 0.45
## A released throw the host never answered (rejected) is dropped after this.
const ANSWER_TIMEOUT := 4.0
## Extra board area that counts as "on the board" for starting a hold, pixels.
const HOLD_MARGIN := 40.0
const GAMEPAD_REACH := 110.0
## Seconds between live shake updates sent to the other players.
const SHAKE_SEND_INTERVAL := 0.1
## Another player's shaking hand disappears if no update arrives for this long.
const REMOTE_TIMEOUT := 1.5

## WATCHING: showing another player's hand while they shake.
enum Phase { IDLE, HOLDING, RELEASED, THROWING, GATHERING, WATCHING }

@export var game: GameManager
@export var hud: HUD

var phase: Phase = Phase.IDLE
var _enabled: bool = false
var _sim: ShellSim
var _viewport: SubViewport
var _camera: Camera3D
var _shells: Array[MeshInstance3D] = []
var _shadows: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _hand_disc: MeshInstance3D
var _pop: Label
var _rng := RandomNumberGenerator.new()

# Holding
var _by_pad: bool = false
var _hold_time: float = 0.0
var _hand_screen: Vector2
var _hand_velocity: Vector2
## The hand's recent positions and their times (the last 0.1 s), for the release velocity.
var _history: Array[Vector2] = []
var _history_times: Array[float] = []
var _energy: float = 0.0
var _shaken: float = 0.0
var _faces: Array[bool] = [false, false, false, false]
## Per shell in the hand: roll (0 = belly down, PI = open side up) and yaw.
var _roll: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _yaw: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _released_poses: Array[Transform3D] = []
var _released_at: float = 0.0
var _gather_token: int = 0
var _shake_send_timer: float = 0.0
# Watching another player's hand
var _watched_seat: int = -1
var _watched_target: Vector2
var _watched_at: float = 0.0

func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless" and game != null and hud != null
	if not _enabled:
		return
	_rng.randomize()
	_add_input_actions()
	var layer := CanvasLayer.new()
	layer.layer = 2 # above the board and HUD panels, below the card UI and overlays
	add_child(layer)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	_viewport = ShellModel.make_viewport()
	container.add_child(_viewport)
	_camera = ShellModel.make_camera(Rect2(Vector2.ZERO, ThrowGesture.SCREEN.size))
	_viewport.add_child(_camera)
	ShellModel.add_lighting(_viewport)
	_hand_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.005
	_hand_disc.mesh = disc
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(1, 1, 1, 0.16)
	_hand_disc.material_override = disc_mat
	_hand_disc.visible = false
	_viewport.add_child(_hand_disc)
	for i in 4:
		var shadow := ShellModel.make_shadow()
		_viewport.add_child(shadow)
		_shadows.append(shadow)
		var ring := ShellModel.make_ring()
		_viewport.add_child(ring)
		_rings.append(ring)
		var shell := ShellModel.make_shell()
		_viewport.add_child(shell)
		_shells.append(shell)
	_pop = Label.new()
	_pop.add_theme_font_size_override("font_size", 46)
	_pop.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_pop.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	_pop.add_theme_constant_override("outline_size", 8)
	_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop.visible = false
	layer.add_child(_pop)
	_sim = ShellSim.new(_board_ground_rect())
	_show_shells(false)
	game.turn_changed.connect(func(_p): _cancel_hold())

# --- INPUT ---
func _add_input_actions() -> void:
	var bindings := {
		"shell_hold": [_key(KEY_SPACE), _pad_button(JOY_BUTTON_A)],
		"shell_left": [_key(KEY_LEFT), _pad_axis(JOY_AXIS_LEFT_X, -1.0)],
		"shell_right": [_key(KEY_RIGHT), _pad_axis(JOY_AXIS_LEFT_X, 1.0)],
		"shell_up": [_key(KEY_UP), _pad_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"shell_down": [_key(KEY_DOWN), _pad_axis(JOY_AXIS_LEFT_Y, 1.0)],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.15)
		for event in bindings[action]:
			InputMap.action_add_event(action, event)

static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

static func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

static func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

## Is it this screen's turn to throw, with nothing else going on?
func can_throw() -> bool:
	return _enabled and hud.roll_button and not hud.roll_button.disabled and phase in [Phase.IDLE, Phase.GATHERING]

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	var press: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if press and can_throw() and _hold_area().has_point(_mouse()):
		_begin_hold(false)

func _input(event: InputEvent) -> void:
	if phase != Phase.HOLDING:
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _by_pad:
		_release()
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or event.is_action_pressed("ui_cancel"):
		_cancel_hold()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _enabled:
		return
	if phase in [Phase.IDLE, Phase.GATHERING] and Input.is_action_just_pressed("shell_hold") and can_throw():
		_begin_hold(true)
	if phase == Phase.HOLDING:
		if not hud.roll_button or hud.roll_button.disabled:
			_cancel_hold() # the turn moved on (or the screen closed) mid-shake
		elif _by_pad and not Input.is_action_pressed("shell_hold"):
			_release()
		else:
			_update_hold(delta)
	elif phase == Phase.WATCHING:
		_update_watching(delta)
	elif phase == Phase.RELEASED and Time.get_ticks_msec() / 1000.0 - _released_at > ANSWER_TIMEOUT:
		phase = Phase.IDLE # the throw was refused; nothing will come
		_show_shells(false)

func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()

# --- HOLDING AND SHAKING ---
func _begin_hold(by_pad: bool) -> void:
	_finish_gather()
	_shake_send_timer = 0.0
	phase = Phase.HOLDING
	_by_pad = by_pad
	_hold_time = 0.0
	_energy = 0.0
	_shaken = 0.0
	_hand_screen = _side_anchor(game.current_player_index) if by_pad else _mouse()
	_hand_velocity = Vector2.ZERO
	_history.clear()
	_history_times.clear()
	for i in 4:
		_faces[i] = _rng.randf() < 0.5
		_roll[i] = PI if _faces[i] else 0.0
		_yaw[i] = _rng.randf_range(-0.5, 0.5) + i * 0.5
	_show_shells(true)
	_hand_disc.visible = true
	(_hand_disc.material_override as StandardMaterial3D).albedo_color = \
		Color(game.get_player_color(game.current_player_index), 0.2)

func _update_hold(delta: float) -> void:
	_hold_time += delta
	var target := _mouse()
	if _by_pad:
		var stick := Input.get_vector("shell_left", "shell_right", "shell_up", "shell_down")
		target = _side_anchor(game.current_player_index) + stick * GAMEPAD_REACH
	var previous_velocity := _hand_velocity
	var previous := _hand_screen
	_hand_screen = _hand_screen.lerp(target, minf(1.0, delta * 20.0))
	_hand_velocity = (_hand_screen - previous) / maxf(delta, 0.0001)
	var accel := (_hand_velocity - previous_velocity).length() / maxf(delta, 0.0001)
	_energy = lerpf(_energy, clampf(accel / FULL_SHAKE_ACCEL, 0.0, 1.0), minf(1.0, delta * 6.0))
	_shaken = clampf(_shaken + _energy * delta / SHAKE_TO_FULL, 0.0, 1.0)
	_history.append(_hand_screen)
	_history_times.append(_hold_time)
	while _history_times.size() > 2 and _hold_time - _history_times[0] > 0.1:
		_history.pop_front()
		_history_times.pop_front()
	# Shaking turns shells over now and then; you can watch which way they lie
	for i in 4:
		if _rng.randf() < _energy * FLIPS_PER_SECOND * delta:
			_faces[i] = not _faces[i]
		_roll[i] = move_toward(_roll[i], PI if _faces[i] else 0.0, delta * 14.0)
		_yaw[i] += _energy * delta * _rng.randf_range(-6.0, 6.0)
	_place_hand_shells()
	_shake_send_timer -= delta
	if _shake_send_timer <= 0.0:
		_shake_send_timer = SHAKE_SEND_INTERVAL
		shake_changed.emit({"holding": true, "pos": [_hand_screen.x, _hand_screen.y],
			"energy": _energy, "faces": Array(_faces)})

func _hand_poses() -> Array[Transform3D]:
	var center := ShellModel.screen_to_ground(_hand_screen, HAND_HEIGHT)
	var poses := ShellSim.hand_poses(center, [false, false, false, false] as Array[bool], 7)
	var result: Array[Transform3D] = []
	for i in 4:
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1)) * _energy * 0.05
		var basis := Basis(Vector3.UP, _yaw[i]) * Basis(Vector3.FORWARD, _roll[i])
		result.append(Transform3D(basis, poses[i].origin + jitter))
	return result

func _place_hand_shells() -> void:
	var poses := _hand_poses()
	for i in 4:
		_shells[i].transform = poses[i]
		ShellModel.place_shadow(_shadows[i], poses[i].origin)
		_rings[i].visible = false
	_hand_disc.position = ShellModel.screen_to_ground(_hand_screen, HAND_HEIGHT - 0.1)

func _release() -> void:
	var gesture := ThrowGesture.new()
	var speed := 0.0
	var direction := Vector2.ZERO
	if _history.size() >= 2:
		var span: float = maxf(_history_times.back() - _history_times[0], 0.001)
		var velocity: Vector2 = (_history.back() - _history[0]) / span
		speed = velocity.length()
		direction = velocity.normalized()
	var board_center := _board_rect().get_center()
	if _by_pad:
		var stick := Input.get_vector("shell_left", "shell_right", "shell_up", "shell_down")
		direction = (board_center - _hand_screen).normalized().rotated(stick.x * 0.4)
		speed = lerpf(MIN_RELEASE_SPEED, FULL_RELEASE_SPEED, clampf(0.15 + _energy * 0.7, 0.0, 1.0))
	elif speed < MIN_RELEASE_SPEED:
		direction = (board_center - _hand_screen).normalized() # a gentle drop drifts inwards
	var click := not _by_pad and _hold_time < CLICK_TIME and _shaken < 0.05
	gesture.quick = click
	gesture.origin = _hand_screen
	gesture.direction = direction
	gesture.power = clampf((speed - MIN_RELEASE_SPEED) / (FULL_RELEASE_SPEED - MIN_RELEASE_SPEED), 0.0, 1.0)
	gesture.shaken = _shaken
	gesture.faces = _faces.duplicate()
	gesture.seed_value = _rng.randi()
	_released_poses.clear()
	if not click:
		_released_poses = _hand_poses()
	_released_at = Time.get_ticks_msec() / 1000.0
	phase = Phase.RELEASED
	_hand_disc.visible = false
	if click:
		_show_shells(false) # a click tosses from the player's side, like the button
	throw_released.emit(gesture)

func _cancel_hold() -> void:
	if phase != Phase.HOLDING:
		return
	phase = Phase.IDLE
	_hand_disc.visible = false
	_show_shells(false)
	shake_changed.emit({"holding": false})

# --- WATCHING ANOTHER PLAYER SHAKE ---
## Another player's live hand (from the network: every field is checked here).
func show_remote_shake(seat: int, state: Dictionary) -> void:
	if not _enabled or not phase in [Phase.IDLE, Phase.GATHERING, Phase.WATCHING]:
		return
	if state.get("holding") != true:
		if phase == Phase.WATCHING:
			_stop_watching()
		return
	var pos: Variant = state.get("pos")
	if not (pos is Array and pos.size() == 2 and (pos[0] is float or pos[0] is int) and (pos[1] is float or pos[1] is int)):
		return
	if phase != Phase.WATCHING or _watched_seat != seat:
		_finish_gather()
		phase = Phase.WATCHING
		_watched_seat = seat
		_hand_screen = Vector2(pos[0], pos[1])
		for i in 4:
			_yaw[i] = _rng.randf_range(-0.5, 0.5) + i * 0.5
		_show_shells(true)
		_hand_disc.visible = true
		(_hand_disc.material_override as StandardMaterial3D).albedo_color = Color(game.get_player_color(seat), 0.2)
	_watched_target = Vector2(pos[0], pos[1]).clamp(ThrowGesture.SCREEN.position, ThrowGesture.SCREEN.end)
	var energy: Variant = state.get("energy")
	_energy = clampf(float(energy), 0.0, 1.0) if energy is float or energy is int else 0.0
	var faces: Variant = state.get("faces")
	if faces is Array and faces.size() == 4:
		for i in 4:
			_faces[i] = faces[i] == true
	_watched_at = Time.get_ticks_msec() / 1000.0

func _update_watching(delta: float) -> void:
	if Time.get_ticks_msec() / 1000.0 - _watched_at > REMOTE_TIMEOUT or _watched_seat != game.current_player_index:
		_stop_watching()
		return
	_hand_screen = _hand_screen.lerp(_watched_target, minf(1.0, delta * 12.0))
	for i in 4:
		_roll[i] = move_toward(_roll[i], PI if _faces[i] else 0.0, delta * 14.0)
		_yaw[i] += _energy * delta * _rng.randf_range(-6.0, 6.0)
	_place_hand_shells()

func _stop_watching() -> void:
	phase = Phase.IDLE
	_watched_seat = -1
	_hand_disc.visible = false
	_show_shells(false)

# --- THE THROW ---
## Plays a decided throw by `seat` and returns once its result has been shown.
## shells: the final faces (true = open side up), already decided by the authority.
func show_throw(seat: int, gesture: ThrowGesture, shells: Array[bool]) -> void:
	if not _enabled:
		return
	var start_poses := _released_poses
	_released_poses = []
	if phase == Phase.WATCHING and _watched_seat == seat:
		start_poses = _hand_poses() # carry on from the hand everyone was watching
	_watched_seat = -1
	_finish_gather()
	phase = Phase.THROWING
	hud.roll_button.disabled = true
	_hand_disc.visible = false
	var origin := gesture.origin
	var direction := gesture.direction
	if gesture.quick or start_poses.is_empty():
		if gesture.quick or origin == Vector2.ZERO:
			origin = _side_anchor(seat)
		start_poses = ShellSim.hand_poses(ShellModel.screen_to_ground(origin, HAND_HEIGHT), gesture.faces, gesture.seed_value)
	if direction == Vector2.ZERO:
		direction = (_board_rect().get_center() - origin).normalized()
	var power := gesture.power if not gesture.quick else 0.35
	var start := ShellSim.release_state(start_poses, Vector3(direction.x, 0.0, direction.y), power, gesture.seed_value)
	var plan := _sim.plan(start, shells, gesture.seed_value)
	_show_shells(true)
	var frames: Array = plan["frames"]
	var duration := (frames.size() - 1) / ShellSim.HZ
	var t := 0.0
	while t < duration:
		_apply_frame(frames, t)
		await get_tree().process_frame
		t += get_process_delta_time()
	_apply_frame(frames, duration)
	await _show_result(frames.back(), shells)
	phase = Phase.GATHERING
	hud.shells_view.revealed = false
	_gather(frames.back(), shells) # runs on while the game carries on

func _apply_frame(frames: Array, t: float) -> void:
	var f := t * ShellSim.HZ
	var i := clampi(int(f), 0, frames.size() - 1)
	var j := mini(i + 1, frames.size() - 1)
	var w := f - i
	for s in 4:
		var a: Transform3D = frames[i][s]
		var b: Transform3D = frames[j][s]
		var pose := a.interpolate_with(b, w)
		_shells[s].transform = pose
		ShellModel.place_shadow(_shadows[s], pose.origin)
		_rings[s].visible = false

func _show_result(final: Array, shells: Array[bool]) -> void:
	var centroid := Vector3.ZERO
	for s in 4:
		var pos: Vector3 = (final[s] as Transform3D).origin
		centroid += pos / 4.0
		_rings[s].position = Vector3(pos.x, 0.01, pos.z)
		_rings[s].visible = shells[s]
	var value := CowryThrower.score(shells)
	_pop.text = {4: "Chamma! 4", 8: "Ashta! 8"}.get(value, str(value))
	_pop.visible = true
	_pop.reset_size()
	_pop.position = _camera.unproject_position(centroid + Vector3(0, 0.3, 0)) - Vector2(_pop.size.x / 2.0, 70)
	_pop.scale = Vector2.ONE * 0.6
	_pop.pivot_offset = _pop.size / 2.0
	var tween := create_tween()
	tween.tween_property(_pop, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(RESULT_HOLD).timeout
	_pop.visible = false

## Flies the resting shells into the side panel's slots, then hands over to ShellsView.
func _gather(final: Array, shells: Array[bool]) -> void:
	_gather_token += 1
	var token := _gather_token
	var slots: Array[Vector2] = hud.shells_view.slot_screen_positions()
	for s in 4:
		_rings[s].visible = false
	var t := 0.0
	while t < GATHER_TIME:
		await get_tree().process_frame
		if token != _gather_token:
			return # a new hold or throw took over
		t += get_process_delta_time()
		var k := clampf(t / GATHER_TIME, 0.0, 1.0)
		var ease_k := k * k * (3.0 - 2.0 * k)
		for s in 4:
			var from: Transform3D = final[s]
			var to := Transform3D(ShellModel.resting_basis(shells[s], 0.0),
				ShellModel.screen_to_ground(slots[s], ShellModel.rest_height(shells[s])))
			var pose := from.interpolate_with(to, ease_k)
			pose.origin.y += sin(k * PI) * 0.35
			_shells[s].transform = pose
			ShellModel.place_shadow(_shadows[s], pose.origin)
	_finish_gather()

func _finish_gather() -> void:
	_gather_token += 1
	if phase == Phase.GATHERING:
		phase = Phase.IDLE
	if hud and hud.shells_view:
		hud.shells_view.revealed = true
	if phase == Phase.IDLE:
		_show_shells(false)

# --- HELPERS ---
func _show_shells(on: bool) -> void:
	for s in _shells.size():
		_shells[s].visible = on
		_shadows[s].visible = on
		if not on:
			_rings[s].visible = false

func _board_rect() -> Rect2:
	return Rect2(game.board.global_position, Vector2.ONE * game.board.get_extent())

func _board_ground_rect() -> Rect2:
	var rect := _board_rect()
	return Rect2(rect.position * ShellModel.UNITS_PER_PIXEL, rect.size * ShellModel.UNITS_PER_PIXEL)

func _hold_area() -> Rect2:
	return _board_rect().grow(HOLD_MARGIN)

## The middle of the board side where `seat` sits (their quick tosses start here).
func _side_anchor(seat: int) -> Vector2:
	var rect := _board_rect()
	var c := rect.get_center()
	var half := rect.size.x / 2.0 + SIDE_DISTANCE
	match game.player_seats[seat] if seat < game.player_seats.size() else 0:
		1: return c + Vector2(half, 0)
		2: return c + Vector2(0, -half)
		3: return c + Vector2(-half, 0)
	return c + Vector2(0, half)
