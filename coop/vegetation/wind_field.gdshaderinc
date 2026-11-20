uniform float wind_time = 0.0;
uniform vec4 wind_field = vec4(0.917, -0.400, 0.32, 0.0);

vec2 woodland_flow(vec2 root) {
	vec2 heading = wind_field.xy;
	float along = dot(root, heading);
	float across = dot(root, vec2(-heading.y, heading.x));
	float passing = 0.5 + 0.5 * sin(wind_time * 0.79 - along * 0.23 + sin(across * 0.071) * 0.73);
	return heading * (wind_field.z + wind_field.w * (0.29 + passing * 0.71));
}

vec2 woodland_local_xz(vec2 displacement, mat4 model) {
	vec2 horizontal_x = model[0].xz;
	vec2 horizontal_z = model[2].xz;
	return vec2(dot(displacement, horizontal_x) / max(dot(horizontal_x, horizontal_x), 0.001),
		dot(displacement, horizontal_z) / max(dot(horizontal_z, horizontal_z), 0.001));
}
