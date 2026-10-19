shader_type canvas_item;
render_mode unshaded;

// 0：不显示；1：整圈显示。
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// SelectionRing 当前尺寸是 270 × 220。
// 如果以后修改 TextureRect 的 Size，这里也要改成同样的值。
uniform vec2 draw_size = vec2(270.0, 220.0);

// 笔尖边缘的柔化范围。
uniform float edge_softness : hint_range(0.001, 0.08) = 0.018;

// 使用本节点局部坐标，而不是图集的 UV 坐标。
varying vec2 local_uv;

void vertex() {
	// VERTEX 是 TextureRect 内部的像素位置。
	// 除以节点尺寸后，左上是 (0, 0)，右下是 (1, 1)。
	local_uv = VERTEX / draw_size;
}

void fragment() {
	// 采样仍然使用 UV，保证 AtlasTexture 能正确取到红圈素材。
	vec4 tex = texture(TEXTURE, UV);

	// 画圈方向使用 local_uv：
	// 顶部 = 0 → 右侧 = 0.25 → 底部 = 0.5 → 左侧 = 0.75。
	vec2 p = local_uv - vec2(0.5);
	float angle = atan(p.x, -p.y);
	float clockwise = mod(angle, TAU) / TAU;

	// progress 之前的圆周保留，之后的圆周隐藏。
	float reveal = 1.0 - smoothstep(
		progress,
		progress + edge_softness,
		clockwise
	);

	// progress 为 0 时必须完全隐藏，避免顶部先露出一个点。
	if (progress <= 0.0) {
		reveal = 0.0;
	}

	COLOR = vec4(tex.rgb, tex.a * reveal) * COLOR;
}