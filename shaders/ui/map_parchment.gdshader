shader_type canvas_item;
render_mode unshaded;

// 纸纹按控件的局部坐标铺设，不随整张长地图的 UV 一起拉伸。
uniform sampler2D paper_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_size : hint_range(128.0, 1024.0) = 512.0;
uniform vec3 paper_color_scale = vec3(1.0);
uniform vec2 surface_size = vec2(1920.0, 4400.0);
uniform float scroll_y = 0.0;
varying vec2 paper_position;
varying vec4 item_modulate;


void vertex() {
	paper_position = VERTEX;
	item_modulate = COLOR;
}


float torn_edge(float position, float phase) {
	return 24.0
		+ 12.0 * sin(position * 0.018 + phase)
		+ 9.0 * sin(position * 0.055 + phase * 1.8)
		+ 4.0 * sin(position * 0.15 + phase * 2.3)
		+ 1.6 * sin(position * 0.43 + phase * 0.7);
}


void fragment() {
	vec2 p = paper_position + vec2(0.0, scroll_y);
	// 纸面与撕边使用实际尺寸，不再从低清长图放大轮廓。
	float edge = min(min(p.x - torn_edge(p.y, 0.0), surface_size.x - torn_edge(p.y, 3.4) - p.x),
		min(p.y - torn_edge(p.x, 1.2), surface_size.y - torn_edge(p.x, 4.8) - p.y));
	vec2 paper_uv = 1.0 - abs(mod(p / tile_size, 2.0) - 1.0);
	vec3 paper = texture(paper_detail, paper_uv).rgb * paper_color_scale;
	float aged_edge = 1.0 - smoothstep(2.0, 30.0, edge);
	paper *= mix(vec3(1.0), vec3(0.86, 0.69, 0.46), aged_edge);
	float ink_edge = 1.0 - smoothstep(0.5, 3.0, edge);
	paper = mix(paper, vec3(0.19, 0.105, 0.045), ink_edge);
	float antialias = max(fwidth(edge), 0.35);
	float alpha = smoothstep(-antialias, antialias, edge);
	COLOR = vec4(paper, alpha) * item_modulate;
}
