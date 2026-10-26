shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.03) = 0.006;
uniform float chromatic_strength : hint_range(0.0, 0.02) = 0.003;
uniform float blur_strength : hint_range(0.0, 0.02) = 0.004;
uniform float desaturation_strength : hint_range(0.0, 1.0) = 0.28;
uniform float double_vision_strength : hint_range(0.0, 0.25) = 0.055;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float noise_strength : hint_range(0.0, 0.1) = 0.018;

float screen_noise(vec2 pixel, float time_value) {
	return fract(sin(dot(pixel + vec2(time_value * 17.0, time_value * 29.0), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 original = texture(screen_texture, uv);
	if (intensity <= 0.0001) {
		COLOR = original;
	} else {

	float edge = smoothstep(0.12, 1.1, length((uv - vec2(0.5)) * 2.0));
	float time_value = TIME;
	float distortion_pulse = 0.68 + 0.32 * (0.5 + 0.5 * sin(time_value * 0.52));
	float chroma_pulse = 0.62 + 0.38 * (0.5 + 0.5 * sin(time_value * 0.37 + 1.2));
	float blur_pulse = 0.48 + 0.52 * (0.5 + 0.5 * sin(time_value * 0.43 + 2.1));
	float echo_pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(time_value * 0.31 + 0.6));
	vec2 wave = vec2(
		sin(uv.y * 8.0 + time_value * 0.18),
		cos(uv.x * 7.0 - time_value * 0.15)
	);
	vec2 distorted_uv = clamp(uv + wave * edge * distortion_strength * intensity * distortion_pulse, vec2(0.001), vec2(0.999));
	vec2 radial = distorted_uv - vec2(0.5);
	float chroma = chromatic_strength * edge * intensity * chroma_pulse;
	vec3 color = texture(screen_texture, distorted_uv).rgb;
	color.r = texture(screen_texture, clamp(distorted_uv + radial * chroma, vec2(0.001), vec2(0.999))).r;
	color.b = texture(screen_texture, clamp(distorted_uv - radial * chroma, vec2(0.001), vec2(0.999))).b;

	// Two nearby current-frame samples soften only the outer field of view.
	float blur = blur_strength * edge * intensity * blur_pulse;
	vec2 blur_offset = vec2(blur, blur * 0.62);
	vec3 soft_color = (
		color +
		texture(screen_texture, clamp(distorted_uv + blur_offset, vec2(0.001), vec2(0.999))).rgb +
		texture(screen_texture, clamp(distorted_uv - blur_offset, vec2(0.001), vec2(0.999))).rgb
	) / 3.0;
	color = mix(color, soft_color, edge * intensity * 0.55);

	vec2 double_offset = vec2(sin(time_value * 0.17), cos(time_value * 0.13)) * SCREEN_PIXEL_SIZE * 2.0;
	vec3 echo = texture(screen_texture, clamp(distorted_uv + double_offset, vec2(0.001), vec2(0.999))).rgb;
	color = mix(color, (color + echo) * 0.5, double_vision_strength * intensity * echo_pulse * (0.3 + edge * 0.7));

	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luminance), desaturation_strength * intensity);
	vec3 cold_tint = vec3(0.78, 0.96, 1.04) * (0.97 + 0.03 * sin(time_value * 0.24));
	color *= mix(vec3(1.0), cold_tint, intensity);
	// Preserve the source scene's black levels; this effect must not add a gray floor.

	float vignette = 1.0 - smoothstep(0.28, 1.12, length((uv - vec2(0.5)) * 2.0));
	float vignette_pulse = 1.0 + 0.14 * sin(time_value * 0.29 + 0.8);
	color *= 1.0 - (1.0 - vignette) * vignette_strength * intensity * vignette_pulse;
	float noise_pulse = 0.7 + 0.3 * (0.5 + 0.5 * sin(time_value * 0.67 + 2.8));
	float noise = (screen_noise(floor(uv / SCREEN_PIXEL_SIZE), time_value) - 0.5) * noise_strength * intensity * noise_pulse;
	color += noise * color;
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), original.a);
	}
}
