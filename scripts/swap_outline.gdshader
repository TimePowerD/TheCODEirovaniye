shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform float outline_width = 0.035;

void vertex() {
	VERTEX += normalize(VERTEX) * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
