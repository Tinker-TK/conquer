shader_type canvas_item;
render_mode unshaded;

uniform sampler2D height_map : repeat_disable, filter_nearest;
uniform sampler2D bed_map : source_color, repeat_enable, filter_nearest;
uniform sampler2D reflection_map : repeat_disable, filter_linear;
uniform sampler2D ripple_map : repeat_disable, filter_linear;
uniform sampler2D cell_level_map : repeat_disable, filter_nearest;
uniform vec4 cell_level_rect;
uniform bool use_cell_levels = false;
uniform vec4 local_rect;
uniform vec4 reflection_rect;
uniform bool has_bed_texture = false;
uniform bool has_weather = false;
uniform float clock_time = 0.0;
uniform float water_level = 0.66;
uniform float pixel_size = 2.0;
uniform float bank_slope = 40.0;
uniform float bed_scale = 128.0;
uniform float random_seed = 1303.0;
uniform vec4 bed_color : source_color = vec4(0.36, 0.40, 0.34, 1.0);
uniform vec4 bank_color : source_color = vec4(0.32, 0.29, 0.21, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.29, 0.47, 0.51, 1.0);
uniform vec4 deep_color : source_color = vec4(0.13, 0.29, 0.37, 1.0);
uniform float shallow_opacity = 0.22;
uniform float deep_opacity = 0.72;
uniform vec2 flow_velocity = vec2(18.0, 4.0);
uniform float wave_scale = 64.0;
uniform float refraction = 1.6;
uniform float caustics_strength = 0.20;
uniform vec4 foam_color : source_color = vec4(0.84, 0.93, 0.89, 0.85);
uniform float foam_width = 2.0;
uniform float shore_motion = 0.012;
uniform float reflection_opacity = 0.30;
varying vec2 local_position;
varying vec2 world_position;

vec2 hash2(vec2 p) {
	p += vec2(random_seed * 0.001, random_seed * 0.003);
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i).x, hash2(i + vec2(1, 0)).x, u.x),
		mix(hash2(i + vec2(0, 1)).x, hash2(i + vec2(1, 1)).x, u.x), u.y);
}

// 到最近/次近碎石中心的距离差：静态河床裂缝，也用于流动焦散细线。
vec2 stones(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float first = 9.0;
	float second = 9.0;
	float shade = 0.5;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 q = vec2(float(x), float(y));
			vec2 h = hash2(cell + q);
			float d = length(q + 0.18 + h * 0.64 - f);
			if (d < first) {
				second = first;
				first = d;
				shade = h.x;
			} else {
				second = min(second, d);
			}
		}
	}
	return vec2(second - first, shade);
}

vec4 height_sample_at(vec2 p) {
	vec2 uv = clamp((p - local_rect.xy) / local_rect.zw, vec2(0.0), vec2(1.0));
	ivec2 size = textureSize(height_map, 0);
	ivec2 pixel = clamp(ivec2(floor(uv * vec2(size) + vec2(0.0001))), ivec2(0), size - ivec2(1));
	return texelFetch(height_map, pixel, 0);
}

float height_at(vec2 p) {
	return height_sample_at(p).r;
}

vec3 river_bed(vec2 p) {
	float h = height_at(p);
	vec2 stone = stones(p / 13.0);
	float seams = smoothstep(0.015, 0.09, stone.x);
	float grain = noise(p / 4.0);
	vec3 floor_color = bed_color.rgb * mix(0.65, 1.25, stone.y) * mix(0.65, 1.0, seams);
	floor_color += (grain - 0.5) * 0.035;
	vec3 bank = bank_color.rgb * mix(0.6, 1.3, stone.y) * mix(0.5, 1.0, seams);
	vec3 result = mix(floor_color, bank, smoothstep(0.65, 0.96, h));
	if (has_bed_texture) {
		result = mix(result, texture(bed_map, p / bed_scale).rgb, 0.85);
	}
	return result;
}

void vertex() {
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(local_position / pixel_size) * pixel_size;
	vec2 uv = (p - local_rect.xy) / local_rect.zw;
	vec4 height_sample = height_sample_at(p);
	float h = height_sample.r;
	float level = water_level;
	if (use_cell_levels) {
		vec2 cell_uv = clamp((p - cell_level_rect.xy) / max(cell_level_rect.zw, vec2(1.0)), vec2(0.0), vec2(1.0));
		ivec2 size = textureSize(cell_level_map, 0);
		ivec2 pixel = clamp(ivec2(floor(cell_uv * vec2(size) + vec2(0.0001))), ivec2(0), size - ivec2(1));
		vec4 cell = texelFetch(cell_level_map, pixel, 0);
		level = mix(level, cell.r, step(0.5, cell.g));
	}
	// 水位阈值只采静态高度；边缘噪声仅影响高光，不推动整条河岸。
	float wet = step(h, level) * step(0.0001, level);
	float depth = max(level - h, 0.0);
	vec2 flow = (p - clock_time * flow_velocity) / wave_scale;
	vec2 wave = vec2(noise(flow), noise(flow + vec2(11.7, 3.2))) - 0.5;
	vec2 offset = wave * refraction * depth * 2.0;
	float ripple = 0.0;
	vec2 weather_uv = (world_position - reflection_rect.xy) / max(reflection_rect.zw, vec2(1.0));
	bool inside_weather = all(greaterThanEqual(weather_uv, vec2(0.0))) && all(lessThanEqual(weather_uv, vec2(1.0)));
	if (has_weather && inside_weather) {
		vec2 texel = 2.0 / max(reflection_rect.zw, vec2(1.0));
		offset += vec2(texture(ripple_map, weather_uv + vec2(texel.x, 0)).g - texture(ripple_map, weather_uv - vec2(texel.x, 0)).g,
			texture(ripple_map, weather_uv + vec2(0, texel.y)).g - texture(ripple_map, weather_uv - vec2(0, texel.y)).g) * refraction * 2.0;
		ripple = texture(ripple_map, weather_uv).r;
	}
	vec3 bed = river_bed(p);
	vec3 under_water = river_bed(p + offset);
	float deep = smoothstep(0.0, 0.70, depth);
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, deep);
	vec3 water = mix(under_water, water_color, mix(shallow_opacity, deep_opacity, deep));
	float caustic = 1.0 - smoothstep(0.015, 0.075, stones(flow * 3.3 + wave * 0.4).x);
	water += vec3(0.34, 0.53, 0.52) * caustic * caustics_strength * smoothstep(0.01, 0.12, depth) * (1.0 - deep * 0.6);
	if (has_weather && inside_weather) {
		vec4 reflected = texture(reflection_map, clamp(weather_uv + offset / reflection_rect.zw, vec2(0), vec2(1)));
		water = mix(water, reflected.rgb / max(reflected.a, 0.001), reflected.a * reflection_opacity);
		water += vec3(0.12, 0.16, 0.16) * ripple;
	}
	float foam_depth = foam_width / max(bank_slope, 1.0);
	float motion = (noise((p - clock_time * flow_velocity * 0.6) / vec2(32.0, 8.0)) - 0.5) * shore_motion;
	float foam = (1.0 - smoothstep(foam_depth, foam_depth + pixel_size / max(bank_slope, 1.0), depth + motion)) * wet;
	foam *= step(0.001, foam_width) * mix(0.5, 1.0, noise(flow * 2.0));
	water = mix(water, foam_color.rgb, foam * foam_color.a);
	COLOR = vec4(mix(bed, water, wet), height_sample.a);
}
