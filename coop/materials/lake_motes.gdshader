shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_never;

varying float opacity;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float phase = dot(center.xz, vec2(1.43, 2.91));
	center += vec3(sin(phase + TIME * 0.28) * 0.085, cos(phase + TIME * 0.41) * 0.037, sin(TIME * 0.24 + phase) * 0.055);
	mat4 facing = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2], vec4(center, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	float metres = distance(center, CAMERA_POSITION_WORLD);
	opacity = smoothstep(0.12, 0.42, metres) * (1.0 - smoothstep(2.1, 5.8, metres)) * 0.40;
}

void fragment() {
	ALBEDO = vec3(0.60, 0.60, 0.42);
	NORMAL = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	ALPHA = (1.0 - smoothstep(0.10, 0.50, distance(UV, vec2(0.5)))) * opacity;
}
