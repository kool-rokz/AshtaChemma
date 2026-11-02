shader_type spatial;
render_mode diffuse_burley;

// A packed-mud courtyard floor, smoothed by hand: warm ochre with darker patches,
// arcs left by the smoothing hand, fine cracks and specks of straw. All procedural.

uniform vec3 mud_light : source_color = vec3(0.50, 0.37, 0.26);
uniform vec3 mud_dark : source_color = vec3(0.34, 0.24, 0.16);
uniform vec3 straw : source_color = vec3(0.66, 0.56, 0.36);
uniform float scale = 1.0;

varying highp vec3 world_pos;

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

highp float fbm(highp vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest cell edge of a jittered grid (crack lines).
highp float cracks(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	highp vec2 p = world_pos.xz * scale;
	float patches = fbm(p * 0.35);
	vec3 col = mix(mud_dark, mud_light, smoothstep(0.25, 0.75, patches));
	// Smoothing arcs: rings around scattered centres, distorted by noise
	float arcs = sin(length(p * 0.9 + vec2(fbm(p * 0.5) * 3.0)) * 9.0 + fbm(p * 1.3) * 4.0);
	col *= 1.0 + arcs * 0.035;
	// Fine grain
	col *= 0.92 + 0.16 * noise(p * 22.0);
	// Hairline cracks, fading in and out across the floor
	float c = cracks(p * 1.6 + fbm(p * 2.0) * 0.6);
	float crack = (1.0 - smoothstep(0.0, 0.035, c)) * smoothstep(0.45, 0.7, fbm(p * 0.6 + 4.0));
	col = mix(col, mud_dark * 0.6, crack * 0.6);
	// Straw specks
	vec2 sp = p * 9.0;
	float speck = step(0.994, hash(floor(sp))) * (1.0 - smoothstep(0.1, 0.35, length(fract(sp) - 0.5)));
	col = mix(col, straw, speck * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.92 - crack * 0.1;
	SPECULAR = 0.2;
	NORMAL_MAP = vec3(0.5 + (noise(p * 18.0) - 0.5) * 0.25, 0.5 + (noise(p * 18.0 + 7.0) - 0.5) * 0.25, 1.0);
	NORMAL_MAP_DEPTH = 0.6;
}
