shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;

// The Ashta Chemma board drawn in chalk on the mud: a hand-drawn 5x5 grid with wobbly,
// dusty lines, crosses on the safe squares and a ring round the centre home.
// The plane is the board itself: UV (0,0)-(1,1) covers all 5x5 squares.

uniform vec3 chalk : source_color = vec3(0.96, 0.94, 0.88);
uniform float line_width = 0.045; // in squares
uniform float wobble = 0.025;
uniform float drawn : hint_range(0.0, 1.0) = 1.0; // 0..1 reveal, for drawing it in

// Integer hash of a lattice point (p holds whole numbers). Exact, so neighbouring
// cells always agree on their shared corners (a float hash left seams on the floor).
highp float hash(highp vec2 p) {
	uint h = uint(int(round(p.x))) * 1597334677u ^ uint(int(round(p.y))) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h) / 4294967295.0;
}

highp float noise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Coverage of a chalk stroke at distance d from its centre line.
float stroke(float d, float along) {
	float w = line_width * (0.75 + 0.5 * noise(vec2(along * 3.0, 1.3)));
	return 1.0 - smoothstep(w * 0.45, w * 0.6, d);
}

bool is_safe(vec2 cell) {
	bool even = mod(cell.x + cell.y, 2.0) < 0.5;
	bool corner = (cell.x < 0.5 || cell.x > 3.5) && (cell.y < 0.5 || cell.y > 3.5);
	return even && !corner;
}

void fragment() {
	vec2 g = UV * 5.0; // square units
	vec2 cell = clamp(floor(g), 0.0, 4.0);
	vec2 local = g - cell;
	float ink = 0.0;
	// Grid lines, each nudged by a slow wobble along its length
	vec2 wob = vec2(noise(vec2(g.y * 1.7, floor(g.x + 0.5) * 7.0)), noise(vec2(g.x * 1.7, floor(g.y + 0.5) * 7.0 + 3.0)));
	vec2 d = abs(g - floor(g + 0.5) + (wob - 0.5) * wobble * 2.0);
	ink = max(ink, stroke(d.x, g.y));
	ink = max(ink, stroke(d.y, g.x));
	// Crosses on safe squares
	if (is_safe(cell)) {
		vec2 c = local - 0.5;
		float inset = 1.0 - smoothstep(0.3, 0.34, max(abs(c.x), abs(c.y)));
		float n = (noise(g * 4.0) - 0.5) * wobble;
		float d1 = abs(c.x - c.y + n) * 0.7071;
		float d2 = abs(c.x + c.y - n) * 0.7071;
		ink = max(ink, stroke(min(d1, d2), g.x + g.y) * inset);
	}
	// A ring round the centre home
	float r = length(g - 2.5);
	ink = max(ink, stroke(abs(r - 0.38 - (noise(g * 3.0) - 0.5) * wobble), atan(g.y - 2.5, g.x - 2.5)));
	// Dusty, uneven chalk: gaps along strokes and powder around them
	float dust = noise(g * 38.0) * 0.6 + noise(g * 9.0) * 0.4;
	ink *= smoothstep(0.15, 0.55, dust + 0.2);
	float halo = 0.0;
	// Reveal: strokes appear in a sweep across the board
	float reveal = smoothstep(drawn * 1.3 - 0.3, drawn * 1.3, (UV.x + UV.y) * 0.5);
	ink *= 1.0 - reveal;
	ALBEDO = chalk;
	ALPHA = clamp(ink * 0.9 + halo, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
