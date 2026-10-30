shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 outline_color : source_color = vec4(0.15, 0.10, 0.23, 1.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool use_texture_color = false;
uniform float outline_width : hint_range(0.0, 6.0, 0.1) = 1.1;
uniform float outline_world_width = 0.0018; // Retained for older scenes; extrusion now uses screen pixels.
uniform float material_edge_scale = 1.0;
uniform bool use_mmd_edge_weights = false;
uniform bool use_face_outline_mask = false;
uniform float mmd_edge_scale_max = 1.0;
uniform float alpha_cutoff = 0.45;
varying float edge_weight;
varying float face_outline_mask;

void vertex() {
	edge_weight = use_mmd_edge_weights ? COLOR.a * mmd_edge_scale_max : 1.0;
	face_outline_mask = use_face_outline_mask ? COLOR.r : 1.0;
	if (use_face_outline_mask) {
		edge_weight *= COLOR.r;
	}
	vec4 clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip_normal = PROJECTION_MATRIX * vec4(MODELVIEW_NORMAL_MATRIX * NORMAL, 0.0);
	vec2 projected_normal = (clip_normal.xy * clip_position.w - clip_position.xy * clip_normal.w) * VIEWPORT_SIZE;
	vec2 pixel_direction = projected_normal / max(length(projected_normal), 0.00001);
	clip_position.xy += pixel_direction * (2.0 / VIEWPORT_SIZE) * clip_position.w * outline_width * material_edge_scale * edge_weight;
	POSITION = clip_position;
}

void fragment() {
	if (IN_SHADOW_PASS || face_outline_mask < 0.999 || edge_weight < 0.001 || material_edge_scale < 0.001 || outline_width < 0.001 || outline_color.a < 0.001 || texture(texture_albedo, UV).a < alpha_cutoff) {
		discard;
	}
	vec3 source = texture(texture_albedo, UV).rgb * base_color.rgb;
	vec3 ink_hue = outline_color.rgb / max(max(max(outline_color.r, outline_color.g), outline_color.b), 0.0001);
	ALBEDO = use_texture_color ? source * mix(vec3(1.0), ink_hue, 0.65) * 0.30 : outline_color.rgb;
	// OUTLINE_ALPHA_VARIANT
}
