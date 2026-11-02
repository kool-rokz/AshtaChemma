class_name BoardWorld
extends RefCounted

## The match's 3D setting, as plain helpers (no game state, so the match view and the
## art labs share it): a mud courtyard floor, the board drawn in chalk, lighting (dusk
## with an oil lamp, or dawn), cowry shell props and board-square positions.
## The board is 5x5 squares of 1 unit, centred on the origin; square index = x + 5*y
## like BoardData, with y running towards +Z (the bottom seat's side).

const SQUARE := 1.0
const SAFE := [2, 6, 8, 10, 12, 14, 16, 18, 22]

static func square_position(index: int) -> Vector3:
	@warning_ignore("integer_division")
	return Vector3((index % 5 - 2) * SQUARE, 0.0, (index / 5 - 2) * SQUARE)

static func add_floor(parent: Node) -> MeshInstance3D:
	var ground := MeshInstance3D.new()
	ground.name = "MudFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://board3d/mud_floor.gdshader")
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # only receives
	parent.add_child(ground)
	return ground

static func add_chalk_board(parent: Node) -> MeshInstance3D:
	var board := MeshInstance3D.new()
	board.name = "ChalkBoard"
	var plane := PlaneMesh.new()
	plane.size = Vector2(5, 5) * SQUARE
	board.mesh = plane
	board.position.y = 0.003
	var mat := ShaderMaterial.new()
	mat.shader = load("res://board3d/chalk_board.gdshader")
	board.material_override = mat
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(board)
	return board

## Light settings (a per-player choice). DUSK (the default): low warm sun, dim blue
## sky light and a flickering oil lamp (diya) at the board's corner. DAWN: cool, soft
## early light from the other side with a little mist, the lamp out.
const DUSK := "dusk"
const DAWN := "dawn"

## Returns the nodes so a lab can switch modes with set_light().
static func add_lighting(parent: Node, mode: String = DUSK) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	parent.add_child(sun)
	var lamp := make_diya()
	lamp.position = Vector3(2.9, 0, -2.9)
	parent.add_child(lamp)
	var lights := {"env": env, "sun": sun, "lamp": lamp}
	set_light(lights, mode)
	return lights

## Graphics quality (Settings.QUALITY_HIGH / QUALITY_LOW): shadows and edge smoothing.
## Every new effect should check this too, so phones and handhelds keep their frame rate.
static func apply_quality(lights: Dictionary, viewport: Viewport, quality: String) -> void:
	var high := quality != Settings.QUALITY_LOW
	(lights["sun"] as DirectionalLight3D).shadow_enabled = high
	var lamp_light := (lights["lamp"] as Node3D).get_node_or_null("Light") as OmniLight3D
	if lamp_light:
		lamp_light.shadow_enabled = high
	viewport.msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED

static func set_light(lights: Dictionary, mode: String) -> void:
	var env: Environment = lights["env"]
	var sun: DirectionalLight3D = lights["sun"]
	var lamp: Node3D = lights["lamp"]
	var dusk := mode != DAWN
	if dusk:
		env.background_color = Color(0.16, 0.12, 0.14)
		env.ambient_light_color = Color(0.45, 0.5, 0.75)
		env.ambient_light_energy = 0.35
		env.fog_enabled = false
		sun.light_color = Color(1.0, 0.62, 0.38)
		sun.light_energy = 0.55
		sun.rotation_degrees = Vector3(-18, -60, 0)
	else:
		env.background_color = Color(0.62, 0.66, 0.74)
		env.ambient_light_color = Color(0.72, 0.78, 0.92)
		env.ambient_light_energy = 0.5
		env.fog_enabled = true
		env.fog_light_color = Color(0.6, 0.63, 0.7)
		env.fog_density = 0.006
		env.fog_sky_affect = 0.0
		sun.light_color = Color(1.0, 0.84, 0.74)
		sun.light_energy = 0.7
		sun.rotation_degrees = Vector3(-14, 120, 0)
	(lamp.get_node("Light") as OmniLight3D).visible = dusk
	(lamp.get_node("Flame") as Node3D).visible = dusk

## A small clay oil lamp with a flame and a flickering light (lit only at dusk).
static func make_diya() -> Node3D:
	var lamp := Node3D.new()
	lamp.name = "Diya"
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.16
	bowl_mesh.bottom_radius = 0.09
	bowl_mesh.height = 0.08
	bowl.mesh = bowl_mesh
	bowl.position.y = 0.04
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.62, 0.3, 0.16)
	clay.roughness = 0.85
	bowl.material_override = clay
	lamp.add_child(bowl)
	var oil := MeshInstance3D.new()
	var oil_mesh := CylinderMesh.new()
	oil_mesh.top_radius = 0.13
	oil_mesh.bottom_radius = 0.13
	oil_mesh.height = 0.005
	oil.mesh = oil_mesh
	oil.position.y = 0.075
	var oil_mat := StandardMaterial3D.new()
	oil_mat.albedo_color = Color(0.35, 0.24, 0.05)
	oil_mat.roughness = 0.1
	oil.material_override = oil_mat
	lamp.add_child(oil)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.03
	flame_mesh.height = 0.11
	flame.mesh = flame_mesh
	flame.position = Vector3(0.1, 0.13, 0)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.8, 0.35)
	flame.material_override = flame_mat
	lamp.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0.1, 0.25, 0)
	light.light_color = Color(1.0, 0.68, 0.32)
	light.light_energy = 2.2
	light.omni_range = 6.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	lamp.add_child(light)
	var flicker := Timer.new()
	flicker.wait_time = 0.07
	flicker.autostart = true
	flicker.timeout.connect(func():
		light.light_energy = 2.2 + randf_range(-0.35, 0.35)
		flame.scale = Vector3.ONE * randf_range(0.9, 1.1))
	lamp.add_child(flicker)
	return lamp

## A cowry shell resting on the board (a prop).
static func add_shell(parent: Node, position: Vector3, open_up: bool, yaw: float) -> MeshInstance3D:
	var shell := ShellModel.make_shell()
	shell.transform = Transform3D(ShellModel.resting_basis(open_up, yaw),
		position + Vector3.UP * ShellModel.rest_height(open_up))
	parent.add_child(shell)
	return shell
