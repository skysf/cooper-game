shader_type spatial;
render_mode cull_disabled;

#include "res://vegetation/wind_field.gdshaderinc"

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 leaf_tint : source_color = vec4(1.0);

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	float flex = clamp(1.0 - UV.y, 0.0, 1.0);
	float near_weight = 1.0 - smoothstep(27.0, 40.0, distance(root, CAMERA_POSITION_WORLD.xz));
	vec2 drift = woodland_flow(root) * flex * flex * near_weight * 0.092;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(drift.x, 0.0, drift.y);
}

void fragment() {
	vec4 color = texture(leaf_texture, UV);
	ALBEDO = color.rgb * leaf_tint.rgb;
	ROUGHNESS = 1.0;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
}
