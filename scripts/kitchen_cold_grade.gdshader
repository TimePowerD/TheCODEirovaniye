shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 blue_grade = source.rgb * vec3(0.62, 0.82, 1.12);
	blue_grade = mix(blue_grade, vec3(luminance * 0.52, luminance * 0.76, luminance * 1.16), 0.28);
	COLOR = vec4(mix(source.rgb, blue_grade, amount), source.a);
}
