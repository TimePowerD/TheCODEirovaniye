shader_type sky;
uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform vec4 top_color : source_color = vec4(0.22, 0.52, 0.88, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.76, 0.88, 0.98, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.98, 0.98, 0.95, 1.0);
uniform vec3 sun_direction = vec3(0.3, 0.6, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.79, 1.0);
uniform float cloud_cover = 0.18;
uniform float lightning = 0.0;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
void sky() {
 float height = max(EYEDIR.y, 0.0);
 vec3 base = mix(horizon_color.rgb, top_color.rgb, pow(height, 0.55));
 vec2 cloud_uv = EYEDIR.xz / (height + 0.25) * 0.12 + vec2(TIME * 0.0015, 0.0);
 float noise = texture(cloud_noise, cloud_uv).r;
 float cloud = smoothstep(1.0 - cloud_cover, 1.08 - cloud_cover, noise);
 cloud *= smoothstep(0.0, 0.12, height);
 float sun = smoothstep(0.9985, 0.9995, dot(normalize(EYEDIR), normalize(sun_direction)));
 float glow = pow(max(dot(normalize(EYEDIR), normalize(sun_direction)), 0.0), 24.0) * 0.22;
 COLOR = mix(base + sun_color.rgb * (sun + glow) * (1.0 - cloud_cover), cloud_color.rgb, cloud);
 vec2 star_cell = floor(EYEDIR.xz / (height + 0.15) * 240.0);
 float star = fract(sin(dot(star_cell, vec2(127.1, 311.7))) * 43758.5453);
 COLOR += vec3(0.75, 0.83, 1.0) * step(0.9985, star) * night_amount * (1.0 - cloud_cover) * smoothstep(0.1, 0.4, height);
 COLOR += vec3(0.66, 0.75, 1.0) * lightning;
}
