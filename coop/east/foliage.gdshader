shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D pigment : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float flexibility = 0.06;
uniform float plant_height = 1.0;
uniform float wind_strength = 1.0;
uniform float room_seconds = 0.0;
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float sway = sin(room_seconds*1.25 + dot(base.xz,vec2(.23,.16))) + .33*sin(room_seconds*2.35 + dot(base.xz,vec2(.54,-.23)));
	float tip = smoothstep(.07,1.0,VERTEX.y/plant_height);
	VERTEX.xz += vec2(.82,.27) * sway * tip * flexibility * wind_strength;
}
void fragment() {
	vec4 tint = texture(pigment,UV);
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	ALPHA_SCISSOR_THRESHOLD = .36;
	NORMAL_MAP = texture(relief,UV).rgb;
	NORMAL_MAP_DEPTH = .52;
	ROUGHNESS = .89;
	SPECULAR = .18;
}
