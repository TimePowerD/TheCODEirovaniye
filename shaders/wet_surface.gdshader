shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.3, 0.32, 0.35, 1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_base_texture = false;
uniform sampler2D ripple_noise : repeat_enable, filter_linear;
uniform float dry_roughness = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 float ripple = texture(ripple_noise, world_position.xz * 0.4 + vec2(TIME * 0.06, -TIME * 0.04)).r;
 vec3 dry_color = base_color.rgb;
 if (use_base_texture) { dry_color *= texture(base_texture, UV).rgb; }
 ALBEDO = dry_color * mix(1.0, 0.62, wetness);
 ROUGHNESS = mix(dry_roughness, 0.12 + ripple * 0.1, wetness);
 SPECULAR = mix(0.3, 0.8, wetness);
 NORMAL_MAP = vec3(0.5 + (ripple - 0.5) * wetness * 0.12, 0.5, 1.0);
}
