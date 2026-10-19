shader_type canvas_item;
render_mode unshaded;

uniform float flake_scale = 1.6;
uniform float clock_time = 0.0;

void vertex() {
	// 随机选择 3×3 图集中的一个形状，在整个生命周期保持该形状。
	float frame = min(floor(INSTANCE_CUSTOM.z * 9.0), 8.0);
	UV = (UV + vec2(mod(frame, 3.0), floor(frame / 3.0))) / 3.0;
	vec2 scale = vec2(length((CANVAS_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy),
		length((CANVAS_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy));
	VERTEX *= flake_scale / (3.0 * max(scale, vec2(0.001)));
	VERTEX.x += sin(clock_time * 1.5 + INSTANCE_CUSTOM.z * 30.0) * 2.0 / max(scale.x, 0.001);
}
