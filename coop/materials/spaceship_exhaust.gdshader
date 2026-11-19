shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform vec3 outer_flame : source_color = vec3(0.12, 0.48, 1.0);
uniform vec3 inner_flame : source_color = vec3(0.74, 0.94, 1.0);
varying float tail;

void vertex() {
	tail = clamp(0.5 - VERTEX.y, 0.0, 1.0);
	float pulse = 1.0 + 0.12 * sin(TIME * 36.0 - tail * 16.0) * tail;
	VERTEX.xz *= pulse;
}

void fragment() {
	float bands = 0.79 + 0.21 * sin(tail * 34.0 - TIME * 44.0);
	float center = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.8);
	vec3 tint = mix(outer_flame, inner_flame, center * (1.0 - tail * 0.5));
	ALBEDO = tint;
	ALPHA = power * pow(max(0.0, 1.0 - tail), 1.15) * mix(0.29, 0.81, center) * bands;
}
