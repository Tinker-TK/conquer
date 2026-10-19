shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ground_screen : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D ground_mask : repeat_disable, filter_nearest;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform vec4 world_rect;
uniform float coverage = 0.68;
uniform float pixel_size = 3.0;
uniform float ground_detail = 0.3;
uniform vec4 snow_tint : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform vec4 snow_shadow : source_color = vec4(0.55, 0.69, 0.82, 1.0);
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(world_position / pixel_size) * pixel_size;
	float n = texture(noise_map, p / 1024.0).r;
	// 噪声固定在世界坐标；只推阈值，就能让同一雪斑逐渐扩张或收缩。
	float threshold = mix(1.0, 0.0, coverage);
	float covered = step(threshold, n) * step(0.001, coverage);
	float land = texture(ground_mask, (world_position - world_rect.xy) / world_rect.zw).r;
	vec3 original = texture(ground_screen, SCREEN_UV).rgb;
	float detail = dot(original, vec3(0.299, 0.587, 0.114));
	float grain = texture(noise_map, p / 1024.0 * 7.1).r;
	vec3 snow = mix(snow_shadow.rgb, snow_tint.rgb, 0.78 + 0.22 * grain);
	snow *= mix(1.0, 0.55 + detail, ground_detail);
	// 薄薄的蓝色阴影让像素雪斑边缘更容易辨认。
	float edge = 1.0 - step(threshold + 0.025, n);
	snow = mix(snow, snow_shadow.rgb, edge * 0.28);
	COLOR = vec4(snow, land * covered * snow_tint.a);
}
