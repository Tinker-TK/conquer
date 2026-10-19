shader_type canvas_item;
render_mode unshaded;

// Eleven layered billows plus two dark rear billows; all shading stays inside the union.
const vec4 BLOBS[13] = {
	vec4(-23.0, -24.0, 11.0, 8.0), vec4(-24.0, -15.0, 17.0, 13.0),
	vec4(-18.0, -7.0, 22.0, 15.0), vec4(-8.0, -10.0, 18.0, 12.0),
	vec4(-29.0, 6.0, 18.0, 11.0), vec4(-9.0, 8.0, 21.0, 13.0),
	vec4(9.0, 9.0, 23.0, 11.0), vec4(26.0, 11.0, 17.0, 8.0),
	vec4(37.0, 13.0, 10.0, 6.0), vec4(-46.0, 12.0, 6.0, 4.0),
	vec4(45.0, 15.0, 6.0, 4.0), vec4(-10.0, 18.0, 24.0, 5.0),
	vec4(22.0, 20.0, 23.0, 5.0)
};

uniform vec2 draw_size = vec2(136.0, 80.0);
uniform vec2 cloud_size = vec2(112.0, 58.0);
uniform float pixel_size = 1.0;
uniform float clock_time = 0.0;
uniform float animation_fps = 16.0;
uniform float roll_speed = 0.65;
uniform float roll_amount = 1.0;
uniform float edge_noise = 1.8;
uniform float shade_noise = 1.0;
uniform float random_seed = 11.0;
uniform float flash_amount = 0.0;
uniform vec2 flash_position = vec2(-9.0, 13.0);
uniform int debug_view = 0;
uniform vec4 dark_color : source_color = vec4(0.12, 0.15, 0.19, 1.0);
uniform vec4 body_color : source_color = vec4(0.24, 0.28, 0.34, 1.0);
uniform vec4 light_color : source_color = vec4(0.35, 0.39, 0.46, 1.0);
uniform vec4 flash_color : source_color = vec4(0.49, 0.78, 0.80, 1.0);
uniform vec4 flash_core : source_color = vec4(0.86, 0.93, 0.88, 1.0);
varying vec4 item_color;

void vertex() { item_color = COLOR; }

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

vec4 animated_blob(int index, float t) {
	vec4 blob = BLOBS[index];
	float phase = float(index) * 2.31 + random_seed * 0.71;
	blob.xy += vec2(sin(t * 0.9 + phase) * 1.4, cos(t * 0.67 + phase) * 0.9) * roll_amount;
	blob.zw *= 1.0 + sin(t * 0.8 + phase + 1.7) * 0.065 * roll_amount;
	return blob;
}

void fragment() {
	vec2 grid = max(draw_size / max(pixel_size, 1.0), vec2(4.0));
	vec2 uv = (floor(UV * grid) + 0.5) / grid;
	vec2 p = (uv - 0.5) * draw_size / (cloud_size / vec2(112.0, 58.0));
	float t = floor(clock_time * animation_fps) / animation_fps * roll_speed;
	vec2 drift = vec2(t * 0.19, -t * 0.14) + random_seed * 2.7;
	float coarse = noise(p * 0.13 + drift);
	float fine = noise(p * 0.36 - drift * 0.8 + vec2(17.0));
	vec2 q = p + vec2(coarse - 0.5, fine - 0.5) * edge_noise * 2.0;
	if (debug_view == 1) { q = p; }
	float visible = 0.0;
	float outline = 0.0;
	float owner = -1.0;
	float shade = 0.0;
	float flash_weight = 0.0;
	// Dark rear billows are painted first; the front billows cover their upper portion.
	for (int order = 0; order < 13; order++) {
		int index = order < 2 ? order + 11 : order - 2;
		vec4 blob = debug_view == 1 ? BLOBS[index] : animated_blob(index, t);
		vec2 local = (q - blob.xy) / blob.zw;
		float edge = length(local);
		outline = max(outline, 1.0 - step(0.045, abs(edge - 1.0)));
		if (edge < 1.0) {
			visible = 1.0;
			owner = float(index);
			float ripple = (coarse - 0.5) * shade_noise * 0.62 + (fine - 0.5) * shade_noise * 0.43;
			float bottom = local.y + ripple;
			float inner = length((q - blob.xy - blob.zw * vec2(0.15, 0.20)) / (blob.zw * vec2(0.76, 0.65)));
			shade = bottom > 0.52 ? 0.0 : 1.0;
			if (inner + ripple > 1.0 && local.y < 0.35) { shade = 2.0; }
			if (index >= 11) { shade = 0.0; }
			float distance_to_flash = length((blob.xy - flash_position) / vec2(24.0, 19.0));
			flash_weight = exp(-distance_to_flash * distance_to_flash * 1.8);
		}
	}
	vec4 result = shade < 0.5 ? dark_color : (shade < 1.5 ? body_color : light_color);
	float energy = clamp(flash_amount * flash_weight, 0.0, 1.5);
	if (debug_view == 0 || debug_view == 4) {
		vec3 lit = mix(flash_color.rgb, flash_core.rgb, clamp((energy - 0.7) * 1.6 + shade * 0.10, 0.0, 1.0));
		result.rgb = mix(result.rgb, lit, clamp(energy, 0.0, 1.0));
	}
	result.a *= visible;
	if (debug_view == 1) {
		result = vec4(mix(body_color.rgb, light_color.rgb, fract(owner * 0.31)), visible * 0.8);
		result = mix(result, vec4(0.85, 0.67, 0.39, 1.0), outline);
	} else if (debug_view == 2) {
		result = vec4(vec3(1.0), visible);
	} else if (debug_view == 4) {
		result.a *= clamp(energy, 0.0, 1.0);
	} else if (debug_view == 5) {
		result = vec4(vec3(coarse * 0.65 + fine * 0.35), 1.0);
	}
	COLOR = result * item_color;
}
