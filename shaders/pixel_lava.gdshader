shader_type canvas_item;
render_mode unshaded;

// Original procedural surface; visual references: docs/像素熔岩地形说明.md.
uniform float radius = 200.0;
uniform float pixel_size = 3.0;
uniform float clock_time = 0.0;
uniform float animation_fps = 12.0;
uniform float flow_speed = 1.0;
uniform float plate_size = 38.0;
uniform float channel_width = 0.18;
uniform float pattern_seed = 1.0;
uniform vec4 crust_dark : source_color = vec4(0.105, 0.075, 0.095, 1.0);
uniform vec4 crust_light : source_color = vec4(0.29, 0.16, 0.17, 1.0);
uniform vec4 lava_dark : source_color = vec4(0.65, 0.10, 0.035, 1.0);
uniform vec4 lava_red : source_color = vec4(0.91, 0.22, 0.035, 1.0);
uniform vec4 lava_orange : source_color = vec4(1.0, 0.43, 0.055, 1.0);
uniform vec4 lava_gold : source_color = vec4(1.0, 0.72, 0.16, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.92, 0.53, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

vec2 hash2(vec2 p) {
	vec3 v = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	v += dot(v, v.yzx + 33.33 + pattern_seed * 0.013);
	return fract((v.xx + v.yz) * v.zy);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(cell).x, hash2(cell + vec2(1.0, 0.0)).x, f.x),
		mix(hash2(cell + vec2(0.0, 1.0)).x, hash2(cell + vec2(1.0)).x, f.x), f.y);
}

// Difference of the two nearest sites creates connected molten channels.
vec3 rock_cells(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float first = 10.0;
	float second = 10.0;
	float rock_id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 h = hash2(cell + offset);
			vec2 site = 0.5 + 0.29 * sin(h * TAU + t * 0.19);
			vec2 d = offset + site - f;
			float distance_sq = dot(d, d);
			if (distance_sq < first) {
				second = first;
				first = distance_sq;
				rock_id = h.x;
			} else {
				second = min(second, distance_sq);
			}
		}
	}
	return vec3(sqrt(second) - sqrt(first), sqrt(first), rock_id);
}

vec3 heat_palette(float heat) {
	vec3 color = lava_dark.rgb;
	color = mix(color, lava_red.rgb, step(0.24, heat));
	color = mix(color, lava_orange.rgb, step(0.46, heat));
	color = mix(color, lava_gold.rgb, step(0.68, heat));
	return mix(color, lava_hot.rgb, step(0.88, heat));
}

void fragment() {
	// Local world-unit grid stays attached to the ground under camera movement.
	vec2 local = (UV - 0.5) * radius * 2.0;
	vec2 p = (floor(local / pixel_size) + 0.5) * pixel_size;
	float t = floor(clock_time * animation_fps) / animation_fps * flow_speed;
	float radial = length(p) / radius;
	float edge_noise = noise(p / 23.0 + vec2(pattern_seed));
	float shoreline = 0.955 + (edge_noise - 0.5) * 0.055;
	float mask = step(radial, shoreline);
	vec2 drift = vec2(t * 0.045, -t * 0.031);
	vec2 q = p / plate_size + vec2(pattern_seed * 0.71) + drift;
	vec2 warp = vec2(noise(q * 0.82 + t * 0.07), noise(q * 0.91 - t * 0.055 + 17.0));
	q += (warp - 0.5) * 0.65;
	vec3 cells = rock_cells(q, t);
	float molten = 1.0 - smoothstep(channel_width * 0.3, channel_width, cells.x);
	float current = noise(p / 29.0 + vec2(t * 0.21, -t * 0.13));
	float fine = noise(p / 9.0 - vec2(t * 0.17, t * 0.1));
	float heat = clamp(molten * 0.55 + current * 0.38 + fine * 0.15, 0.0, 1.0);
	float rock_shade = floor(clamp(cells.z * 0.45 + fine * 0.35 + cells.y * 0.2, 0.0, 0.99) * 3.0) / 2.0;
	vec3 rock = mix(crust_dark.rgb, crust_light.rgb, rock_shade);
	float bevel = step(cells.x, channel_width + 0.07);
	rock = mix(rock, vec3(0.38, 0.17, 0.13), bevel * 0.65);
	vec3 color = mix(rock, heat_palette(heat), step(0.14, molten));
	// Sparse expanding pixel bubbles, no particle nodes or gameplay RNG.
	vec2 bubble_cell = floor(p / 34.0);
	vec2 bubble_hash = hash2(bubble_cell + 83.0);
	vec2 bubble_pos = (bubble_cell + 0.2 + bubble_hash * 0.6) * 34.0;
	float life = fract(t * 0.32 + bubble_hash.x * 7.0);
	float bubble_distance = length(p - bubble_pos);
	float ring = step(abs(bubble_distance - life * 6.0), pixel_size * 0.6);
	ring *= step(0.10, life) * step(life, 0.80) * step(0.68, bubble_hash.y) * step(0.6, molten);
	color = mix(color, lava_hot.rgb, ring);
	// Scorched irregular lip stays within the actual circular damage radius.
	float inner_rim = step(shoreline - 0.045, radial);
	float outer_rim = step(shoreline - 0.020, radial);
	color = mix(color, mix(lava_dark.rgb, lava_orange.rgb, step(0.55, current)), inner_rim);
	color = mix(color, crust_dark.rgb, outer_rim);
	COLOR = vec4(color, mask) * item_color;
}
