class_name ShellStage
extends Node

## The cowry shells on the 3D board (BoardView3D's world): resting by the thrower, held
## and shaken, thrown, the result, and the chalked tally of this turn's throws.
##   Mouse / touch: hold on the board (or on your shells), shake, then flick and let go.
##     The flick's direction and speed set the throw; letting go without a flick is a
##     gentle drop (the best release for skill throws). A short click is a quick toss.
##   Gamepad / keyboard: hold A or Space, shake with the left stick or arrows, let go.
## Emits throw_released(gesture); MatchController turns it into a THROW intent, and once
## the throw is decided (by the host, online) awaits show_throw(), which plans a flight
## landing on exactly those faces (ShellSim), plays it, holds the result, then gathers the
## shells back to the thrower's spot. Positions are board-plane units (ThrowGesture.AREA),
## so every screen replays the same throw from its own side.
## Online, the hand is streamed while shaking (shake_changed) and other players' hands
## are shown (show_remote_shake). A view: it never changes the game. Headless: off.

signal throw_released(gesture: ThrowGesture)
## This screen's hand while shaking, about 10 times a second ({holding: false} = put down).
signal shake_changed(state: Dictionary)

## Height of the hand above the board, board units.
const HAND_HEIGHT := 0.9
## Where each seat's shells rest, beside their board edge on their right, for the bottom
## seat (other seats: turned round the board).
const REST_SPOT := Vector3(3.3, 0.0, 1.6)
## The chalk tally of this turn's throws, above the resting shells.
const TALLY_START := Vector3(2.95, 0.0, 0.9)
const TALLY_STEP := 0.3
const TALLY_PER_ROW := 4
const CHALK := Color(0.96, 0.94, 0.88, 0.92)
## Quick tosses and the gamepad hand start this far inside the thrower's board edge.
const SIDE_INSET := 0.55
## Hand acceleration (units/s²) that counts as full-strength shaking.
const FULL_SHAKE_ACCEL := 220.0
const FLIPS_PER_SECOND := 4.0
## Seconds of full shaking for `shaken` to reach 1.
const SHAKE_TO_FULL := 1.2
## Flick speed (units/s) for full power; slower than MIN is a gentle drop.
const MIN_RELEASE_SPEED := 1.4
const FULL_RELEASE_SPEED := 14.0
## Shorter, shake-free holds count as a click (a quick toss).
const CLICK_TIME := 0.2
## Let go of the shells this close to their spot (board units) and they're put down, not thrown.
const DROP_RADIUS := 0.55
const RESULT_HOLD := 0.85
const GATHER_TIME := 0.5
const LIFT_TIME := 0.18
## A released throw the host never answered (rejected) is dropped after this.
const ANSWER_TIMEOUT := 4.0
## How far off the board (or from your shells) a press still starts a hold.
const HOLD_MARGIN := 0.6
const GAMEPAD_REACH := 1.1
const SHAKE_SEND_INTERVAL := 0.1
const REMOTE_TIMEOUT := 1.5

## WATCHING: showing another player's hand while they shake.
enum Phase { IDLE, HOLDING, RELEASED, THROWING, GATHERING, WATCHING }

@export var game: GameManager
@export var hud: HUD
## The 3D board: the shells live in its world and use its camera.
@export var view: BoardView3D

var phase: Phase = Phase.IDLE
var _enabled: bool = false
var _sim: ShellSim
var _shells: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _pop: Label
var _rng := RandomNumberGenerator.new()
## The seat whose spot the shells rest at (the current thrower).
var _resting_seat := 0
var _rest_poses: Array[Transform3D] = []
var _tally: Array[Node] = []
## Throws chalked up so far this turn (a new one makes a chalk sound).
var _tally_count := 0

# Holding
var _by_pad: bool = false
var _hold_time: float = 0.0
var _hand: Vector2
var _hand_velocity: Vector2
## The pointer's latest screen position, from its own events (works for touch and for
## injected input, unlike asking the OS where the cursor is).
var _pointer_screen: Vector2
## The hand's recent positions and their times (the last 0.1 s), for the flick.
var _history: Array[Vector2] = []
var _history_times: Array[float] = []
var _energy: float = 0.0
var _drop_ring: MeshInstance3D
var _shaken: float = 0.0
var _faces: Array[bool] = [false, false, false, false]
## Per shell in the hand: roll (0 = belly down, PI = open side up) and yaw.
var _roll: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _yaw: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lift: float = 0.0
var _released_poses: Array[Transform3D] = []
var _released_at: float = 0.0
var _move_token: int = 0
var _shake_send_timer: float = 0.0
# Watching another player's hand
var _watched_seat: int = -1
var _watched_target: Vector2
var _watched_at: float = 0.0

func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless" and game != null and hud != null and view != null
	if not _enabled:
		return
	_rng.randomize()
	GameInput.ensure(get_tree())
	for i in 4:
		var ring := ShellModel.make_ring()
		ring.visible = false
		view.add_child(ring)
		_rings.append(ring)
		var shell := ShellModel.make_shell()
		view.add_child(shell)
		_shells.append(shell)
	var layer := CanvasLayer.new()
	layer.layer = 2 # above the board and HUD panels, below the card UI and overlays
	add_child(layer)
	_pop = Label.new()
	_pop.add_theme_font_override("font", GameFonts.title())
	_pop.add_theme_font_size_override("font_size", 50)
	_pop.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_pop.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	_pop.add_theme_constant_override("outline_size", 10)
	_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop.visible = false
	layer.add_child(_pop)
	var half := game.board.board_data.get_grid_size() / 2.0
	_sim = ShellSim.new(Rect2(-half, -half, half * 2.0, half * 2.0))
	game.turn_changed.connect(_on_turn_changed)
	game.throw_pool_changed.connect(_on_pool_changed)
	game.setup_done.connect(func(): _rest_at(game.current_player_index, false))
	game.snapshot_loaded.connect(func(): _rest_at(game.current_player_index, false))
	if not game.players.is_empty():
		_rest_at(game.current_player_index, false)

# --- INPUT (actions: GameInput) ---
## Is it this screen's turn to throw, with nothing else going on?
func can_throw() -> bool:
	return _enabled and hud.throw_allowed and phase in [Phase.IDLE, Phase.GATHERING]

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	var press: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if press and can_throw():
		var at: Variant = _pointer(event.position)
		if at != null and _can_hold_at(at):
			_pointer_screen = event.position
			_begin_hold(false)
			get_viewport().set_input_as_handled()
	# Space / pad A, unless another view used the press (the card hand, a menu)
	elif event.is_action_pressed("shell_hold") and can_throw():
		_begin_hold(true)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_screen = event.position
	if phase != Phase.HOLDING:
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _by_pad:
		_release()
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or event.is_action_pressed("pick_cancel"):
		_cancel_hold()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _enabled:
		return
	if phase == Phase.HOLDING:
		if not hud.throw_allowed:
			_cancel_hold() # the turn moved on (or the screen closed) mid-shake
		elif _by_pad and not Input.is_action_pressed("shell_hold"):
			_release()
		else:
			_update_hold(delta)
	elif phase == Phase.WATCHING:
		_update_watching(delta)
	elif phase == Phase.RELEASED and Time.get_ticks_msec() / 1000.0 - _released_at > ANSWER_TIMEOUT:
		phase = Phase.IDLE # the throw was refused; nothing will come
		_rest_at(_resting_seat, true)

## The pointer on the board plane at hand height (board units), or null.
func _pointer(screen: Vector2) -> Variant:
	var cam := view.camera
	var hit: Variant = Plane(Vector3.UP, HAND_HEIGHT).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	return Vector2(hit.x, hit.z) if hit != null else null

func _can_hold_at(at: Vector2) -> bool:
	var spot := _spot(_resting_seat)
	return _board_area().grow(HOLD_MARGIN).has_point(at) or at.distance_to(Vector2(spot.x, spot.z)) < HOLD_MARGIN + 0.3

# --- HOLDING AND SHAKING ---
func _begin_hold(by_pad: bool) -> void:
	_move_token += 1
	_clear_rings()
	_shake_send_timer = 0.0
	phase = Phase.HOLDING
	_by_pad = by_pad
	_hold_time = 0.0
	_lift = 0.0
	_energy = 0.0
	_shaken = 0.0
	var mouse: Variant = _pointer(_pointer_screen)
	_hand = _side_anchor(game.current_player_index) if by_pad or mouse == null else _clamp_hand(mouse)
	_show_drop_spot(not by_pad)
	hud.set_hint(GameInput.pick(
		"Shake, then flick and let go to throw. Changed your mind? Let go over the ringed spot (or right-click).",
		"Shake, then flick and let go to throw. Changed your mind? Let go over the ringed spot.",
		"Shake with the stick / arrows, let go to throw. B / Esc puts them down."))
	_hand_velocity = Vector2.ZERO
	_history.clear()
	_history_times.clear()
	_rest_poses = _current_poses()
	for i in 4:
		_faces[i] = ShellModel.is_open_up(_shells[i].basis)
		_roll[i] = PI if _faces[i] else 0.0
		_yaw[i] = _rng.randf_range(-0.5, 0.5) + i * 0.5

func _update_hold(delta: float) -> void:
	_hold_time += delta
	_lift = minf(1.0, _lift + delta / LIFT_TIME)
	var target := _hand
	if _by_pad:
		var stick := Input.get_vector("shell_left", "shell_right", "shell_up", "shell_down")
		target = _side_anchor(game.current_player_index) + _to_board_dir(stick) * GAMEPAD_REACH
	else:
		var mouse: Variant = _pointer(_pointer_screen)
		if mouse != null:
			target = _clamp_hand(mouse)
	var previous_velocity := _hand_velocity
	var previous := _hand
	_hand = _hand.lerp(target, minf(1.0, delta * 20.0))
	_hand_velocity = (_hand - previous) / maxf(delta, 0.0001)
	var accel := (_hand_velocity - previous_velocity).length() / maxf(delta, 0.0001)
	_energy = lerpf(_energy, clampf(accel / FULL_SHAKE_ACCEL, 0.0, 1.0), minf(1.0, delta * 6.0))
	_shaken = clampf(_shaken + _energy * delta / SHAKE_TO_FULL, 0.0, 1.0)
	_rattle(delta, 0.0)
	# The flick is read from the pointer itself (not the smoothed hand), so it's sharp
	var raw: Vector2 = target
	_history.append(raw)
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
		shake_changed.emit({"holding": true, "pos": [_hand.x, _hand.y], "energy": _energy, "faces": Array(_faces)})

func _hand_poses() -> Array[Transform3D]:
	var center := Vector3(_hand.x, HAND_HEIGHT, _hand.y)
	var poses := ShellSim.hand_poses(center, [false, false, false, false] as Array[bool], 7)
	var result: Array[Transform3D] = []
	for i in 4:
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1)) * _energy * 0.05
		var basis := Basis(Vector3.UP, _yaw[i]) * Basis(Vector3.FORWARD, _roll[i])
		result.append(Transform3D(basis, poses[i].origin + jitter))
	return result

## In the hand (rising off the resting spot when a hold starts).
func _place_hand_shells() -> void:
	var poses := _hand_poses()
	var k := _lift * _lift * (3.0 - 2.0 * _lift)
	for i in 4:
		var pose := poses[i]
		if k < 1.0 and i < _rest_poses.size():
			pose = _rest_poses[i].interpolate_with(pose, k)
		_shells[i].transform = pose

func _release() -> void:
	if not _by_pad and _hold_time >= CLICK_TIME and _over_drop_spot():
		_cancel_hold() # dropped back on their spot: put down, not thrown
		return
	_show_drop_spot(false)
	var gesture := ThrowGesture.new()
	var speed := 0.0
	var direction := Vector2.ZERO
	if _history.size() >= 2:
		var span: float = maxf(_history_times.back() - _history_times[0], 0.001)
		var velocity: Vector2 = (_history.back() - _history[0]) / span
		speed = velocity.length()
		direction = velocity.normalized()
	if _by_pad:
		var stick := Input.get_vector("shell_left", "shell_right", "shell_up", "shell_down")
		direction = (-_hand).normalized().rotated(stick.x * 0.4)
		speed = lerpf(MIN_RELEASE_SPEED, FULL_RELEASE_SPEED, clampf(0.15 + _energy * 0.7, 0.0, 1.0))
	elif speed < MIN_RELEASE_SPEED:
		direction = (-_hand).normalized() # no flick: a gentle drop drifting to the middle
	var click := not _by_pad and _hold_time < CLICK_TIME and _shaken < 0.05
	gesture.quick = click
	gesture.origin = _hand
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
	throw_released.emit(gesture)

func _cancel_hold() -> void:
	if phase != Phase.HOLDING:
		return
	phase = Phase.IDLE
	_show_drop_spot(false)
	hud.set_hint(HUD.throw_hint())
	_rest_at(_resting_seat, true)

## While holding: a chalk ring on the shells' spot. Let go over it to put them down.
func _show_drop_spot(on: bool) -> void:
	if on and _drop_ring == null:
		var spot := _spot(_resting_seat)
		_drop_ring = CardFx.chalk_mark(view, Vector3(spot.x, 0.004, spot.z), Color(0.95, 0.93, 0.85), true, 0.3)
		_drop_ring.scale = Vector3.ONE * DROP_RADIUS * 2.2
	elif not on and _drop_ring != null:
		_drop_ring.queue_free()
		_drop_ring = null

## Is the pointer over the shells' own spot (letting go there puts them down)? The
## pointer, not the hand: the hand stays over the board, and the spot is beside it.
func _over_drop_spot() -> bool:
	var spot := _spot(_resting_seat)
	var at: Variant = _pointer(_pointer_screen)
	return at != null and (at as Vector2).distance_to(Vector2(spot.x, spot.z)) < DROP_RADIUS
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
	var at := Vector2(pos[0], pos[1]).clamp(ThrowGesture.AREA.position, ThrowGesture.AREA.end)
	if phase != Phase.WATCHING or _watched_seat != seat:
		_move_token += 1
		_clear_rings()
		phase = Phase.WATCHING
		_watched_seat = seat
		_hand = at
		_lift = 0.0
		_rest_poses = _current_poses()
		for i in 4:
			_yaw[i] = _rng.randf_range(-0.5, 0.5) + i * 0.5
	_watched_target = at
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
	_rattle(delta, -5.0) # someone else's shaking, a little quieter
	_lift = minf(1.0, _lift + delta / LIFT_TIME)
	_hand = _hand.lerp(_watched_target, minf(1.0, delta * 12.0))
	for i in 4:
		_roll[i] = move_toward(_roll[i], PI if _faces[i] else 0.0, delta * 14.0)
		_yaw[i] += _energy * delta * _rng.randf_range(-6.0, 6.0)
	_place_hand_shells()

func _stop_watching() -> void:
	phase = Phase.IDLE
	_watched_seat = -1
	_rest_at(_resting_seat, true)

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
	_move_token += 1
	_clear_rings()
	phase = Phase.THROWING
	var origin := gesture.origin
	var direction := gesture.direction
	if gesture.quick or start_poses.is_empty():
		if gesture.quick or origin == Vector2.ZERO:
			origin = _side_anchor(seat)
		start_poses = ShellSim.hand_poses(Vector3(origin.x, HAND_HEIGHT, origin.y), gesture.faces, gesture.seed_value)
		# The shells lift off the thrower's spot into the toss
		await _move_shells(_current_poses(), start_poses, LIFT_TIME * 1.5, 0.2)
	if direction == Vector2.ZERO:
		direction = (-origin).normalized()
	var power := gesture.power if not gesture.quick else 0.35
	var start := ShellSim.release_state(start_poses, Vector3(direction.x, 0.0, direction.y), power, gesture.seed_value)
	var plan := _sim.plan(start, shells, gesture.seed_value)
	var frames: Array = plan["frames"]
	var duration := (frames.size() - 1) / ShellSim.HZ
	var hits := _impacts(frames)
	Sound.play(&"shell_throw", lerpf(-8.0, 0.0, power))
	var t := 0.0
	while t < duration:
		_apply_frame(frames, t)
		while not hits.is_empty() and hits[0][0] <= t:
			var hit: Array = hits.pop_front()
			Sound.play(hit[1], hit[2])
		await get_tree().process_frame
		t += get_process_delta_time()
	_apply_frame(frames, duration)
	await _show_result(frames.back(), shells)
	phase = Phase.GATHERING
	_resting_seat = seat
	_gather(shells) # runs on while the game carries on

func _apply_frame(frames: Array, t: float) -> void:
	var f := t * ShellSim.HZ
	var i := clampi(int(f), 0, frames.size() - 1)
	var j := mini(i + 1, frames.size() - 1)
	var w := f - i
	for s in 4:
		var a: Transform3D = frames[i][s]
		var b: Transform3D = frames[j][s]
		_shells[s].transform = a.interpolate_with(b, w)

func _show_result(final: Array, shells: Array[bool]) -> void:
	var centroid := Vector3.ZERO
	for s in 4:
		var pos: Vector3 = (final[s] as Transform3D).origin
		centroid += pos / 4.0
		_rings[s].position = Vector3(pos.x, 0.01, pos.z)
		_rings[s].visible = shells[s]
	var value := CowryThrower.score(shells)
	if value in [4, 8]:
		Sound.play(&"throw_chamma" if value == 4 else &"throw_ashta")
	_pop.text = {4: "Chamma! 4", 8: "Ashta! 8"}.get(value, str(value))
	_pop.visible = true
	_pop.reset_size()
	_pop.position = view.camera.unproject_position(centroid + Vector3(0, 0.3, 0)) - Vector2(_pop.size.x / 2.0, 80)
	_pop.scale = Vector2.ONE * 0.6
	_pop.pivot_offset = _pop.size / 2.0
	var tween := create_tween()
	tween.tween_property(_pop, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(RESULT_HOLD).timeout
	_pop.visible = false

## The shells hop back, one after another, to rest by the thrower (as they landed).
func _gather(shells: Array[bool]) -> void:
	_clear_rings()
	var to: Array[Transform3D] = []
	for s in 4:
		to.append(_rest_pose(_resting_seat, s, shells[s]))
	await _move_shells(_current_poses(), to, GATHER_TIME, 0.3)
	Sound.play(&"shell_click", -14.0)
	Sound.play(&"shell_click", -16.0, 0.05)
	if phase == Phase.GATHERING:
		phase = Phase.IDLE

## Moves the shells to `seat`'s spot (keeping how they lie): at a turn change, or after
## a cancelled hold.
func _rest_at(seat: int, animate: bool) -> void:
	_resting_seat = seat
	var to: Array[Transform3D] = []
	for s in 4:
		to.append(_rest_pose(seat, s, ShellModel.is_open_up(_shells[s].basis)))
	if animate:
		_move_shells(_current_poses(), to, GATHER_TIME, 0.3)
	else:
		_move_token += 1
		for s in 4:
			_shells[s].transform = to[s]

## Glides the shells from `from` to `to` in a little arc. Another move starting cancels it.
func _move_shells(from: Array[Transform3D], to: Array[Transform3D], seconds: float, height: float) -> void:
	_move_token += 1
	var token := _move_token
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if token != _move_token:
			return
		t += get_process_delta_time()
		for s in 4:
			var k := clampf((t - s * 0.04) / maxf(seconds - 0.12, 0.01), 0.0, 1.0)
			var eased := k * k * (3.0 - 2.0 * k)
			var pose := from[s].interpolate_with(to[s], eased)
			pose.origin.y += sin(k * PI) * height
			_shells[s].transform = pose
	for s in 4:
		_shells[s].transform = to[s]

func _current_poses() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for shell in _shells:
		poses.append(shell.transform)
	return poses

# --- THE TALLY ---
func _on_turn_changed(player: int) -> void:
	_cancel_hold()
	_clear_tally()
	if phase in [Phase.IDLE, Phase.GATHERING]:
		_rest_at(player, true)

## This turn's throws, chalked on the mud above the thrower's shells: the throw to be
## used next circled, throws that couldn't be used struck through.
func _on_pool_changed(pool: Array[int], exhausted: Array[int], selected: int) -> void:
	if not _enabled:
		return
	_clear_tally()
	var seat := game.current_player_index
	var entries: Array = []
	for i in pool.size():
		entries.append([pool[i], i == selected, false])
	for value in exhausted:
		entries.append([value, false, true])
	if entries.size() > _tally_count:
		Sound.play(&"chalk", -2.0, 0.2) # a new throw chalked up
	_tally_count = entries.size()
	for n in entries.size():
		var at := _turned(seat, TALLY_START + Vector3((n % TALLY_PER_ROW) * TALLY_STEP, 0.0, -floorf(n / float(TALLY_PER_ROW)) * 0.36))
		var label := Label3D.new()
		label.text = str(entries[n][0])
		label.font = GameFonts.chalk()
		label.font_size = 120
		label.pixel_size = 0.0028
		label.outline_size = 0
		label.modulate = CHALK if not entries[n][2] else Color(CHALK, 0.45)
		label.double_sided = true
		label.position = at + Vector3.UP * 0.006
		label.rotation = Vector3(-PI / 2.0, _seat_yaw(seat), 0)
		view.add_child(label)
		_tally.append(label)
		if entries[n][2]: # struck through
			var strike := Label3D.new()
			strike.text = "/"
			strike.font = GameFonts.chalk()
			strike.font_size = 130
			strike.pixel_size = 0.0028
			strike.outline_size = 0
			strike.modulate = CHALK
			strike.double_sided = true
			strike.position = label.position + Vector3.UP * 0.001
			strike.rotation = label.rotation
			view.add_child(strike)
			_tally.append(strike)
		if entries[n][1]:
			var ring := CardFx.chalk_mark(view, at - Vector3.UP * 0.003, Color(1.0, 0.85, 0.4), true, 0.3)
			ring.scale = Vector3.ONE * 0.42
			_tally.append(ring)

func _clear_tally() -> void:
	for node in _tally:
		if is_instance_valid(node):
			node.queue_free()
	_tally.clear()
	_tally_count = 0

# --- SOUND ---
## Shells knocking together in the hand: more often and louder the harder the shake.
func _rattle(delta: float, volume_db: float) -> void:
	if randf() < (0.5 + _energy * 28.0) * delta:
		Sound.play(&"shell_click", lerpf(-16.0, -3.0, _energy) + volume_db)

## The moments in a planned throw that make a sound: a shell coming down on the ground
## (louder the harder it lands) or two shells knocking together. [time, id, volume_db],
## in time order. The plan is the same on every screen, so everyone hears the same throw.
static func _impacts(frames: Array) -> Array:
	var hits: Array = []
	var last_hit: Array[float] = [-1.0, -1.0, -1.0, -1.0]
	var touch := ShellSim.SHELL_RADIUS * 2.2
	for f in range(2, frames.size()):
		var t := f / ShellSim.HZ
		for s in 4:
			var y0: float = (frames[f - 2][s] as Transform3D).origin.y
			var y1: float = (frames[f - 1][s] as Transform3D).origin.y
			var y2: float = (frames[f][s] as Transform3D).origin.y
			var falling := (y1 - y0) * ShellSim.HZ
			var now := (y2 - y1) * ShellSim.HZ
			if falling < -0.5 and now > falling * 0.4 and y1 < 0.12 and t - last_hit[s] > 0.08:
				last_hit[s] = t
				hits.append([t, &"shell_land", lerpf(-18.0, 0.0, clampf(-falling / 4.0, 0.0, 1.0))])
		for a in 4:
			for b in range(a + 1, 4):
				var before: float = (frames[f - 1][a] as Transform3D).origin.distance_to((frames[f - 1][b] as Transform3D).origin)
				var after: float = (frames[f][a] as Transform3D).origin.distance_to((frames[f][b] as Transform3D).origin)
				if after < touch and before >= touch:
					var closing := (before - after) * ShellSim.HZ
					hits.append([t, &"shell_click", lerpf(-16.0, -2.0, clampf(closing / 2.0, 0.0, 1.0))])
	hits.sort_custom(func(x: Array, y: Array): return x[0] < y[0])
	return hits

# --- HELPERS ---
## The four shell meshes (read only: for effects such as a card making them glow).
func shell_nodes() -> Array[MeshInstance3D]:
	return _shells.duplicate()

func _clear_rings() -> void:
	for ring in _rings:
		ring.visible = false

## The board's own area on the plane (board units).
func _board_area() -> Rect2:
	var half := game.board.board_data.get_grid_size() / 2.0
	return Rect2(-half, -half, half * 2.0, half * 2.0)

## The hand stays over the board (the shells are thrown onto it).
func _clamp_hand(at: Vector2) -> Vector2:
	var area := _board_area().grow(-0.3)
	return at.clamp(area.position, area.end)

func _seat_yaw(seat: int) -> float:
	var side: int = game.player_seats[seat] if seat < game.player_seats.size() else 0
	return deg_to_rad(side * 90.0)

## A bottom-seat position turned round to `seat`'s side of the board.
func _turned(seat: int, point: Vector3) -> Vector3:
	return Basis(Vector3.UP, _seat_yaw(seat)) * point

func _spot(seat: int) -> Vector3:
	return _turned(seat, REST_SPOT)

## Shell i resting in its little group at `seat`'s spot.
func _rest_pose(seat: int, i: int, open_up: bool) -> Transform3D:
	var offset := Vector3((i % 2 - 0.5) * 0.3 + floorf(i / 2.0) * 0.05, 0.0, (floorf(i / 2.0) - 0.5) * 0.26)
	var at := _spot(seat) + Basis(Vector3.UP, _seat_yaw(seat)) * offset
	return Transform3D(ShellModel.resting_basis(open_up, _seat_yaw(seat) + i * 1.3), at + Vector3.UP * ShellModel.rest_height(open_up))

## Just inside the middle of `seat`'s board edge (quick tosses and the gamepad hand).
func _side_anchor(seat: int) -> Vector2:
	var half := game.board.board_data.get_grid_size() / 2.0 - SIDE_INSET
	var at := _turned(seat, Vector3(0.0, 0.0, half))
	return Vector2(at.x, at.z)

## A stick / arrow-key direction on screen, as seen from this screen's side, on the board.
func _to_board_dir(stick: Vector2) -> Vector2:
	var yaw := deg_to_rad(view.camera.rotation_degrees.y) if view.camera else 0.0
	return stick.rotated(-yaw)
