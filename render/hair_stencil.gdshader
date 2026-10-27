shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode write, 1;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float base_alpha = 1.0;
varying float is_shadow_pass;

void vertex() {
	float difference = length(INV_VIEW_MATRIX[3] - MAIN_CAM_INV_VIEW_MATRIX[3]);
	difference += length(INV_VIEW_MATRIX[2] - MAIN_CAM_INV_VIEW_MATRIX[2]);
	is_shadow_pass = step(0.001, difference);
}

void fragment() {
	if (is_shadow_pass > 0.5 || texture(texture_albedo, UV).a * base_alpha < 0.45) { discard; }
	ALBEDO = vec3(0.0);
	ALPHA = 0.000001;
}
