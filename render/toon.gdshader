shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
// FACE, SKIN, HAIR, CLOTH, METAL, EYE.
uniform int category : hint_range(0, 5) = 3;
uniform bool shadows_enabled = true;
uniform bool enhanced = true;
uniform bool has_generated_map = false;
uniform sampler2D generated_map : filter_linear_mipmap, repeat_disable;
uniform bool has_face_map = false;
uniform bool has_face_sdf = false;
uniform bool has_light_map = false;
uniform bool has_warm_ramp = false;
uniform bool has_cool_ramp = false;
uniform bool has_highlight_map = false;
uniform bool has_mmd_toon = false;
uniform bool has_mmd_sphere = false;
uniform bool has_sphere_uv1 = false;
uniform bool casts_shadows = true;
uniform int sphere_mode = 0;
uniform sampler2D mmd_toon : source_color, filter_nearest, repeat_disable;
uniform sampler2D mmd_sphere : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 authored_specular : source_color = vec4(0.0);
uniform float authored_shininess = 32.0;
uniform sampler2D face_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D face_sdf : filter_linear_mipmap, repeat_enable;
uniform sampler2D light_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D warm_ramp : source_color, filter_nearest, repeat_disable;
uniform sampler2D cool_ramp : source_color, filter_nearest, repeat_disable;
uniform sampler2D highlight_map : filter_linear_mipmap, repeat_enable;
uniform vec4 shadow_color : source_color = vec4(0.761112, 0.741905, 0.854306, 1.0);
uniform float shadow_threshold : hint_range(-0.5, 0.7, 0.01) = 0.30;
uniform float shadow_softness = 0.025;
uniform float face_shadow_softness = 0.015;
uniform float shadow_receive : hint_range(0.0, 1.0) = 1.0;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.28;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.45;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 specular_color : source_color = vec4(1.0, 0.91, 0.97, 1.0);
uniform float rim_strength : hint_range(0.0, 0.2) = 0.025;
uniform mat4 world_to_head;
uniform mat4 head_to_world;
uniform float face_half_width = 0.0817;
uniform float nose_height = 0.02770555;
uniform float face_bottom = -0.06;
uniform float face_top = 0.12;
uniform float eye_height = 0.04;
uniform int detail_kind = 0;

varying vec3 head_position;
varying vec2 sphere_uv1;
varying vec3 sphere_multiplier;
varying vec3 source_albedo;

float toon_step(float threshold, float value) {
	// Keep two flat tones; soften only the one-pixel raster boundary.
	float width = max(fwidth(value), 0.0001);
	return smoothstep(threshold - width * 0.5, threshold + width * 0.5, value);
}

void vertex() {
	head_position = (world_to_head * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sphere_uv1 = CUSTOM0.xy;
}

void fragment() {
	// Solid eyes and oral surfaces close facial openings in the head's shadow silhouette.
	if ((!casts_shadows || (enhanced && category == 5 && detail_kind > 0)) && IN_SHADOW_PASS) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 sampled = texture(texture_albedo, UV);
	vec3 diffuse_sample = sampled.rgb * base_color.rgb;
	ALBEDO = diffuse_sample;
	source_albedo = ALBEDO;
	sphere_multiplier = vec3(1.0);
	vec3 sphere_addition = vec3(0.0);
	if (has_mmd_sphere) {
		vec2 sphere_uv = sphere_mode == 3 ? sphere_uv1 : NORMAL.xy * vec2(0.5, -0.5) + vec2(0.5);
		vec3 sphere_color = texture(mmd_sphere, sphere_uv).rgb;
		if (sphere_mode == 1 || (sphere_mode == 3 && has_sphere_uv1)) {
			sphere_multiplier = sphere_color;
			ALBEDO *= sphere_color;
		} else if (sphere_mode == 2) {
			sphere_addition = sphere_color;
		}
	}
	ALPHA = sampled.a * base_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	if (enhanced && category == 0 && (has_face_map || has_generated_map)) {
		vec3 head_view = normalize((VIEW_MATRIX * head_to_world * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
		float nose_mask = has_face_map ? texture(face_map, UV).b : texture(generated_map, UV).b;
		if (!has_face_map) { nose_mask = toon_step(0.25, nose_mask) * 0.7 * step(0.0, head_position.x); }
		float nose_ink = nose_mask * pow(max(dot(head_view, VIEW), 0.0), 20.0);
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.65, 0.39, 0.33), nose_ink);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Godot supplies environment irradiance; authored AO affects that term only.
	AO = 0.0;
	AO_LIGHT_AFFECT = 0.0;
	if (enhanced && shadows_enabled && category != 5) {
		float occlusion = 1.0;
		if (category == 0 && has_face_map) {
			vec4 data = texture(face_map, UV);
			occlusion = data.r <= 0.5 ? 1.0 : data.g;
		} else if (has_light_map) {
			occlusion = texture(light_map, UV).r;
		}
		AO = mix(0.5, 1.0, occlusion);
	}
	if (!shadows_enabled || category == 5) {
		EMISSION = ALBEDO;
	} else if (!enhanced) {
		float floor_usage = enhanced || has_mmd_toon ? 0.0 : ambient_floor;
		EMISSION = ALBEDO * shadow_color.rgb * floor_usage;
	}
	// Additive sphere reflection is applied after the Toon palette, not tinted by it.
	EMISSION += sphere_addition;
}

void light() {
	if (shadows_enabled && category != 5) {
		float n_dot_l = dot(NORMAL, LIGHT);
		float irradiance = max(n_dot_l, 0.0) * mix(1.0, ATTENUATION, shadow_receive);
		float threshold = shadow_threshold;
		vec4 light_data = vec4(1.0, 0.5, 0.5, 0.0);
		if (enhanced && has_light_map) {
			light_data = texture(light_map, UV);
		}
		if (enhanced && category != 0) {
			threshold = 1.0 - light_data.g + (shadow_threshold - 0.3) * 0.5;
			irradiance = n_dot_l * 0.5 + 0.5;
		}
		float width = enhanced ? max(shadow_softness, fwidth(irradiance) * 0.5) : max(fwidth(irradiance) * 0.5, 0.0001);
		float band = smoothstep(threshold - width, threshold + width, irradiance);
		// Directional visibility changes the band, without moving its normal threshold.
		if (enhanced && category != 0 && LIGHT_IS_DIRECTIONAL) {
			band = min(band, mix(1.0, smoothstep(0.45, 0.55, ATTENUATION), shadow_receive));
		}
		float cast_light = toon_step(0.5, ATTENUATION);
		float illumination = band;
		if (category == 0) {
			vec3 local_light = (world_to_head * INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
			vec2 horizontal = normalize(local_light.xz + vec2(0.0, 0.00001));
			float face_height = max(face_top - face_bottom, 0.01);
			float nose = 1.0 - smoothstep(0.0, face_height * 0.14, abs(head_position.y - nose_height));
			// shortcut: models without an authored face SDF use a head-local cheek field.
			float face_score = horizontal.y + horizontal.x * head_position.x / face_half_width + abs(horizontal.x) * 0.18 * nose;
			// Lip, nose and chin normals must not introduce curved 3D shading into the face field.
			band = smoothstep(-max(face_shadow_softness, fwidth(face_score) * 0.5), max(face_shadow_softness, fwidth(face_score) * 0.5), face_score);
			if (enhanced && (has_generated_map || has_face_map || has_face_sdf)) {
				vec2 thresholds = has_generated_map ? texture(generated_map, UV).rg : vec2(0.5);
				float sdf_value = local_light.x * head_position.x >= 0.0 ? thresholds.r : thresholds.g;
				vec2 sdf_uv = vec2(local_light.x >= 0.0 ? UV.x : 1.0 - UV.x, UV.y);
				if (has_face_map) { sdf_value = texture(face_map, sdf_uv).a; }
				if (has_face_sdf) { sdf_value = texture(face_sdf, sdf_uv).r; }
				float sdf_threshold = 0.5 - horizontal.y * 0.5;
				// Keep black/white SDF endpoints decisive at exactly frontal/rear light.
				float sdf_width = min(max(face_shadow_softness, fwidth(sdf_value) * 0.5), max(0.0001, min(sdf_threshold, 1.0 - sdf_threshold)));
				band = smoothstep(sdf_threshold - sdf_width, sdf_threshold + sdf_width, sdf_value - 0.001);
				if (has_face_map) {
					vec4 face_data = texture(face_map, UV);
					band = face_data.r <= 0.5 ? band : face_data.g;
				}
			}
			float forehead = smoothstep(eye_height - face_height * 0.08, eye_height + face_height * 0.03, head_position.y);
			cast_light = mix(1.0, cast_light, forehead);
			illumination = min(band, mix(1.0, cast_light, shadow_receive));
		}
		if (enhanced && category != 0 && has_light_map) {
			illumination *= light_data.r;
		}
		vec3 tint = mix(shadow_color.rgb, vec3(1.0), illumination);
		if (has_mmd_toon) {
			tint = texture(mmd_toon, vec2(0.5, 1.0 - illumination)).rgb;
		}
		if (enhanced && (has_warm_ramp || has_cool_ramp)) {
			float row = category == 0 || category == 2 ? 0.5 : (floor(clamp(light_data.a, 0.0, 0.999) * 8.0) + 0.5) / 8.0;
			vec2 ramp_uv = vec2(mix(0.75, 1.0, illumination), row);
			vec3 warm = has_warm_ramp ? texture(warm_ramp, ramp_uv).rgb : tint;
			vec3 cool = has_cool_ramp ? texture(cool_ramp, ramp_uv).rgb : warm;
			if (!has_warm_ramp) { warm = cool; }
			float daylight = clamp((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y * 0.5 + 0.5, 0.0, 1.0);
			tint = mix(cool, warm, daylight);
		}
		if (LIGHT_IS_DIRECTIONAL) {
			float floor_usage = enhanced || has_mmd_toon ? 0.0 : ambient_floor;
			DIFFUSE_LIGHT += max(tint - shadow_color.rgb * floor_usage, vec3(0.0)) * LIGHT_COLOR / PI;
		} else {
			vec3 local_tint = enhanced || has_mmd_toon ? tint : (vec3(1.0) - shadow_color.rgb * ambient_floor) * band;
			DIFFUSE_LIGHT += local_tint * ATTENUATION * LIGHT_COLOR / PI;
		}
		vec3 halfway = normalize(LIGHT + VIEW);
		float highlight = 0.0;
		float mapped_specular = 0.0;
		float mapped_metallic = 0.0;
		if (enhanced && category == 2) {
			vec3 head_up = normalize((VIEW_MATRIX * head_to_world * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			vec3 strand = head_up - NORMAL * dot(head_up, NORMAL);
			strand = normalize(strand + NORMAL * 0.16);
			float strand_dot = dot(strand, halfway);
			float anisotropic = sqrt(max(0.0, 1.0 - strand_dot * strand_dot));
			highlight = smoothstep(0.987, 0.997, anisotropic) * smoothstep(0.15, 0.6, dot(NORMAL, halfway));
			highlight *= smoothstep(0.035, 0.09, head_position.y / (max(face_top - face_bottom, 0.01) / 0.18));
			if (enhanced && has_generated_map && !has_highlight_map && !has_light_map) {
				highlight *= texture(generated_map, UV).b;
			}
		} else if (enhanced && category == 4) {
			highlight = smoothstep(0.945, 0.965, max(dot(NORMAL, halfway), 0.0));
		}
		if (enhanced && has_light_map) {
			float broad_specular = pow(max(dot(NORMAL, halfway), 0.0), 32.0);
			highlight *= toon_step(1.0 - light_data.b, broad_specular);
			if (category != 0 && category != 2) {
				mapped_metallic = 1.0 - smoothstep(0.04, 0.12, abs(light_data.a - 0.52));
				mapped_specular = mix(toon_step(1.04 - light_data.b, broad_specular) * 0.04, broad_specular * light_data.b * 0.45, mapped_metallic);
			}
		}
		if (enhanced && has_highlight_map) {
			highlight *= texture(highlight_map, UV).r;
		}
		float rim = !enhanced || category == 0 ? 0.0 : pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 5.0);
		rim *= smoothstep(-0.1, 0.4, n_dot_l) * rim_strength;
		float authored_gloss = pow(max(dot(NORMAL, halfway), 0.0), authored_shininess);
		authored_gloss = enhanced ? toon_step(0.5, authored_gloss) : authored_gloss;
		SPECULAR_LIGHT += (specular_color.rgb * highlight * specular_strength + authored_specular.rgb * authored_gloss + mix(vec3(1.0), source_albedo, mapped_metallic) * mapped_specular + source_albedo * rim) * sphere_multiplier * illumination * ATTENUATION * LIGHT_COLOR / PI;
	}
}
