class_name ShellSim
extends RefCounted

## A small rigid-body simulation of the four shells landing on the board, written for
## one job: plan(), which finds a natural-looking throw that comes to rest on faces
## decided beforehand (the host decides every throw; see ThrowGesture).
## It is pure GDScript and steps instantly, so a throw can be simulated, checked and
## retried with slightly different spins before anyone sees it, then played back.
## Each shell's hull is a handful of contact points (ShellModel.hull_points) with
## impulse-based ground contact and friction; walls keep shells on the board, and
## shells push each other apart as spheres.

const HZ := 120.0
const DT := 1.0 / HZ
const MAX_TIME := 2.6
## Game gravity in stage units/s² (1 unit = 100 px): slower than real, so a throw reads.
const GRAVITY := 14.0
const RESTITUTION := 0.32
## Below this impact speed a contact doesn't bounce (stops endless micro-bounces).
const BOUNCE_MIN_SPEED := 0.45
const FRICTION := 0.5
const AIR_DRAG := 0.08
const AIR_SPIN_DRAG := 0.25
## Rolling resistance while touching the ground.
const GROUND_DRAG := 1.4
const GROUND_SPIN_DRAG := 2.6
const SHELL_RADIUS := 0.15
const WALL_BOUNCE := 0.45
const REST_SPEED := 0.04
const REST_SPIN := 0.4
const REST_TIME := 0.12
## A slow shell lying (nearly) flat is damped hard, so contact jitter on its flat belly
## can't keep it wobbling forever. Only when flat: a shell on its edge must roll over.
const SETTLE_SPEED := 0.15
const SETTLE_SPIN := 1.2
const SETTLE_DAMPING := 0.88
## How flat counts as lying flat (|up axis · vertical|).
const FLAT := 0.9
## Re-simulations allowed before falling back to a little settling hop.
const MAX_TRIES := 24
const HOP_TIME := 0.4
const HOP_HEIGHT := 0.2

## Where shells may be, on the ground plane (x, z in stage units).
var bounds: Rect2

var _hull: PackedVector3Array
var _inv_inertia: Vector3
## Lowest a hull point can be below the shell's centre (cheap "near the ground?" check).
var _reach: float

class Body:
	var p: Vector3
	var q: Quaternion
	var v: Vector3
	var w: Vector3
	var asleep: bool = false
	var rest_time: float = 0.0

func _init(area: Rect2) -> void:
	bounds = area
	_hull = ShellModel.hull_points()
	var a := ShellModel.WIDTH / 2.0
	var h := (ShellModel.DOME + ShellModel.BELLY) / 2.0
	var c := ShellModel.LENGTH / 2.0
	# Solid ellipsoid, unit mass
	_inv_inertia = Vector3(5.0 / (h * h + c * c), 5.0 / (a * a + c * c), 5.0 / (a * a + h * h))
	_reach = 0.0
	for point in _hull:
		_reach = maxf(_reach, point.length())

## Where the shells sit in a hand at `center`: a loose 2x2 spread (far enough apart
## that every face can be read while shaking), each lying on its face from `faces`,
## turned a little by `seed_value`.
static func hand_poses(center: Vector3, faces: Array[bool], seed_value: int) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var offsets := [Vector3(-0.17, 0.0, -0.13), Vector3(0.17, 0.02, -0.12), Vector3(-0.15, 0.04, 0.15), Vector3(0.16, 0.03, 0.14)]
	var poses: Array[Transform3D] = []
	for i in faces.size():
		var basis := ShellModel.resting_basis(faces[i], rng.randf_range(-0.6, 0.6) + i * 0.4)
		poses.append(Transform3D(basis, center + offsets[i % offsets.size()]))
	return poses

## The moment of release: shells leave `hand` towards `direction` (on the ground plane)
## with speed and spin from `power` 0..1; `seed_value` varies each shell a little.
static func release_state(hand: Array[Transform3D], direction: Vector3, power: float, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	var state: Array = []
	for pose in hand:
		var dir := flat.rotated(Vector3.UP, rng.randf_range(-0.25, 0.25))
		var speed := lerpf(1.0, 4.2, power) * rng.randf_range(0.88, 1.12)
		var v := dir * speed + Vector3.UP * lerpf(0.8, 2.2, power) * rng.randf_range(0.9, 1.1)
		var spin := lerpf(4.0, 22.0, power) * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.8, 1.2)
		var wobble := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * lerpf(1.0, 6.0, power)
		state.append({"p": pose.origin, "basis": pose.basis, "v": v, "w": pose.basis.z * spin + wobble})
	return state

## start: one {p: Vector3, basis: Basis, v: Vector3, w: Vector3} per shell.
## Returns {frames: Array (per step: Array[Transform3D], one per shell), faces: Array[bool],
## tries: int, hopped: Array[int]} where the last frame rests on `targets`.
func plan(start: Array, targets: Array[bool], seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state := start.duplicate(true)
	var best: Dictionary = {}
	var best_wrong := 99
	for attempt in MAX_TRIES:
		var result := simulate(state)
		var wrong: Array[int] = []
		for i in targets.size():
			if result["faces"][i] != targets[i]:
				wrong.append(i)
		if wrong.size() < best_wrong:
			best_wrong = wrong.size()
			best = result
			best["tries"] = attempt + 1
		if wrong.is_empty():
			best["hopped"] = [] as Array[int]
			return best
		# Same throw, a little more or less spin on the shells that landed wrong. The
		# nudges grow with each try: a gentle drop barely turns, so it may need more.
		var reach := 1.0 + attempt * 0.2
		for i in wrong:
			var entry: Dictionary = state[i]
			var long_axis: Vector3 = (entry["basis"] as Basis).z
			entry["w"] += long_axis * rng.randf_range(2.5, 6.0) * reach * (1.0 if rng.randf() < 0.5 else -1.0)
			entry["v"] *= rng.randf_range(0.94, 1.06)
			entry["v"].y += rng.randf_range(0.0, 0.08) * reach
	# Rare: settle the stubborn shells with a little hop and flip
	var hopped: Array[int] = []
	for i in targets.size():
		if best["faces"][i] != targets[i]:
			hopped.append(i)
	_append_hops(best, hopped, targets)
	best["hopped"] = hopped
	return best

## Runs one throw from `start` until every shell rests (or MAX_TIME).
func simulate(start: Array) -> Dictionary:
	var bodies: Array[Body] = []
	for entry in start:
		var body := Body.new()
		body.p = entry["p"]
		body.q = (entry["basis"] as Basis).get_rotation_quaternion()
		body.v = entry["v"]
		body.w = entry["w"]
		bodies.append(body)
	var frames: Array = [_frame(bodies)]
	var steps := int(MAX_TIME * HZ)
	for step in steps:
		_step(bodies)
		frames.append(_frame(bodies))
		if bodies.all(func(b: Body): return b.asleep):
			break
	var faces: Array[bool] = []
	for body in bodies:
		faces.append(ShellModel.is_open_up(Basis(body.q)))
	return {"frames": frames, "faces": faces}

func _frame(bodies: Array[Body]) -> Array:
	var frame: Array = []
	for body in bodies:
		frame.append(Transform3D(Basis(body.q), body.p))
	return frame

func _step(bodies: Array[Body]) -> void:
	for body in bodies:
		if body.asleep:
			continue
		body.v.y -= GRAVITY * DT
		body.v *= 1.0 - AIR_DRAG * DT
		body.w *= 1.0 - AIR_SPIN_DRAG * DT
		body.p += body.v * DT
		var turn := body.w * DT
		if turn.length_squared() > 1e-12:
			body.q = (Quaternion(turn.normalized(), turn.length()) * body.q).normalized()
		_ground(body)
		_walls(body)
	_shell_contacts(bodies)
	for body in bodies:
		_check_rest(body)

## Impulse contact with the ground for every hull point below it.
func _ground(body: Body) -> void:
	if body.p.y > _reach:
		return # nowhere near the ground
	var basis := Basis(body.q)
	var deepest := 0.0
	var touching := false
	for local in _hull:
		var r := basis * local
		var depth := -(body.p.y + r.y)
		if depth <= 0.0:
			continue
		touching = true
		deepest = maxf(deepest, depth)
		var vp := body.v + body.w.cross(r)
		var vn := vp.y
		if vn >= 0.0:
			continue
		var n := Vector3.UP
		var e := RESTITUTION if -vn > BOUNCE_MIN_SPEED else 0.0
		var jn := -(1.0 + e) * vn / _effective_mass(basis, r, n)
		_apply(body, basis, r, n * jn)
		# Friction against the sliding direction, capped by the normal impulse
		vp = body.v + body.w.cross(r)
		var vt := Vector3(vp.x, 0.0, vp.z)
		var speed := vt.length()
		if speed > 1e-5:
			var t := vt / speed
			var jt := minf(speed / _effective_mass(basis, r, t), FRICTION * jn)
			_apply(body, basis, r, -t * jt)
	if touching:
		body.p.y += deepest * 0.8 # push out of the ground
		body.v *= 1.0 - GROUND_DRAG * DT
		body.w *= 1.0 - GROUND_SPIN_DRAG * DT
		if absf(basis.y.y) > FLAT and body.v.length() < SETTLE_SPEED and body.w.length() < SETTLE_SPIN:
			body.v *= SETTLE_DAMPING
			body.w *= SETTLE_DAMPING

func _effective_mass(basis: Basis, r: Vector3, n: Vector3) -> float:
	var rn := r.cross(n)
	return 1.0 + n.dot(_inv_inertia_world(basis, rn).cross(r))

func _inv_inertia_world(basis: Basis, x: Vector3) -> Vector3:
	var local := basis.transposed() * x
	return basis * Vector3(local.x * _inv_inertia.x, local.y * _inv_inertia.y, local.z * _inv_inertia.z)

func _apply(body: Body, basis: Basis, r: Vector3, impulse: Vector3) -> void:
	body.v += impulse
	body.w += _inv_inertia_world(basis, r.cross(impulse))

## The board's edges: shells bounce back in, losing some speed and spin.
func _walls(body: Body) -> void:
	var min_x := bounds.position.x + SHELL_RADIUS
	var max_x := bounds.end.x - SHELL_RADIUS
	var min_z := bounds.position.y + SHELL_RADIUS
	var max_z := bounds.end.y - SHELL_RADIUS
	if body.p.x < min_x or body.p.x > max_x:
		body.p.x = clampf(body.p.x, min_x, max_x)
		body.v.x = -body.v.x * WALL_BOUNCE
		body.w *= 0.8
	if body.p.z < min_z or body.p.z > max_z:
		body.p.z = clampf(body.p.z, min_z, max_z)
		body.v.z = -body.v.z * WALL_BOUNCE
		body.w *= 0.8

## Shells knock into each other: pushed apart as spheres, swapping some speed.
func _shell_contacts(bodies: Array[Body]) -> void:
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var a := bodies[i]
			var b := bodies[j]
			var d := b.p - a.p
			var dist := d.length()
			if dist >= SHELL_RADIUS * 2.0 or dist < 1e-6:
				continue
			var n := d / dist
			var overlap := SHELL_RADIUS * 2.0 - dist
			a.p -= n * overlap * 0.5
			b.p += n * overlap * 0.5
			var closing := (a.v - b.v).dot(n)
			if closing > 0.0:
				var j_imp := closing * (1.0 + RESTITUTION) * 0.5
				a.v -= n * j_imp
				b.v += n * j_imp
				a.w += n.cross(Vector3.UP) * j_imp * 2.0
				b.w -= n.cross(Vector3.UP) * j_imp * 2.0
			if closing > 0.05:
				a.asleep = false
				b.asleep = false

func _check_rest(body: Body) -> void:
	if body.asleep:
		return
	var grounded := body.p.y < _reach and absf(Basis(body.q).y.y) > FLAT
	if grounded and body.v.length() < REST_SPEED and body.w.length() < REST_SPIN:
		body.rest_time += DT
		if body.rest_time >= REST_TIME:
			body.asleep = true
			body.v = Vector3.ZERO
			body.w = Vector3.ZERO
	else:
		body.rest_time = 0.0

## After the throw rests: each listed shell hops and rolls over onto its target face.
func _append_hops(result: Dictionary, shells: Array[int], targets: Array[bool]) -> void:
	if shells.is_empty():
		return
	var frames: Array = result["frames"]
	var last: Array = frames.back()
	var count := int(HOP_TIME * HZ)
	for k in range(1, count + 1):
		var t := float(k) / count
		var frame: Array = last.duplicate()
		for i in shells:
			var start: Transform3D = last[i]
			var rest_y := ShellModel.rest_height(targets[i])
			var y := lerpf(start.origin.y, rest_y, t) + sin(t * PI) * HOP_HEIGHT
			var roll := Basis(start.basis.z.normalized(), PI * t) * start.basis
			frame[i] = Transform3D(roll.orthonormalized(), Vector3(start.origin.x, y, start.origin.z))
		frames.append(frame)
	for i in shells:
		result["faces"][i] = targets[i]
