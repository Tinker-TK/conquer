shader_type canvas_item;
render_mode unshaded;

// Surface combustion inspired by BV1dyJi62E5A: a glowing, ragged rim
// carries short upward flame sheets around transparent, charred pockets.
uniform float radius = 200.0;
uniform float pixel_size = 2.0;
uniform float density = 0.85;
uniform float pattern_seed = 1.0;
uniform float clock_time = 0.0;
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

float hash(vec2 p) {
	vec3 v = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	v += dot(v, v.yzx + 33.33 + pattern_seed * 0.017);
	return fract((v.x + v.y) * v.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

// Return heat and coverage for a burning rim. Noise moves upward through
// the sheet, opening holes and breaking off tips as each pocket cools.
vec2 flame_rim(vec2 p, float root_y, float dx, float height, float t, float phase, float energy) {
	float lift = root_y - p.y;
	float rise = max(lift / max(height, 1.0), 0.0);
	float flow = noise(vec2(dx * 5.4 + phase, t * 2.1 + rise * 1.8));
	float fine = noise(vec2(dx * 7.0 - phase, t * 3.2 + rise * 3.1));
	float crest = height * (0.18 + pow(flow, 1.5) * 1.50) * sqrt(max(energy, 0.0));
	float body = (1.0 - smoothstep(crest - pixel_size, crest + pixel_size * 0.35, lift));
	body *= smoothstep(-pixel_size, 0.0, lift);
	body *= smoothstep(0.03 + rise * 0.24, 0.15 + rise * 0.24, fine);
	body *= 1.0 - smoothstep(0.75, 1.02, abs(dx));
	float rim = (1.0 - smoothstep(pixel_size * 0.35, pixel_size * 1.2, abs(lift))) * 0.38;
	float alpha = max(body, rim) * energy;
	float heat = clamp(0.88 - rise * 0.58 + (fine - 0.5) * 0.28, 0.0, 1.0);
	return vec2(heat, alpha);
}

void fragment() {
	vec2 local = (UV - 0.5) * radius * 2.0;
	vec2 p = (floor(local / pixel_size) + 0.5) * pixel_size;
	float t = floor(clock_time * 12.0) / 12.0;
	float scale = max(0.2, min(1.0, radius / 90.0));
	vec2 spacing = vec2(34.0, 23.0) * scale / sqrt(max(density, 0.05));
	spacing = max(spacing, vec2(pixel_size * 5.0));
	vec2 cell = floor(p / spacing);
	vec2 fire = vec2(0.0);
	// Nine nearby surface pockets merge into one translucent layer, avoiding
	// the opaque overlaps produced by stacking independent flame sprites.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = cell + vec2(float(x), float(y));
			float seed = hash(id);
			vec2 jitter = vec2(hash(id + 7.1), hash(id + 13.7)) - 0.5;
			vec2 center = (id + 0.5 + jitter * 0.65) * spacing;
			float width = spacing.x * mix(0.45, 0.76, seed);
			float dx = (p.x - center.x) / width;
			if (abs(dx) < 1.08) {
				float duration = mix(2.6, 5.3, hash(id + 27.0));
				float period = duration + mix(0.4, 1.2, hash(id + 48.0));
				float age = mod(t + seed * 17.0, period);
				float energy = smoothstep(0.0, 0.50, age) * (1.0 - smoothstep(duration * 0.72, duration, age));
				float edge = sqrt(max(1.0 - dx * dx, 0.0));
				float wrinkle = (noise(vec2(dx * 3.0 + seed * 9.0, t * 0.65)) - 0.5) * 8.0 * scale;
				float depth = spacing.y * mix(0.15, 0.27, hash(id + 19.0));
				float height = mix(12.0, 20.0, hash(id + 36.0)) * scale;
				float back_y = center.y - edge * depth + wrinkle;
				float front_y = center.y + edge * depth + wrinkle;
				vec2 back = flame_rim(p, back_y, dx, height, t, seed * 31.0, energy);
				vec2 front = flame_rim(p, front_y, dx, height * 0.8, t, seed * 31.0 + 12.0, energy);
				back.y *= 0.76;
				vec2 patch = front.y > back.y ? front : back;
				if (patch.y > fire.y) {
					fire = patch;
				}
			}
		}
	}
	float radial = length(p) / radius;
	float irregular = (noise(p / 29.0 + 21.0) - 0.5) * 0.13;
	float area = (1.0 - smoothstep(0.56, 0.87, radial + irregular));
	area *= step(length(local), radius) * step(0.001, density);
	vec3 color = vec3(0.69, 0.045, 0.010);
	color = mix(color, vec3(0.95, 0.18, 0.025), smoothstep(0.10, 0.42, fire.x));
	color = mix(color, vec3(1.0, 0.39, 0.065), smoothstep(0.45, 0.85, fire.x));
	color = mix(color, vec3(1.0, 0.68, 0.22), smoothstep(0.86, 1.0, fire.x));
	COLOR = vec4(color, fire.y * area) * item_color;
}
