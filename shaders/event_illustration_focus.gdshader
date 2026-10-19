shader_type canvas_item;
render_mode unshaded;

// 四周融入浅色页面；中心叙事物件保留清晰度、饱和度与原始亮度。
uniform vec2 focal_point = vec2(0.50, 0.57);
uniform float core_radius : hint_range(0.1, 0.6) = 0.27;
uniform float fade_radius : hint_range(0.4, 1.0) = 0.69;
uniform float edge_feather : hint_range(0.01, 0.3) = 0.13;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float distance_from_focus = length((UV - focal_point) * vec2(1.0, 1.06));
	float focus = 1.0 - smoothstep(core_radius, fade_radius, distance_from_focus);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float feather = smoothstep(0.0, edge_feather, edge);
	float value = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
	ink.rgb = mix(vec3(value), ink.rgb, mix(0.58, 1.0, focus));
	ink.a *= feather * mix(0.24, 1.0, focus);
	COLOR = ink * vertex_tint;
}
