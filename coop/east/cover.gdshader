shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D pigment : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wind_strength = 1.0;
uniform float room_seconds = 0.0;
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float sway = sin(room_seconds*1.3+dot(base.xz,vec2(.23,.16))) + .22*sin(room_seconds*2.2+base.x*.63);
	VERTEX.xz += vec2(.032,.017)*sway*max(0.0,VERTEX.y)*wind_strength;
}
void fragment() {
	vec4 leaf = texture(pigment,UV);
	ALBEDO = leaf.rgb*vec3(.80,.81,.76);
	ALPHA=leaf.a;
	ALPHA_SCISSOR_THRESHOLD=.36;
	// The photograph already contains stem relief. All three projections receive the same skylight.
	NORMAL=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
	ROUGHNESS=1.0;
}
