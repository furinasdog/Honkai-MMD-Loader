shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color = vec4(1.0);
// FACE, SKIN, HAIR, CLOTH, METAL, EYE.
uniform int category : hint_range(0, 5) = 3;
uniform vec4 shadow_color : source_color = vec4(0.69, 0.65, 0.82, 1.0);
uniform float shadow_threshold : hint_range(-0.5, 0.7, 0.01) = 0.12;
uniform float shadow_softness : hint_range(0.005, 0.15, 0.005) = 0.025;
uniform float shadow_receive : hint_range(0.0, 1.0) = 1.0;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.28;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.45;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 specular_color : source_color = vec4(1.0, 0.91, 0.97, 1.0);
uniform float rim_strength : hint_range(0.0, 0.2) = 0.025;
uniform vec3 color_gain = vec3(1.0);
uniform mat4 world_to_head;
uniform mat4 head_to_world;
uniform float face_half_width = 0.0817;
uniform float nose_height = 0.02770555;
uniform float face_bottom = -0.06;
uniform float face_top = 0.12;
uniform int detail_kind = 0;

varying vec3 head_position;
varying float is_shadow_pass;

void vertex() {
	head_position = (world_to_head * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float camera_difference = length(INV_VIEW_MATRIX[3] - MAIN_CAM_INV_VIEW_MATRIX[3]);
	camera_difference += length(INV_VIEW_MATRIX[2] - MAIN_CAM_INV_VIEW_MATRIX[2]);
	is_shadow_pass = step(0.001, camera_difference);
}

void fragment() {
	if (category == 5 && is_shadow_pass > 0.5) {
		discard;
	}
	vec4 sampled = texture(texture_albedo, UV);
	ALBEDO = sampled.rgb * base_color.rgb * color_gain;
	ALPHA = sampled.a * base_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (category == 2) {
		vec3 crown = normalize(vec3(head_position.x, head_position.y * 0.7 - 0.056, head_position.z + 0.01));
		vec3 crown_view = normalize((VIEW_MATRIX * head_to_world * vec4(crown, 0.0)).xyz);
		float crown_weight = smoothstep(0.07, 0.14, head_position.y) * 0.65;
		NORMAL = normalize(mix(NORMAL, crown_view, crown_weight));
	}
	if (detail_kind == 1) {
		ALBEDO = mix(ALBEDO, vec3(0.24, 0.067, 0.05), 0.45);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = ALBEDO * shadow_color.rgb * ambient_floor;
	if (category == 5) {
		EMISSION = ALBEDO;
	}
}

void light() {
	if (category != 5) {
		float n_dot_l = dot(NORMAL, LIGHT);
		float band = smoothstep(shadow_threshold - shadow_softness, shadow_threshold + shadow_softness, n_dot_l);
		float cast_light = smoothstep(0.25, 0.75, ATTENUATION);
		if (category == 0) {
			vec3 local_light = (world_to_head * INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
			vec2 horizontal = normalize(local_light.xz + vec2(0.0, 0.00001));
			float face_height = max(face_top - face_bottom, 0.01);
			float nose = 1.0 - smoothstep(0.0, face_height * 0.14, abs(head_position.y - nose_height));
			// shortcut: models without an authored face SDF use a head-local cheek field.
			float face_score = horizontal.y + horizontal.x * head_position.x / face_half_width + abs(horizontal.x) * 0.18 * nose;
			band = smoothstep(-0.035, 0.035, face_score);
			vec3 head_normal = normalize((world_to_head * INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			float under_chin = 1.0 - smoothstep(-0.65, -0.25, head_normal.y);
			float surface_band = smoothstep(shadow_threshold - 0.10, shadow_threshold + 0.10, n_dot_l);
			band = mix(band, min(band, surface_band), under_chin);
			float forehead = smoothstep(mix(face_bottom, face_top, 0.65), mix(face_bottom, face_top, 0.9), head_position.y);
			cast_light = mix(1.0, cast_light, forehead);
		}
		float illumination = min(band, mix(1.0, cast_light, shadow_receive));
		vec3 tint = mix(shadow_color.rgb, vec3(1.0), illumination);
		if (LIGHT_IS_DIRECTIONAL) {
			DIFFUSE_LIGHT += max(tint - shadow_color.rgb * ambient_floor, vec3(0.0)) * LIGHT_COLOR / PI;
		} else {
			DIFFUSE_LIGHT += (vec3(1.0) - shadow_color.rgb * ambient_floor) * band * ATTENUATION * LIGHT_COLOR / PI;
		}
		vec3 halfway = normalize(LIGHT + VIEW);
		float highlight = 0.0;
		if (category == 2) {
			vec3 head_up = normalize((VIEW_MATRIX * head_to_world * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			vec3 strand = head_up - NORMAL * dot(head_up, NORMAL);
			strand = normalize(strand + NORMAL * 0.16);
			float strand_dot = dot(strand, halfway);
			float anisotropic = sqrt(max(0.0, 1.0 - strand_dot * strand_dot));
			highlight = smoothstep(0.987, 0.997, anisotropic) * smoothstep(0.15, 0.6, dot(NORMAL, halfway));
			highlight *= smoothstep(0.035, 0.09, head_position.y);
		} else if (category == 4) {
			highlight = smoothstep(0.945, 0.965, max(dot(NORMAL, halfway), 0.0));
		}
		float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 5.0);
		rim *= smoothstep(-0.1, 0.4, n_dot_l) * rim_strength;
		SPECULAR_LIGHT += (specular_color.rgb * highlight * specular_strength + ALBEDO * rim) * illumination * ATTENUATION * LIGHT_COLOR / PI;
	}
}
