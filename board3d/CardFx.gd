class_name CardFx
extends RefCounted

## Board effects that show what a card did on the 3D board (plain helpers, no game state): a shield
## dome, a chalk mark drawn on a square, sparkle bursts, dust, wind streaks, glowing
## shells and pawn moves (hops, a knock back home, a swap). Each one adds nodes under
## `parent` and animates them with tweens owned by those nodes.

const GOLD := Color(1.0, 0.8, 0.35)

## A see-through golden dome over a pawn that stays (call free() on it to end it).
static func shield(parent: Node3D, at: Vector3) -> MeshInstance3D:
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.is_hemisphere = true
	dome.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = load("res://board3d/shield.gdshader")
	dome.material_override = mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = at
	dome.scale = Vector3.ONE * 0.01
	parent.add_child(dome)
	var t := dome.create_tween()
	t.tween_property(dome, "scale", Vector3.ONE * 1.15, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(dome, "scale", Vector3.ONE, 0.2)
	burst(parent, at + Vector3.UP * 0.3, GOLD)
	return dome

## A chalk circle-and-cross drawn into a square (glowing in `tint`), or a ring pulse.
static func chalk_mark(parent: Node3D, at: Vector3, tint: Color, ring_only: bool = false, seconds: float = 0.9) -> MeshInstance3D:
	var mark := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.95, 0.95)
	mark.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://board3d/chalk_mark.gdshader")
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("ring_only", ring_only)
	mat.set_shader_parameter("drawn", 0.0)
	mark.material_override = mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.position = at + Vector3.UP * 0.006
	parent.add_child(mark)
	var t := mark.create_tween()
	t.tween_method(func(v: float): mat.set_shader_parameter("drawn", v), 0.0, 1.0, seconds)
	t.tween_method(func(v: float): mat.set_shader_parameter("glow", v), 1.2, 0.35, 0.8)
	return mark

## An expanding glowing ring on the ground (an unlock, a pulse) that fades away.
static func ring_pulse(parent: Node3D, at: Vector3, color: Color, size: float = 1.2) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.48
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	ring.material_override = mat
	ring.position = at + Vector3.UP * 0.02
	ring.scale = Vector3(0.2, 0.05, 0.2)
	parent.add_child(ring)
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(size, 0.05, size), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)

## A one-off burst of sparkles.
static func burst(parent: Node3D, at: Vector3, color: Color, amount: int = 40) -> void:
	var p := _particles(parent, at, color, amount, 0.9)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -1.2, 0)
	p.emitting = true

## Brown dust puffing out along the ground (a landing, a knock).
static func dust(parent: Node3D, at: Vector3) -> void:
	var p := _particles(parent, at + Vector3.UP * 0.03, Color(0.55, 0.42, 0.3, 0.7), 18, 0.7)
	p.direction = Vector3.UP
	p.spread = 90.0
	p.flatness = 0.8
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, -0.3, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.emitting = true

## Streaks blowing past a pawn in `direction` for `seconds` (Tailwind).
static func wind(parent: Node3D, at: Vector3, direction: Vector3, seconds: float = 1.6) -> void:
	var p := _particles(parent, at + Vector3.UP * 0.2 - direction * 0.4, Color(0.85, 1.0, 0.95, 0.8), 24, 0.6)
	p.one_shot = false
	p.direction = direction
	p.spread = 8.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.2
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.15, 0.15, 0.15)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.emitting = true
	_stop_after(p, seconds)

## Sparkles circling a spot for a while (Lucky Charm over the shells).
static func shimmer(parent: Node3D, at: Vector3, color: Color, seconds: float = 2.5) -> void:
	var p := _particles(parent, at + Vector3.UP * 0.15, color, 30, 1.0)
	p.one_shot = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.5
	p.emission_ring_inner_radius = 0.35
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.orbit_velocity_min = 0.4
	p.orbit_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	p.emitting = true
	_stop_after(p, seconds)

## Floating text that rises and fades (e.g. "+1" over each pawn, "4!" over the shells).
static func float_text(parent: Node3D, at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = GameFonts.title()
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = color
	label.no_depth_test = true
	label.position = at
	parent.add_child(label)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "position", at + Vector3.UP * 0.5, 1.2).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.4)
	t.chain().tween_callback(label.queue_free)

## A glow laid over a mesh (e.g. golden shells) that fades in, holds, and fades out.
static func glow_over(mesh: GeometryInstance3D, color: Color, hold: float = 1.5) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.0)
	mesh.material_overlay = mat
	var t := mesh.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.8, 0.3)
	t.tween_interval(hold)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	t.tween_callback(func(): mesh.material_overlay = null)

# --- moving pawns ---
## Hops a figure square by square through `points`, with dust on each landing.
static func hop_along(fig: Node3D, points: Array, seconds_per_hop: float = 0.3) -> void:
	for to: Vector3 in points:
		var from := fig.position
		fig.rotation.y = atan2(-(to - from).x, -(to - from).z)
		var t := fig.create_tween()
		t.tween_method(func(v: float):
			fig.position = from.lerp(to, v) + Vector3.UP * sin(v * PI) * 0.28, 0.0, 1.0, seconds_per_hop)
		await t.finished
		dust(fig.get_parent(), to)

## Knocks a figure back to `home`: it tumbles over in an arc and lands in a puff of dust.
static func knock_home(fig: Node3D, home: Vector3) -> void:
	var from := fig.position
	var start_rot := fig.rotation
	dust(fig.get_parent(), from)
	var t := fig.create_tween()
	t.tween_method(func(v: float):
		fig.position = from.lerp(home, v) + Vector3.UP * sin(v * PI) * 0.9
		fig.rotation = Vector3(v * TAU, start_rot.y, 0), 0.0, 1.0, 0.9).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	fig.rotation = start_rot
	dust(fig.get_parent(), home)

## Swaps two figures: each rises and arcs to the other's place, trailing sparkles.
static func swap(a: Node3D, b: Node3D, color: Color) -> void:
	var pa := a.position
	var pb := b.position
	var side := (pb - pa).cross(Vector3.UP).normalized() * 0.35
	var t := a.create_tween()
	t.tween_method(func(v: float):
		var lift := Vector3.UP * sin(v * PI) * 0.6
		a.position = pa.lerp(pb, v) + lift + side * sin(v * PI)
		b.position = pb.lerp(pa, v) + lift - side * sin(v * PI), 0.0, 1.0, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	burst(a.get_parent(), pa + Vector3.UP * 0.3, color, 20)
	burst(a.get_parent(), pb + Vector3.UP * 0.3, color, 20)
	await t.finished
	burst(a.get_parent(), pa + Vector3.UP * 0.2, color, 20)
	burst(a.get_parent(), pb + Vector3.UP * 0.2, color, 20)

## Looping particles: stop emitting after `seconds`, then free once the last ones fade.
static func _stop_after(p: CPUParticles3D, seconds: float) -> void:
	var t := p.create_tween()
	t.tween_interval(seconds)
	t.tween_callback(func(): p.emitting = false)
	t.tween_interval(p.lifetime)
	t.tween_callback(p.queue_free)

static func _particles(parent: Node3D, at: Vector3, color: Color, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.85
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.04
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	quad.material = mat
	p.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.position = at
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	return p
