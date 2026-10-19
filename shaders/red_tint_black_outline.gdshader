shader_type canvas_item;

// 选中时的主体颜色；默认纯红，也可以改成蓝色、金色等阵营提示色。
uniform vec4 tint_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
// 1.0 是贴图原色，0.0 是纯 tint_color；保留一点原图明暗会更容易看清角色细节。
uniform float tint_strength : hint_range(0.0, 1.0, 0.01) = 0.85;

// 黑色描边的颜色与宽度。宽度以贴图像素为单位，像素风角色建议先用 1.0 或 2.0。
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0, 0.1) = 1.0;

void fragment() {
	vec4 sprite_color = texture(TEXTURE, UV) * COLOR;

	// 在透明像素周围的八个方向采样：只要邻近位置有角色像素，当前位置就绘制描边。
	// TEXTURE_PIXEL_SIZE 会随贴图分辨率自动换算，避免不同尺寸角色的描边错位。
	vec2 offset = TEXTURE_PIXEL_SIZE * outline_width;
	float nearby_alpha = 0.0;
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-offset.x, -offset.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2( 0.0,      -offset.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2( offset.x, -offset.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-offset.x,  0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2( offset.x,  0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-offset.x,  offset.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2( 0.0,       offset.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2( offset.x,  offset.y)).a);

	if (sprite_color.a > 0.0) {
		// 保留原图的亮暗关系，再向红色混合，避免角色变成没有细节的一整块红色。
		float brightness = dot(sprite_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 red_tinted = brightness * tint_color.rgb;
		COLOR = vec4(mix(sprite_color.rgb, red_tinted, tint_strength), sprite_color.a);
	} else if (nearby_alpha > 0.0) {
		// 只有原图透明、附近有角色像素的位置才显示黑边，角色主体不会被黑边覆盖。
		COLOR = vec4(outline_color.rgb, nearby_alpha * outline_color.a);
	} else {
		COLOR = vec4(0.0);
	}
}
