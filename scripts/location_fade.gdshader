shader_type canvas_item;
render_mode unshaded;

uniform float darkness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Edges darken slightly ahead of the center, with exact clear/black endpoints.
	vec2 centered_uv = (UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.15, 1.2, length(centered_uv));
	float coverage = darkness + edge * 0.16 * sin(darkness * 3.14159265);
	float opacity = smoothstep(0.0, 1.0, coverage);
	COLOR = vec4(vec3(0.0), opacity);
}
