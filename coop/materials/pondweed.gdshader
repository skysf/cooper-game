shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

void vertex() {
	float sway = sin(TIME * 0.86 + MODEL_MATRIX[3].x * 0.81 + MODEL_MATRIX[3].z * 1.24);
	VERTEX.x += sway * VERTEX.y * VERTEX.y * 0.085;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.88;
	BACKLIGHT = COLOR.rgb * 0.16;
}
