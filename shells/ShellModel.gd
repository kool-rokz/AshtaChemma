class_name ShellModel
extends RefCounted

## The cowrie shell's look and shape, built in code (swap make_mesh() for a loaded .glb
## later). Local axes: Z = the long axis, X = width, +Y = the domed back. The flat belly
## (-Y) carries the toothed slit: a shell lies "open side up" when its -Y faces the sky.
## Sizes are in board units (one board square = 1).

const LENGTH := 0.36
const WIDTH := 0.27
## Height of the dome above the widest line, and depth of the belly below it.
## The dome is lower than half the width, so a shell on its back rocks back onto
## its crown (stable) instead of resting at any tilt.
const DOME := 0.105
const BELLY := 0.045
## Where the weight sits, above the widest line: a real cowrie's thick back makes it
## heavier there, which keeps "on its back" about as likely as "on its belly".
## All geometry is measured from this point (the body's origin).
const CENTER_OF_MASS := Vector3(0, 0.028, 0)

## A money cowrie: warm amber back with brown spots, white belly (easy to tell apart,
## and both stand out on the pale board).
const BACK_COLOR := Color(0.88, 0.7, 0.38)
const SPOT_COLOR := Color(0.5, 0.3, 0.14)
const BELLY_COLOR := Color(0.99, 0.97, 0.92)
const SLIT_COLOR := Color(0.22, 0.14, 0.09)

static var _mesh_cache: ArrayMesh
static var _material_cache: StandardMaterial3D

## Is a shell with this orientation lying open side up?
static func is_open_up(basis: Basis) -> bool:
	return basis.y.y < 0.0

## Orientation for a resting shell: open side up or down, turned `yaw` around the vertical.
static func resting_basis(open_up: bool, yaw: float) -> Basis:
	var basis := Basis(Vector3.UP, yaw)
	if open_up:
		basis = basis * Basis(Vector3.FORWARD, PI) # roll over onto the back
	return basis

## Contact points on the hull (local space) used by ShellSim: rings of points on the
## same curved surface as the mesh, dense enough that a shell rolls smoothly onto its
## crown or belly instead of resting propped on a facet.
static func hull_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	# [angle from the crown in degrees, points in that ring]
	var rings := [[0, 1], [25, 6], [50, 6], [72, 6], [90, 8], [125, 6], [180, 1]]
	for r in rings.size():
		var phi := deg_to_rad(rings[r][0])
		var count: int = rings[r][1]
		for i in count:
			# Neighbouring rings are staggered half a step, so no gap lines up
			points.append(_surface_point(phi, TAU * (i + 0.5 * (r % 2)) / count))
	return points

## A point on the shell: phi from the crown (0) to the belly's centre (PI), theta around.
static func _surface_point(phi: float, theta: float) -> Vector3:
	var x := sin(phi) * cos(theta) * WIDTH / 2.0
	var z := sin(phi) * sin(theta) * LENGTH / 2.0
	var y := cos(phi) * (DOME if cos(phi) >= 0.0 else BELLY)
	return Vector3(x, y, z) - CENTER_OF_MASS

## Height of the body's origin when resting open side up (on its back) or down (on its belly).
static func rest_height(open_up: bool) -> float:
	return DOME + CENTER_OF_MASS.y if open_up else BELLY - CENTER_OF_MASS.y

# --- SCENE PIECES (used by ShellStage on the 3D board) ---
## The ring under a shell that landed open side up.
const RING_COLOR := Color(1.0, 0.84, 0.35)

## Warm key light from the top left plus soft ambient fill.
static func add_lighting(parent: Node) -> void:
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.looking_at(Vector3(0.35, -1.0, 0.45)), Vector3.ZERO)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.96, 0.9)
	parent.add_child(light)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)

static func make_shell() -> MeshInstance3D:
	var shell := MeshInstance3D.new()
	shell.mesh = make_mesh()
	return shell

## Gold ring lying under a shell that landed open side up.
static func make_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.235
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.25, 1.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RING_COLOR
	ring.material_override = mat
	ring.visible = false
	return ring

static func make_mesh() -> ArrayMesh:
	if _mesh_cache:
		return _mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var segments := 28
	# A squashed ellipsoid: tall dome above the widest line, flat belly below it
	var grid: Array = []
	for r in rings + 1:
		var phi := PI * r / rings # 0 = top of the dome, PI = middle of the belly
		var row: Array = []
		for s in segments + 1:
			row.append(_surface_point(phi, TAU * s / segments))
		grid.append(row)
	for r in rings:
		for s in segments:
			var quad := [grid[r][s], grid[r + 1][s], grid[r + 1][s + 1], grid[r][s + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[idx]
				st.set_color(_surface_color(v))
				st.set_normal(_normal_at(v))
				st.add_vertex(v)
	_add_slit(st)
	_mesh_cache = st.commit()
	_mesh_cache.surface_set_material(0, material())
	return _mesh_cache

static func material() -> StandardMaterial3D:
	if _material_cache:
		return _material_cache
	_material_cache = StandardMaterial3D.new()
	_material_cache.vertex_color_use_as_albedo = true
	_material_cache.roughness = 0.3
	_material_cache.metallic_specular = 0.7
	# Closed shape, so drawing both sides costs nothing and winding never matters
	_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material_cache

## Back: cream with brown speckles (a fixed pattern so every copy looks the same).
static func _surface_color(point: Vector3) -> Color:
	var v := point + CENTER_OF_MASS
	if v.y < -0.001:
		return BELLY_COLOR
	var n := sin(v.x * 71.0) * cos(v.z * 53.0) + sin((v.x + v.z) * 97.0) * 0.6
	var color := BACK_COLOR.lerp(SPOT_COLOR, clampf(n * 1.1 - 0.4, 0.0, 0.8))
	# The back pales towards the rim, like a real shell
	return color.lerp(BELLY_COLOR, clampf(1.0 - v.y / DOME * 3.0, 0.0, 0.7))

static func _normal_at(point: Vector3) -> Vector3:
	var v := point + CENTER_OF_MASS
	var a := WIDTH / 2.0
	var c := LENGTH / 2.0
	var h := DOME if v.y >= 0.0 else BELLY
	return Vector3(v.x / (a * a), v.y / (h * h), v.z / (c * c)).normalized()

## The dark slit down the belly with its teeth, just outside the surface.
static func _add_slit(st: SurfaceTool) -> void:
	var y := -BELLY - 0.004 - CENTER_OF_MASS.y
	var half_len := LENGTH * 0.4
	var half_w := 0.012
	_add_quad(st, Vector3(-half_w, y, -half_len), Vector3(half_w, y, -half_len),
		Vector3(half_w, y, half_len), Vector3(-half_w, y, half_len), SLIT_COLOR)
	var teeth := 7
	for i in teeth:
		var z := lerpf(-half_len * 0.85, half_len * 0.85, float(i) / (teeth - 1))
		var tooth := 0.035 * (1.0 - absf(z) / half_len * 0.5)
		_add_quad(st, Vector3(-tooth, y, z - 0.005), Vector3(tooth, y, z - 0.005),
			Vector3(tooth, y, z + 0.005), Vector3(-tooth, y, z + 0.005), SLIT_COLOR)

static func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color) -> void:
	for v in [p0, p2, p1, p0, p3, p2]: # wound to face -Y (outwards from the belly)
		st.set_color(color)
		st.set_normal(Vector3.DOWN)
		st.add_vertex(v)
