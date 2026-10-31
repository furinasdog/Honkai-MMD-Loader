shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

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
uniform float palette_mix = 0.0;
uniform float hair_shadow_pigment = 0.0;
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
uniform float eye_height = 0.04;
uniform int detail_kind = 0;

varying vec3 head_position;
varying vec2 sphere_uv1;
varying vec3 sphere_multiplier;
varying vec3 source_albedo;
varying float pigment_saturation;

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
	vec3 pigment = clamp(diffuse_sample, vec3(0.0), vec3(1.0));
	pigment = mix(pigment * 12.92, 1.055 * pow(pigment, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), pigment));
	float pigment_max = max(max(pigment.r, pigment.g), pigment.b);
	// Palette membership uses ungraded display chroma; linear contrast exaggerates blue-gray saturation.
	pigment_saturation = (pigment_max - min(min(pigment.r, pigment.g), pigment.b)) / max(pigment_max, 0.001);
	ALBEDO = diffuse_sample + diffuse_sample * (color_gain - vec3(1.0)) * clamp(vec3(1.0) - diffuse_sample, vec3(0.0), vec3(1.0));
	if (enhanced && category == 3 && !has_warm_ramp && !has_cool_ramp) {
		float chroma = max(max(ALBEDO.r, ALBEDO.g), ALBEDO.b) - min(min(ALBEDO.r, ALBEDO.g), ALBEDO.b);
		float luminance = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
		// Preserve a small channel floor when increasing cyan or blue saturation.
		float saturation = clamp((luminance - 0.03) / max(luminance - min(min(ALBEDO.r, ALBEDO.g), ALBEDO.b), 0.0001), 1.0, 1.35);
		ALBEDO = clamp(mix(vec3(luminance), ALBEDO, saturation) * (1.0 - 0.35 * chroma), vec3(0.0), vec3(1.0));
		float dark_neutral = smoothstep(0.015, 0.08, luminance) * (1.0 - smoothstep(0.20, 0.40, luminance)) * (1.0 - smoothstep(0.12, 0.28, pigment_saturation));
		ALBEDO *= 1.0 - 0.45 * dark_neutral;
		float white_fabric = smoothstep(0.62, 0.80, min(min(ALBEDO.r, ALBEDO.g), ALBEDO.b)) * (1.0 - smoothstep(0.12, 0.20, chroma));
		ALBEDO += (vec3(1.0) - ALBEDO) * white_fabric * vec3(0.66, 0.58, 0.45);
	}
	if (enhanced && category == 2 && palette_mix > 0.0 && !has_warm_ramp && !has_cool_ramp) {
		ALBEDO = mix(ALBEDO, clamp((ALBEDO - vec3(0.75)) * 1.45 + vec3(0.85, 0.81, 0.78), vec3(0.0), vec3(1.0)), palette_mix);
	}
	if (enhanced && category == 2 && !has_light_map && !has_warm_ramp && !has_cool_ramp) {
		float pale_hair = smoothstep(0.40, 0.65, dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722)));
		float pink_pigment = smoothstep(0.018, 0.05, ALBEDO.r - ALBEDO.g);
		float head_scale = max(face_top - face_bottom, 0.01) / 0.18;
		float lower_hair = 1.0 - smoothstep(-0.10, 0.13, head_position.y / head_scale);
		ALBEDO *= mix(vec3(1.0), vec3(0.84, 0.50, 0.61), lower_hair * pale_hair * pink_pigment);
	}
	if (enhanced && category == 0 && !has_warm_ramp && !has_cool_ramp) {
		ALBEDO = min(ALBEDO * vec3(1.04, 1.10, 1.04), vec3(1.0));
	}
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
	if (shadows_enabled && enhanced && category == 2) {
		float head_scale = max(face_top - face_bottom, 0.01) / 0.18;
		vec3 local_head = head_position / head_scale;
		vec3 crown = normalize(vec3(local_head.x * 0.65, local_head.y * 0.7 + 0.025, (local_head.z + 0.01) * 0.65));
		vec3 crown_view = normalize((VIEW_MATRIX * head_to_world * vec4(crown, 0.0)).xyz);
		float crown_weight = smoothstep(0.04, 0.12, local_head.y) * 0.95;
		NORMAL = normalize(mix(NORMAL, crown_view, crown_weight));
	}
	if (shadows_enabled && enhanced && detail_kind == 1) {
		ALBEDO = mix(ALBEDO, vec3(0.24, 0.067, 0.05), 0.45);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (!shadows_enabled || category == 5) {
		EMISSION = ALBEDO;
	} else {
		float floor_usage = has_mmd_toon || (enhanced && (has_warm_ramp || has_cool_ramp)) ? 0.0 : ambient_floor;
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
			// Body and cloth keep a broad two-tone ramp without hard self-cast shadow patches.
			float style_threshold = shadow_threshold + (category == 2 ? 0.33 : 0.0);
			threshold = clamp(has_light_map ? 1.0 - light_data.g + (style_threshold - 0.3) * 0.5 : style_threshold * 0.5 + 0.35, 0.01, 0.99);
			if (category == 3 && !has_light_map && !has_warm_ramp && !has_cool_ramp) {
				threshold -= 0.18 * smoothstep(0.45, 0.65, min(min(source_albedo.r, source_albedo.g), source_albedo.b));
				threshold += 0.06 * smoothstep(0.18, 0.40, pigment_saturation);
			}
			irradiance = n_dot_l * 0.5 + 0.5;
			if (category == 1 || category == 2) {
				// Skin and hair quantize the combined lighting once, including cast-shadow visibility.
				float cast_receive = shadow_receive;
				if (category == 1 && !has_light_map && !has_warm_ramp && !has_cool_ramp) {
					// shortcut: head proportions bound neck contact until an authored skin LightMap or Ramp is supplied.
					float height = max(face_top - face_bottom, 0.01);
					float neck = (1.0 - smoothstep(face_half_width, face_half_width * 1.6, abs(head_position.x)))
						* smoothstep(face_bottom - height, face_bottom - height * 0.8, head_position.y)
						* (1.0 - smoothstep(face_bottom + height * 0.3, face_bottom + height * 0.5, head_position.y));
					float contact = smoothstep(face_bottom - height * 0.30, face_bottom - height * 0.06, head_position.y)
						* smoothstep(-face_half_width * 0.25, face_half_width * 0.12, head_position.z);
					cast_receive *= mix(1.0, contact, neck);
				}
				irradiance *= mix(1.0, ATTENUATION, cast_receive);
			}
		}
		float band = toon_step(threshold, irradiance);
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
			band = toon_step(0.0, face_score);
			if (enhanced && (has_generated_map || has_face_map || has_face_sdf)) {
				vec2 thresholds = has_generated_map ? texture(generated_map, UV).rg : vec2(0.5);
				float sdf_value = local_light.x * head_position.x >= 0.0 ? thresholds.r : thresholds.g;
				vec2 sdf_uv = vec2(local_light.x >= 0.0 ? UV.x : 1.0 - UV.x, UV.y);
				if (has_face_map) { sdf_value = texture(face_map, sdf_uv).a; }
				if (has_face_sdf) { sdf_value = texture(face_sdf, sdf_uv).r; }
				band = toon_step(0.5 - horizontal.y * 0.5, sdf_value - 0.001);
				if (has_face_map) {
					vec4 face_data = texture(face_map, UV);
					band = mix(face_data.g, band, 1.0 - step(0.5, face_data.r));
				}
			}
			float forehead = smoothstep(eye_height - face_height * 0.08, eye_height + face_height * 0.03, head_position.y);
			cast_light = mix(1.0, cast_light, forehead);
			illumination = min(band, mix(1.0, cast_light, shadow_receive));
		}
		if (enhanced && category != 0 && has_light_map) {
			illumination *= light_data.r;
		}
		bool cloth_palette = enhanced && category == 3 && !has_light_map && !has_warm_ramp && !has_cool_ramp;
		float blue_pigment = cloth_palette ? smoothstep(0.10, 0.20, source_albedo.b - source_albedo.g) * smoothstep(0.05, 0.12, source_albedo.g - source_albedo.r) : 0.0;
		float pink_pigment = cloth_palette ? smoothstep(0.15, 0.30, min(source_albedo.r, source_albedo.b) - source_albedo.g) : 0.0;
		float colored_pigment = smoothstep(0.18, 0.40, pigment_saturation);
		vec3 fallback_shadow = shadow_color.rgb;
		if (enhanced && (category == 2 || category == 3) && !has_warm_ramp && !has_cool_ramp) {
			// Neutral pigments must not inherit the magenta shadow of saturated cloth or pink hair.
			vec3 neutral_shadow = category == 2 ? vec3(0.60, 0.62, 0.65) : vec3(0.54, 0.51, 0.70);
			float shadow_pigment = category == 2 ? max(hair_shadow_pigment, smoothstep(0.01, 0.06, min(source_albedo.r, source_albedo.b) - source_albedo.g)) : colored_pigment;
			fallback_shadow = mix(neutral_shadow, fallback_shadow, shadow_pigment);
		}
		vec3 tint = mix(fallback_shadow, vec3(1.0), illumination);
		if (has_mmd_toon) {
			vec3 authored = texture(mmd_toon, vec2(0.5, 1.0 - illumination)).rgb;
			vec3 neutral_authored = authored * min(1.0, dot(tint, vec3(0.2126, 0.7152, 0.0722)) / max(dot(authored, vec3(0.2126, 0.7152, 0.0722)), 0.0001));
			vec3 styled = category == 3 ? mix(neutral_authored, min(authored, tint), colored_pigment) : tint;
			tint = mix(authored, styled, enhanced ? palette_mix : 0.0);
		}
		if (enhanced && (has_warm_ramp || has_cool_ramp)) {
			float row = category == 0 || category == 2 ? 0.5 : (floor(clamp(light_data.a, 0.0, 0.999) * 8.0) + 0.5) / 8.0;
			vec2 ramp_uv = vec2(mix(0.05, 0.95, illumination), row);
			vec3 warm = has_warm_ramp ? texture(warm_ramp, ramp_uv).rgb : tint;
			vec3 cool = has_cool_ramp ? texture(cool_ramp, ramp_uv).rgb : warm;
			if (!has_warm_ramp) { warm = cool; }
			float daylight = clamp((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y * 0.5 + 0.5, 0.0, 1.0);
			tint = mix(cool, warm, daylight);
		}
		if (enhanced && category == 3 && !has_light_map && !has_warm_ramp && !has_cool_ramp) {
			float white_cloth = smoothstep(0.55, 0.75, min(min(ALBEDO.r, ALBEDO.g), ALBEDO.b));
			white_cloth *= smoothstep(0.05, 0.25, min(min(tint.r, tint.g), tint.b));
			tint = mix(tint, vec3(0.54, 0.51, 0.70), white_cloth * (1.0 - illumination) * 0.65);
		}
		if (cloth_palette) {
			// shortcut: source hue and brightness approximate painted folds until authored cloth masks exist.
			float blue_fold = blue_pigment * smoothstep(0.12, 0.22, source_albedo.g) * (1.0 - smoothstep(0.26, 0.36, source_albedo.g)) * illumination;
			tint *= mix(vec3(1.0), vec3(0.60, 0.30, 0.72), blue_fold);
			float blue_bright = blue_pigment * smoothstep(0.30, 0.40, source_albedo.g) * illumination;
			tint *= mix(vec3(1.0), vec3(0.98, 0.85, 0.93), blue_bright);
			float pink_bright = pink_pigment * smoothstep(0.21, 0.26, source_albedo.g) * illumination;
			tint *= mix(vec3(1.0), vec3(0.95, 1.13, 0.94), pink_bright);
		}
		if (enhanced && category != 0) {
			tint *= mix(0.65, 1.0, light_data.r);
		}
		if (LIGHT_IS_DIRECTIONAL) {
			float floor_usage = has_mmd_toon || (enhanced && (has_warm_ramp || has_cool_ramp)) ? 0.0 : ambient_floor;
			DIFFUSE_LIGHT += max(tint - shadow_color.rgb * floor_usage, vec3(0.0)) * LIGHT_COLOR / PI;
		} else {
			vec3 local_tint = has_mmd_toon || (enhanced && (has_warm_ramp || has_cool_ramp)) ? tint : (vec3(1.0) - shadow_color.rgb * ambient_floor) * band;
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
