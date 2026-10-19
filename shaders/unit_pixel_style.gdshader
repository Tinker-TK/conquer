shader_type canvas_item;
render_mode unshaded;

// 在当前帧的本地网格内采样，切图集帧时不会把相邻帧颜色带进来。
uniform float pixel_step : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform vec2 frame_origin = vec2(0.0);
uniform vec2 frame_size = vec2(384.0);
uniform bool match_palette = false;
uniform sampler2D source_palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform int palette_count : hint_range(1, 32) = 14;
// 保留单位现有受击参数，闪红在换色之后叠加。
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

vec3 palette_color(vec3 rgb) {
	vec3 result = rgb;
	float best = 1000.0;
	for (int index = 0; index < 32; index++) {
		if (index >= palette_count) {
			break;
		}
		vec2 palette_uv = vec2((float(index) + 0.5) / float(palette_count), 0.5);
		vec3 reference_rgb = texture(source_palette_texture, palette_uv).rgb;
		vec3 delta = reference_rgb - rgb;
		float distance = dot(delta * delta, vec3(0.3, 0.5, 0.2));
		if (distance < best) {
			best = distance;
			// 源色与目标色成对匹配，保持绿皮肤、皮革、木棒各自的阴影层次。
			result = texture(palette_texture, palette_uv).rgb;
		}
	}
	return result;
}

void fragment() {
	vec2 local_pixel = UV / TEXTURE_PIXEL_SIZE - frame_origin;
	float block_size = max(pixel_step, 1.0);
	// 采样落在原纹理像素中心，避免偶数网格落在像素边界而随图集 UV 精度跳色。
	vec2 snapped_pixel = floor(local_pixel / block_size) * block_size + floor(block_size * 0.5) + 0.5;
	snapped_pixel = clamp(snapped_pixel, vec2(0.5), frame_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, (frame_origin + snapped_pixel) * TEXTURE_PIXEL_SIZE);
	if (match_palette && sampled.a > 0.0) {
		sampled.rgb = palette_color(sampled.rgb);
	}
	sampled.rgb = mix(sampled.rgb, flash_color.rgb, flash_intensity);
	COLOR = sampled * sprite_tint;
}
