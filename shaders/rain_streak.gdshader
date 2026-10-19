shader_type canvas_item;
render_mode unshaded;

void vertex() {
	// CANVAS_MATRIX 包含实际绘制的镜头与视口缩放。只补偿雨丝的尺寸，
	// 粒子位置/速度仍在世界中，镜头移动不会让雨滴粘在屏幕上。
	vec2 axis_x = (CANVAS_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
	vec2 axis_y = (CANVAS_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	VERTEX /= max(vec2(length(axis_x), length(axis_y)), vec2(0.001));
}
