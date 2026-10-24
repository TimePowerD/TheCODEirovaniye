shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// Shared parameter name lets both transitions use the same timing controller.
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float blur_radius : hint_range(0.0, 24.0) = 14.0;
uniform vec4 light_tint : source_color = vec4(1.0, 0.95, 0.83, 1.0);

void fragment() {
	float progress = smoothstep(0.0, 1.0, darkness);
	vec2 offset = SCREEN_PIXEL_SIZE * blur_radius * blur_amount;
	float lod = blur_amount * 2.5;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, lod).rgb * 0.2;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(offset.x, 0.0), lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(offset.x, 0.0), lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(0.0, offset.y), lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(0.0, offset.y), lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV + offset, lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV - offset, lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(offset.x, -offset.y), lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(-offset.x, offset.y), lod).rgb * 0.08;
	vec2 centered = SCREEN_UV - vec2(0.5, 0.38);
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float angle = atan(centered.y, centered.x);
	float rays = pow(0.5 + 0.5 * sin(angle * 11.0 + length(centered) * 3.0), 3.0);
	float halo = exp(-length(centered) * 2.0);
	// Rays fade out at full white; the scene is completely hidden at transfer.
	float envelope = sin(progress * 3.14159265);
	float light_amount = clamp(progress + (rays * 0.12 + halo * 0.18) * envelope, 0.0, 1.0);
	vec3 radiant_white = mix(vec3(1.0), light_tint.rgb, envelope * 0.6);
	COLOR = vec4(mix(blurred, radiant_white, light_amount), 1.0);
}
