shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode read, compare_equal, 1;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform mat4 head_to_world;
uniform float strength = 0.3;

void fragment() {
	vec3 head_forward = normalize(head_to_world[2].xyz);
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - head_to_world[3].xyz);
	float frontal = smoothstep(0.45, 0.8, dot(head_forward, to_camera));
	vec4 source = texture(texture_albedo, UV) * base_color;
	if (frontal < 0.001 || source.a < 0.45 || strength < 0.001) { discard; }
	ALBEDO = source.rgb;
	ALPHA = source.a * strength * frontal;
}
