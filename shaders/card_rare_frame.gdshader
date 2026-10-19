shader_type canvas_item;
varying vec4 frame_tint;

void vertex() {
	frame_tint = COLOR;
}

// 仅把边框中的蓝色改为金色，保留原来的明暗、装饰和透明轮廓。
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float blue_mask = smoothstep(0.02, 0.16, base.b - base.r);
	float lightness = max(base.r, max(base.g, base.b));
	vec3 gold = mix(vec3(0.30, 0.13, 0.025), vec3(1.0, 0.83, 0.35), lightness);
	COLOR = vec4(mix(base.rgb, gold, blue_mask), base.a) * frame_tint;
}
