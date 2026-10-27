shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 outline_color : source_color = vec4(0.15, 0.10, 0.23, 1.0);
uniform float outline_width : hint_range(0.0, 4.0, 0.1) = 1.1;
uniform float outline_world_width = 0.0018;
uniform bool use_mmd_edge_weights = false;
uniform bool use_face_outline_mask = false;
uniform float mmd_edge_scale_max = 1.0;
uniform float alpha_cutoff = 0.45;
varying float is_shadow_pass;
varying float edge_weight;
varying float face_outline_mask;

void vertex() {
	edge_weight = use_mmd_edge_weights ? COLOR.a * mmd_edge_scale_max : 1.0;
	face_outline_mask = use_face_outline_mask ? COLOR.r : 1.0;
	if (use_face_outline_mask) {
		edge_weight *= COLOR.r;
	}
	VERTEX += NORMAL * outline_world_width * outline_width * edge_weight;
	// A next pass shares the mesh: reject its light-camera pass so the shell cannot thicken cast shadows.
	float camera_difference = length(INV_VIEW_MATRIX[3] - MAIN_CAM_INV_VIEW_MATRIX[3]);
	camera_difference += length(INV_VIEW_MATRIX[2] - MAIN_CAM_INV_VIEW_MATRIX[2]);
	is_shadow_pass = step(0.001, camera_difference);
}

void fragment() {
	if (is_shadow_pass > 0.5 || face_outline_mask < 0.999 || edge_weight < 0.001 || outline_width < 0.001 || outline_color.a < 0.001 || texture(texture_albedo, UV).a < alpha_cutoff) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
