shader_type canvas_item;
render_mode unshaded;

// 普通 CanvasItem 的圆角光框，不依赖场景开启 Bloom。
uniform vec4 glow_color : source_color = vec4(0.18, 1.0, 0.76, 1.0);
uniform vec2 panel_size = vec2(306.0, 392.0);
uniform vec2 card_half_size = vec2(124.0, 167.0);
uniform float corner_radius = 13.0;
uniform float strength = 0.0;

void fragment() {
    vec2 point = (UV - vec2(0.5)) * panel_size;
    vec2 edge = abs(point) - card_half_size + vec2(corner_radius);
    float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - corner_radius;
    float outside = max(distance_to_edge, 0.0);
    float halo = exp(-outside / 7.5) * smoothstep(-3.0, 2.0, distance_to_edge);
    float rim = exp(-abs(distance_to_edge) / 1.8);
    float pulse = 0.84 + 0.16 * sin(TIME * 3.5 + UV.y * 2.0);
    COLOR = vec4(glow_color.rgb, clamp((halo * 0.55 + rim * 0.65) * pulse * strength, 0.0, 0.95));
}
