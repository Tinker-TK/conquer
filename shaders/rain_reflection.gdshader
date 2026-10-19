shader_type canvas_item;
render_mode unshaded;

uniform float source_top = -50.0;
uniform float source_height = 100.0;
uniform float foot_y = 0.0;
uniform float gap = 1.0;
uniform float fade = 0.3;
varying float depth;
varying float reflected_y;

void vertex() {
	depth = 1.0 - clamp((VERTEX.y - source_top) / max(source_height, 1.0), 0.0, 1.0);
	reflected_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	COLOR.a *= (1.0 - depth * fade) * step(foot_y + gap, reflected_y);
}
