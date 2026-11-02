shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A see-through protective dome (Aegis): clear in the middle so the pawn inside shows in
// its own colours, a glowing rim where the dome curves away, thin woven bands sweeping
// up, and a gentle pulse. The far side shows fainter through the near side.

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float strength = 1.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - facing, 3.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	float bands = smoothstep(0.93, 1.0, 0.5 + 0.5 * sin(UV.y * 60.0 - TIME * 2.0));
	ALBEDO = tint.rgb * 1.3;
	// The far side: only a faint rim, no bands (they'd stripe across the pawn)
	float near = FRONT_FACING ? 1.0 : 0.0;
	ALPHA = clamp((rim * (0.3 + 0.4 * near) + bands * 0.06 * near) * pulse * strength, 0.0, 0.9);
}
