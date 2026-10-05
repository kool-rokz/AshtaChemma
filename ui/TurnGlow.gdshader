shader_type canvas_item;

// Soft glow along the screen edges in the active player's colour, gently pulsing.
// Drawn by a full-screen ColorRect in the HUD (behind the panels, ignores the mouse).

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How far the glow reaches in from each edge, in pixels.
uniform float width_px = 34.0;
uniform float min_strength = 0.28;
uniform float max_strength = 0.7;
// Seconds per pulse.
uniform float period = 2.6;

void fragment() {
	vec2 size_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = UV * size_px;
	float edge = min(min(px.x, size_px.x - px.x), min(px.y, size_px.y - px.y));
	float falloff = 1.0 - smoothstep(0.0, width_px, edge);
	float pulse = 0.5 + 0.5 * sin(TIME * TAU / period);
	float strength = mix(min_strength, max_strength, pulse);
	COLOR = vec4(glow_color.rgb, glow_color.a * falloff * falloff * strength);
}
