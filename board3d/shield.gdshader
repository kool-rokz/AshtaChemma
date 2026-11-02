shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// A see-through protective dome (Aegis): bright at the rim, faint in the middle, pulsing.

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float strength = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
	// Faint bands sweeping up the dome, like a woven shell pattern
	float bands = 0.5 + 0.5 * sin(UV.y * 40.0 - TIME * 2.0);
	ALBEDO = tint.rgb * (rim * 1.4 + 0.06 + bands * 0.05) * pulse * strength;
}
