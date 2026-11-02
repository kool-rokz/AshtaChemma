shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// A chalk mark drawn on one square: a circle with a cross in it (a new safe house,
// Sanctuary), or just a ring (ring_only, used for pulses). `drawn` 0..1 sweeps the
// strokes in as if someone is drawing them; `glow` lights the chalk in `tint`.

uniform vec3 chalk : source_color = vec3(0.96, 0.94, 0.88);
uniform vec3 tint : source_color = vec3(0.3, 0.9, 0.9);
uniform float drawn : hint_range(0.0, 1.0) = 1.0;
uniform float glow = 0.0;
uniform bool ring_only = false;
uniform float width = 0.05;

float stroke(float d) {
	return 1.0 - smoothstep(width * 0.4, width * 0.6, d);
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	float a = fract(atan(c.y, c.x) / 6.28318 + 0.25);
	float ink = stroke(abs(r - 0.4)) * step(a, drawn * (ring_only ? 1.0 : 2.0));
	if (!ring_only) {
		// The cross is drawn in the second half of `drawn`, one stroke after the other
		float t = clamp(drawn * 2.0 - 1.0, 0.0, 1.0);
		float inset = step(max(abs(c.x), abs(c.y)), 0.26);
		float d1 = abs(c.x - c.y) * 0.7071;
		float d2 = abs(c.x + c.y) * 0.7071;
		float along1 = (c.x + c.y) * 0.7071 / 0.74 + 0.5;
		float along2 = (c.x - c.y) * 0.7071 / 0.74 + 0.5;
		ink = max(ink, stroke(d1) * inset * step(along1, t * 2.0));
		ink = max(ink, stroke(d2) * inset * step(along2, t * 2.0 - 1.0));
	}
	ALBEDO = mix(chalk, tint, glow * 0.6);
	EMISSION = tint * glow * 1.5 * ink;
	ALPHA = ink * 0.92;
	ROUGHNESS = 1.0;
}
