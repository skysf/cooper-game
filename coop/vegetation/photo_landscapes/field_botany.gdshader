shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://vegetation/wind_field.gdshaderinc"

uniform sampler2D botanical_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float flexibility = 0.23;
uniform float wetness = 0.0;

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	vec2 flow = woodland_flow(root);
	float height = max(VERTEX.y, 0.0);
	float phase = dot(root, vec2(0.47, 0.26)) + dot(VERTEX.xz, vec2(1.8, 2.1));
	float tip = smoothstep(0.55, 1.85, height);
	float wave = 0.69 + 0.26 * sin(wind_time * 1.83 + phase - height * 0.78);
	vec2 bend = flow * wave + vec2(-flow.y, flow.x) * (0.16 * tip * sin(wind_time * 2.24 + phase));
	VERTEX.xz += woodland_local_xz(bend * height * height * flexibility, MODEL_MATRIX);
	VERTEX.y -= height * tip * min(dot(bend,bend),2.6) * flexibility * 0.18;
}

void fragment() {
	vec4 sample_color = texture(botanical_atlas, UV);
	ALBEDO = sample_color.rgb * COLOR.rgb * (1.0-wetness*0.14);
	if (UV.x < .5 && UV.y < .5) { ALBEDO *= vec3(.72,.70,.69); }
	ALPHA = sample_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
	ROUGHNESS = 0.94 - wetness*0.21;
	BACKLIGHT = ALBEDO * 0.15;
}
