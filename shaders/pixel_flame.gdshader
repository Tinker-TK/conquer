shader_type canvas_item;
render_mode unshaded;

// Fixed silhouette -> upward two-scale noise -> erosion -> five-color palette.
uniform vec2 draw_size = vec2(64.0, 80.0);
uniform float pixel_size = 1.0;
uniform float clock_time = 0.0;
uniform float animation_fps = 18.0;
uniform float flow_speed = 1.0;
uniform float distortion = 0.28;
uniform float erosion = 0.30;
uniform float wind = 0.0;
uniform float intensity = 1.0;
uniform float tall_shape = 0.0;
uniform float random_seed = 1.0;
uniform bool embers_enabled = true;
uniform bool glow_enabled = false;
uniform int debug_view = 0;
uniform bool use_shape_mask = false;
uniform sampler2D shape_mask : filter_nearest, repeat_disable;
uniform vec4 color_0 : source_color = vec4(0.12, 0.24, 0.28, 1.0);
uniform vec4 color_1 : source_color = vec4(0.20, 0.40, 0.44, 1.0);
uniform vec4 color_2 : source_color = vec4(0.32, 0.59, 0.60, 1.0);
uniform vec4 color_3 : source_color = vec4(0.52, 0.79, 0.77, 1.0);
uniform vec4 color_4 : source_color = vec4(0.76, 0.94, 0.87, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.03 + vec2(8.1, 3.7)) * 0.35;
}

float silhouette(vec2 p) {
	float height = mix(0.52, 0.70, tall_shape) * mix(0.65, 1.0, clamp(intensity, 0.0, 1.5));
	float h = (0.89 - p.y) / height;
	float width = mix(0.30 * pow(max(1.0 - h, 0.0), 0.85),
		0.24 * pow(max(1.0 - h, 0.0), 1.35), tall_shape);
	width += sin(clamp(h, 0.0, 1.0) * PI) * 0.08 * (1.0 - tall_shape);
	width *= sqrt(clamp(h / 0.13, 0.0, 1.0));
	width *= mix(0.5, 1.0, clamp(intensity, 0.0, 1.0));
	float field = 1.0 - abs(p.x - 0.5) / max(width, 0.001);
	return field * step(0.0, h) * step(h, 1.0);
}

vec4 palette(float heat) {
	vec4 result = color_0;
	result = mix(result, color_1, step(0.24, heat));
	result = mix(result, color_2, step(0.43, heat));
	result = mix(result, color_3, step(0.64, heat));
	return mix(result, color_4, step(0.84, heat));
}

void fragment() {
	vec2 grid = max(draw_size / max(pixel_size, 0.5), vec2(4.0));
	vec2 uv = (floor(UV * grid) + 0.5) / grid;
	float t = floor(clock_time * animation_fps) / animation_fps * flow_speed;
	vec2 drift = vec2(random_seed * 7.13, t * 0.72);
	float coarse = fbm(uv * vec2(3.8, 2.6) + drift);
	float fine = fbm(uv * vec2(8.0, 5.5) + drift * vec2(1.7, 1.45) + vec2(19.0));
	float height = mix(0.52, 0.70, tall_shape) * mix(0.65, 1.0, clamp(intensity, 0.0, 1.5));
	float rise = clamp((0.89 - uv.y) / height, 0.0, 1.0);
	vec2 displaced = uv;
	displaced.x += (coarse - 0.5) * distortion * mix(0.12, 1.15, rise);
	displaced.x -= wind * 0.21 * rise * rise;
	displaced.y += (fine - 0.5) * distortion * 0.11 * rise;
	float body = silhouette(displaced);
	if (use_shape_mask) {
		float inside = step(0.0, displaced.x) * step(displaced.x, 1.0)
			* step(0.0, displaced.y) * step(displaced.y, 1.0);
		vec4 mask = texture(shape_mask, clamp(displaced, vec2(0.0), vec2(1.0)));
		body = mask.r * mask.a * inside;
	}
	float contour = body - (fine - 0.28) * erosion * mix(0.18, 1.65, rise);
	float heat = body * mix(0.61, 0.88, 1.0 - rise) + (1.0 - rise) * 0.12;
	heat -= (fine - 0.3) * erosion * 0.85;
	float alpha = step(0.13, contour) * step(0.01, body);
	vec4 flame = palette(clamp(heat, 0.0, 1.0));
	flame.a *= alpha;
	float ember = 0.0;
	if (embers_enabled && debug_view == 0) {
		for (int i = 0; i < 8; i++) {
			float fi = float(i);
			float duration = mix(1.3, 2.7, hash(vec2(fi, random_seed)));
			float cycle = t / duration + hash(vec2(fi, 3.7));
			float life = fract(cycle);
			float origin = hash(vec2(fi + random_seed, floor(cycle)));
			vec2 pos = vec2(0.5 + (origin - 0.5) * 0.32 + wind * life * 0.12,
				0.62 - life * 0.53);
			pos.x += sin(life * 6.0 + fi * 2.0) * 0.025;
			pos = (floor(pos * grid) + 0.5) / grid;
			vec2 d = abs(uv - pos) * grid;
			float spark = step(d.x, 0.51) * step(d.y, mix(1.51, 0.51, life));
			ember = max(ember, spark * step(0.16, life) * step(life, 0.91));
		}
	}
	float halo = 0.0;
	if (glow_enabled && debug_view == 0) {
		vec2 delta = (uv - vec2(0.5, 0.62)) * vec2(1.0, 0.85);
		halo = pow(max(0.0, 1.0 - length(delta) / 0.48), 3.0) * 0.18;
	}
	vec4 result = vec4(color_2.rgb, halo);
	result = mix(result, flame, step(0.01, flame.a));
	result = mix(result, vec4(color_3.rgb, 1.0), ember);
	if (debug_view == 1) {
		result = vec4(vec3(1.0), alpha);
	} else if (debug_view == 2) {
		result = vec4(vec3(coarse), 1.0);
	} else if (debug_view == 3) {
		result = vec4(vec3(fine), 1.0);
	} else if (debug_view == 4) {
		result = vec4(vec3(clamp(heat, 0.0, 1.0)), alpha);
	}
	result.a *= clamp(intensity, 0.0, 1.0);
	COLOR = result * item_color;
}
