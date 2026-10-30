shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode write, 1;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float base_alpha = 1.0;

void fragment() {
	if (IN_SHADOW_PASS || texture(texture_albedo, UV).a * base_alpha < 0.45) { discard; }
	ALBEDO = vec3(0.0);
	ALPHA = 0.000001;
}
