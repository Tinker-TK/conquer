shader_type canvas_item;
render_mode unshaded;

// Four pixel layers share an integer-frame, periodic local clock.
uniform vec2 draw_size = vec2(32.0, 48.0);
uniform vec2 portal_size = vec2(19.0, 34.0);
uniform float pixel_size = 1.0;
uniform float cycle_phase = 0.0;
uniform float ring_width = 2.3;
uniform float distortion = 0.7;
uniform float swirl_strength = 1.0;
uniform float brightness = 1.0;
uniform float random_seed = 1.0;
uniform int fragment_count = 10;
uniform bool ring_enabled = true;
uniform bool interior_enabled = true;
uniform bool fragments_enabled = true;
uniform bool ground_enabled = true;
uniform bool halo_enabled = false;
uniform vec4 color_0 : source_color = vec4(0.055, 0.08, 0.15, 1.0);
uniform vec4 color_1 : source_color = vec4(0.12, 0.22, 0.29, 1.0);
uniform vec4 color_2 : source_color = vec4(0.22, 0.43, 0.5, 1.0);
uniform vec4 color_3 : source_color = vec4(0.39, 0.69, 0.73, 1.0);
uniform vec4 color_4 : source_color = vec4(0.7, 0.91, 0.89, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

vec4 palette(float value) {
	vec4 c = color_0;
	if (value > 0.22) { c = color_1; }
	if (value > 0.43) { c = color_2; }
	if (value > 0.66) { c = color_3; }
	if (value > 0.86) { c = color_4; }
	return c;
}

vec4 over(vec4 bottom, vec4 top) {
	float a = top.a + bottom.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

void fragment() {
	vec2 p = (floor(UV * draw_size / pixel_size) + 0.5) * pixel_size;
	vec2 center = vec2(draw_size.x * 0.5, draw_size.y - 6.0 - portal_size.y * 0.5);
	vec2 radius = portal_size * 0.5;
	vec2 q = (p - center) / radius;
	float r = length(q);
	float angle = atan(q.y, q.x);
	float t = cycle_phase * TAU;
	vec2 orbit = vec2(cos(t), sin(t));
	float n = noise(p * 0.37 + orbit * 1.8 + random_seed * 7.13);
	float detail = noise(p * 0.81 + vec2(cos(t * 2.0), sin(t * 2.0)) * 2.0 + random_seed);
	vec4 result = vec4(0.0);

	// Ground light: an uneven pool plus three staggered expanding ellipses.
	vec2 floor_q = (p - vec2(center.x, draw_size.y - 5.5)) / vec2(radius.x + 3.8, 2.6);
	float floor_r = length(floor_q);
	if (ground_enabled) {
		float light = max(0.0, 1.0 - floor_r) * (0.25 + n * 0.65);
		float waves = 0.0;
		for (int i = 0; i < 3; i++) {
			float phase = fract(cycle_phase + float(i) / 3.0);
			float wave_r = 0.18 + phase * 0.9;
			float wave = step(abs(floor_r - wave_r), 0.065) * sin(phase * 3.14159265);
			waves = max(waves, wave * step(0.35, detail));
		}
		float ground = max(light * step(0.30, n), waves * 0.8);
		if (ground > 0.09) {
			result = palette(ground * 0.65 + n * 0.28);
			result.a *= clamp(ground * 1.35, 0.0, 0.86);
		}
	}

	// The interior stays dark; rotating spiral bands imply depth without filling the hole with light.
	if (interior_enabled && r < 0.91) {
		float spiral = sin(angle * 3.0 + r * 9.0 - t * 2.0 + n * 2.3);
		float eddy = noise(q * 2.8 + orbit * 1.3 + random_seed * 3.0);
		float value = clamp((spiral * 0.19 + eddy * 0.31 + r * 0.12) * swirl_strength, 0.0, 0.56);
		vec4 inside = palette(value);
		inside.a *= 0.76;
		result = over(result, inside);
	}

	// A narrow ellipse with continuous breathing, lumpy erosion, and travelling bright filaments.
	float wobble = (sin(angle * 3.0 - t) * 0.33 + sin(angle * 7.0 + t * 2.0) * 0.18
		+ (n - 0.5) * 0.9) * distortion;
	float distance_to_ring = (r - 1.0) * radius.x - wobble;
	float width = ring_width * (0.78 + n * 0.36);
	if (halo_enabled && ring_enabled) {
		float halo = max(0.0, 1.0 - abs(distance_to_ring) / (width + 2.2)) * 0.16;
		result = over(result, vec4(color_2.rgb, halo * color_2.a));
	}
	if (ring_enabled && abs(distance_to_ring) < width * 0.5) {
		float rim = 1.0 - abs(distance_to_ring + width * 0.12) / (width * 0.55);
		float filament = sin(angle * 5.0 - t * 3.0 + n * 3.2) * 0.5 + 0.5;
		float value = clamp(0.30 + rim * 0.39 + n * 0.12 + filament * 0.16, 0.0, 1.0);
		if (detail > 0.65 && rim > 0.25) { value += 0.19; }
		result = over(result, palette(value));
	}

	// Individually phased chips orbit outside the ring. Every trajectory returns exactly after one cycle.
	if (fragments_enabled) {
		vec4 chips = vec4(0.0);
		for (int i = 0; i < 20; i++) {
			if (i >= fragment_count) { break; }
			float id = float(i);
			float seed = hash(vec2(id + 1.0, random_seed + 8.0));
			float a = t + id * 2.39996323 + seed * 0.8;
			float radial = 1.12 + seed * 0.19 + sin(t * 2.0 + id) * 0.045;
			vec2 pos = center + vec2(cos(a), sin(a)) * radius * radial;
			vec2 delta = abs(p - pos);
			float size = mix(0.40, 0.87, seed);
			float visibility = sin(t + id * 1.7) * 0.5 + 0.5;
			if (max(delta.x, delta.y) < size && visibility > 0.28) {
				chips = palette(0.42 + visibility * 0.47);
				chips.a *= smoothstep(0.28, 0.5, visibility);
			}
		}
		result = over(result, chips);
	}
	result.rgb *= brightness;
	result.a *= min(brightness, 1.0);
	COLOR = result * item_color;
}
