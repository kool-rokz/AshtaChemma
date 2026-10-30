class_name ShellModel
extends RefCounted

## The cowrie shell's look and shape, built in code (swap make_mesh() for a loaded .glb
## later). Local axes: Z = the long axis, X = width, +Y = the domed back. The flat belly
## (-Y) carries the toothed slit: a shell lies "open side up" when its -Y faces the sky.
## Sizes are in stage units (1 unit = 100 screen pixels, see ShellStage).

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
static var _ghost_cache: StandardMaterial3D

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

# --- SCENE PIECES (shared by ShellStage over the board and ShellsView in the panel) ---
## Stage units per screen pixel: the ground plane (y = 0) maps 1:1 onto the screen.
const UNITS_PER_PIXEL := 0.01
const CAMERA_HEIGHT := 10.0
const RING_COLOR := Color(1.0, 0.84, 0.35)

static func screen_to_ground(screen: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(screen.x * UNITS_PER_PIXEL, height, screen.y * UNITS_PER_PIXEL)

static func ground_to_screen(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / UNITS_PER_PIXEL

## A camera looking straight down at `view_rect` (screen pixels) so that the ground
## plane lines up pixel for pixel with the 2D screen. Shells in the air look bigger.
static func make_camera(view_rect: Rect2) -> Camera3D:
	var camera := Camera3D.new()
	var center := screen_to_ground(view_rect.get_center(), CAMERA_HEIGHT)
	# Looking down -Y; screen right = +X, screen down = +Z
	camera.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), center)
	camera.fov = rad_to_deg(2.0 * atan(view_rect.size.y * UNITS_PER_PIXEL / 2.0 / CAMERA_HEIGHT))
	camera.near = 0.5
	camera.far = CAMERA_HEIGHT + 2.0
	return camera

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

## A transparent 3D layer (sized by its SubViewportContainer), with its own world.
static func make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	return viewport

## See-through version, for "not thrown yet" placeholders.
static func ghost_material() -> StandardMaterial3D:
	if _ghost_cache:
		return _ghost_cache
	_ghost_cache = material().duplicate()
	_ghost_cache.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_cache.albedo_color = Color(1, 1, 1, 0.22)
	return _ghost_cache

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

## Soft round shadow on the ground (offset and fainter the higher the shell is).
static func make_shadow() -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.44, 0.5)
	shadow.mesh = plane
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.32))
	gradient.set_color(1, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow.material_override = mat
	return shadow

## Puts a shell's shadow on the ground under it (offset from the light, fainter when high).
static func place_shadow(shadow: MeshInstance3D, shell_pos: Vector3) -> void:
	var h := maxf(shell_pos.y, 0.0)
	shadow.position = Vector3(shell_pos.x + h * 0.25, 0.002, shell_pos.z + h * 0.3)
	shadow.scale = Vector3.ONE * (1.0 + h * 0.35)
	var fade := clampf(h * 0.8, 0.0, 0.85)
	(shadow.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 1.0 - fade)

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
