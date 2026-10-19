shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform float coverage = 0.68;
uniform float snowline = 0.8;
uniform vec4 snow_tint : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform vec4 snow_shadow : source_color = vec4(0.55, 0.69, 0.82, 1.0);
uniform vec4 source_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
varying vec2 local_position;
varying vec4 sprite_tint;

void vertex() {
	local_position = VERTEX;
	sprite_tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 relative_uv = (UV - source_uv_rect.xy) / source_uv_rect.zw;
	vec2 p = floor(local_position / 3.0) * 3.0;
	float n = texture(noise_map, p / 320.0).r;
	float light = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float above = texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y * 3.0)).a;
	float exposed = 1.0 - above;
	// 亮部和朝上的轮廓先接雪；树干下部保持可见。
	float field = n * 0.55 + light * 0.5 + exposed * 0.22;
	float mask = step(mix(1.1, 0.24, coverage), field) * step(0.001, coverage);
	mask *= 1.0 - smoothstep(snowline - 0.12, snowline, relative_uv.y);
	vec3 snow = mix(snow_shadow.rgb, snow_tint.rgb, clamp(light * 1.4 + 0.25, 0.0, 1.0));
	COLOR = vec4(snow, base.a * mask) * sprite_tint;
}
