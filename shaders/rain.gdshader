shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
 float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
 float tip = sin(UV.y * 3.14159265);
 ALBEDO = vec3(0.68, 0.8, 0.95);
 ALPHA = edge * tip * intensity * 0.48;
}
