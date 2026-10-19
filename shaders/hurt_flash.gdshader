shader_type canvas_item;

// 受击闪红强度：0 = 正常，1 = 全红。从外部用 set_shader_parameter 控制
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
// 闪红颜色（默认红色，可调）
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

void fragment() {
    // 把贴图颜色向 flash_color 方向混合，flash_intensity 越大越红
    vec4 flash = mix(COLOR, flash_color, flash_intensity);
    // 保留贴图自身的透明度（闪红不改变 alpha）
    COLOR = vec4(flash.rgb, COLOR.a);
}