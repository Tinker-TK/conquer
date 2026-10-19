shader_type canvas_item;
render_mode unshaded, blend_mul;

// Multiply the ground already drawn beneath this pass: no replacement grass texture
// and no screen copy that could accidentally capture units or the previous frame.
uniform float radius = 200.0;
uniform float pixel_size = 2.0;
uniform float burn_amount = 0.86;
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

void fragment() {
	vec2 local = (UV - 0.5) * radius * 2.0;
	float block_size = min(pixel_size, max(radius * 0.25, 1.0));
	vec2 p = (floor(local / block_size) + 0.5) * block_size;
	float radial = length(p) / radius;
	float patches = noise(p / 43.0 + pattern_seed);
	float flecks = noise(p / 13.0 + 19.0);
	float edge = radial + (patches - 0.5) * 0.28 + (flecks - 0.5) * 0.08;
	float dry = (1.0 - smoothstep(0.62, 0.98, edge)) * step(radial, 1.0);
	float charred = (1.0 - smoothstep(0.38, 0.87, edge)) * mix(0.72, 1.0, patches);
	charred *= step(radial, 1.0) * burn_amount;
	// Dry brown grass around irregular soot patches. Original ground pixels survive.
	vec3 factor = mix(vec3(1.0), vec3(0.78, 0.59, 0.43), dry * 0.64 * burn_amount);
	factor = mix(factor, vec3(0.20, 0.19, 0.21), charred);
	float grain = hash(floor(p / block_size));
	float ash = step(0.94, grain) * step(0.56, charred);
	factor = mix(factor, vec3(0.64, 0.60, 0.54), ash * 0.30);
	// Only a few isolated embers; no connected luminous cracks or molten pools.
	float t = floor(clock_time * 12.0) / 12.0;
	float ember = step(0.991, grain) * step(0.44, charred);
	ember *= 0.45 + 0.55 * max(0.0, sin(t * 2.1 + grain * 79.0 + p.x * 0.13));
	factor = mix(factor, vec3(1.0, 0.17, 0.035), ember);
	// White multiplication outside the mask leaves all underlying pixels untouched.
	COLOR = vec4(mix(vec3(1.0), factor, item_color.a), 1.0);
}
