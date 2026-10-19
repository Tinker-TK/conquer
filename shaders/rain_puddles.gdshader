shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ground_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform sampler2D edge_noise_map : repeat_enable, filter_linear;
uniform sampler2D sky_map : source_color, repeat_enable, filter_linear;
uniform sampler2D scene_cloud_map : source_color, repeat_enable, filter_nearest;
uniform sampler2D ground_mask : repeat_disable, filter_nearest;
uniform sampler2D reflection_map : repeat_disable, filter_linear;
uniform sampler2D ripple_map : repeat_disable, filter_linear;
uniform vec4 world_rect;
uniform vec2 screen_zoom = vec2(1.0);
uniform float clock_time = 0.0;
uniform float coverage = 0.52;
uniform float edge_softness = 0.025;
uniform float edge_noise_strength = 0.10;
uniform vec2 edge_noise_speed = vec2(12.0, -8.0);
uniform float edge_width = 3.0;
uniform vec4 edge_color : source_color = vec4(0.72, 0.84, 0.86, 0.75);
uniform float wetness = 0.7;
uniform float depth_opacity = 0.65;
uniform vec4 water_tint : source_color = vec4(0.30, 0.43, 0.55, 1.0);
uniform float sky_strength = 0.36;
uniform float sky_cloud_strength = 0.65;
uniform float sky_scale = 800.0;
uniform vec2 sky_scroll_offset = vec2(0.0);
uniform bool has_sky_texture = false;
uniform bool has_scene_clouds = false;
uniform float reflection_opacity = 0.48;
uniform float distortion = 1.2;
uniform float pixel_size = 2.0;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float puddle_field(vec2 p) {
	// 主体轮廓和深浅透明度始终采样静态世界坐标。
	return texture(noise_map, p / 1024.0).r;
}

void fragment() {
	vec2 p = floor(world_position / pixel_size) * pixel_size;
	vec2 local_uv = (p - world_rect.xy) / world_rect.zw;
	float land = texture(ground_mask, (world_position - world_rect.xy) / world_rect.zw).r;
	float n = puddle_field(p);
	float threshold = mix(0.72, 0.28, coverage);
	float water_body = smoothstep(threshold - edge_softness, threshold + edge_softness, n);
	float water = water_body * land * step(0.001, coverage);
	vec2 texel = 1.0 / world_rect.zw;
	vec2 wave = vec2(
		texture(ripple_map, local_uv + vec2(texel.x * 2.0, 0.0)).g - texture(ripple_map, local_uv - vec2(texel.x * 2.0, 0.0)).g,
		texture(ripple_map, local_uv + vec2(0.0, texel.y * 2.0)).g - texture(ripple_map, local_uv - vec2(0.0, texel.y * 2.0)).g
	);
	// 只在实际落雨/脚步波纹附近折射，移除整片水面同向运动的正弦波。
	vec2 offset = wave * 3.0 * distortion;
	vec3 ground = texture(ground_screen, SCREEN_UV + offset * SCREEN_PIXEL_SIZE * screen_zoom).rgb;
	// 只有天空颜色层缓慢移动；水洼主体与深浅透明度仍采样静态 p。
	vec2 sky_position = p + offset - sky_scroll_offset;
	float cloud = texture(noise_map, sky_position / 1024.0 * 1.67).r;
	if (has_sky_texture) {
		vec3 sky_sample = texture(sky_map, sky_position / sky_scale).rgb;
		cloud = smoothstep(0.35, 0.85, dot(sky_sample, vec3(0.299, 0.587, 0.114)));
	}
	vec3 sky = water_tint.rgb * mix(0.8, 1.2, cloud);
	// 云层只在天空反射内柔和混合；物体倒影在它之后合成。
	vec3 cloud_tint = mix(water_tint.rgb, vec3(0.72, 0.8, 0.84), 0.65);
	if (!has_scene_clouds) {
		sky = mix(sky, cloud_tint, cloud * sky_cloud_strength);
	}
	vec3 result = mix(ground, sky, sky_strength);
	if (has_scene_clouds) {
		// 云图保存原精灵的直通 RGB/Alpha；独立透明度避免与天空强度连乘而过淡。
		vec4 scene_cloud = texture(scene_cloud_map, sky_position / sky_scale);
		result = mix(result, scene_cloud.rgb, scene_cloud.a * sky_cloud_strength);
	}
	vec4 reflected = texture(reflection_map, clamp(local_uv + offset * texel, vec2(0.0), vec2(1.0)));
	// 离屏画布是预乘透明度；恢复颜色，避免倒影在边缘变黑。
	vec3 reflection_color = reflected.rgb / max(reflected.a, 0.001);
	result = mix(result, reflection_color, reflected.a * reflection_opacity);
	// R 是清晰可见的环；G 是较宽的柔和高度场，求梯度用于折射。
	float ring = texture(ripple_map, local_uv).r;
	result += vec3(0.09, 0.13, 0.16) * ring * wetness;
	if (edge_width > 0.0 && edge_color.a > 0.0) {
		// 按世界坐标估计梯度，把宽度转换成噪声阈值带；缩放不会改变实际宽度。
		float sample_step = max(pixel_size, 2.0);
		vec2 gradient = vec2(
			puddle_field(p + vec2(sample_step, 0.0)) - puddle_field(p - vec2(sample_step, 0.0)),
			puddle_field(p + vec2(0.0, sample_step)) - puddle_field(p - vec2(0.0, sample_step))
		) / (2.0 * sample_step);
		float distance_inside = max((n - threshold) / max(length(gradient), 0.0001), 0.0);
		float detail = texture(edge_noise_map, (p + clock_time * edge_noise_speed) / 256.0).r;
		float rim_width = edge_width * clamp(1.0 + (detail - 0.5) * edge_noise_strength * 10.0, 0.25, 2.0);
		float fragments = mix(1.0, smoothstep(0.15, 0.65, detail), clamp(edge_noise_strength * 10.0, 0.0, 1.0));
		float shore = water_body * (1.0 - smoothstep(rim_width, rim_width + pixel_size, distance_inside)) * fragments;
		result = mix(result, edge_color.rgb, shore * edge_color.a);
	}
	float depth = smoothstep(threshold, min(threshold + 0.18, 1.0), n);
	COLOR = vec4(result, water * wetness * mix(1.0, depth, depth_opacity));
}
