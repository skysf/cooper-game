shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_field : repeat_enable, filter_linear_mipmap;
uniform sampler2D contact_shade : hint_default_white, repeat_disable, filter_linear_mipmap;
uniform vec3 refracted_sun = vec3(0.0, 0.65, 0.0);
uniform float room_time;

void fragment() {
	float depth = UV2.x;
	float silt = UV2.y;
	float wet_edge = smoothstep(-0.047, 0.032, depth);
	float submerged = smoothstep(0.015, 0.21, depth);
	vec2 uv = UV / 2.9;
	vec3 stones = texture(gravel, uv).rgb;
	float mineral = dot(stones, vec3(0.27, 0.57, 0.16));
	vec3 sediment = vec3(0.32, 0.29, 0.22) * (0.63 + mineral * 0.72);
	vec3 floor_color = mix(stones, sediment, smoothstep(0.24, 0.85, silt) * 0.72);
	floor_color *= mix(vec3(1.04, 0.99, 0.91), vec3(0.77, 0.80, 0.75), wet_edge);
	floor_color *= mix(vec3(1.0), vec3(0.68, 0.82, 0.80), smoothstep(0.1, 2.3, depth));
	float contact = texture(contact_shade, UV * 0.025 + vec2(1.15, 1.75)).r;
	floor_color *= contact;
	if (submerged * refracted_sun.y > 0.005) {
		// Sample the sun's projected footpoint on the surface, so the pattern follows
		// the water and travels farther across deeper parts of the bed at low sun.
		vec2 incoming = UV + refracted_sun.xz * depth;
		vec2 field_uv = incoming * 0.294 + vec2(-0.049, 0.013) * room_time;
		float focus = texture(ripple_field, field_uv).b;
		vec2 cross_uv = vec2(incoming.y, -incoming.x) * 0.236 + vec2(0.027, -0.019) * room_time;
		focus = smoothstep(0.34, 0.84, focus * 0.78 + texture(ripple_field, cross_uv).b * 0.30);
		float patch = 0.10 + 0.90 * smoothstep(0.26, 0.71, silt);
		float irradiance = refracted_sun.y * submerged * patch * contact * (1.0 - 0.57 * smoothstep(0.55, 2.30, depth));
		floor_color *= 1.0 + (focus - 0.075) * irradiance * vec3(0.51, 0.52, 0.42);
	}
	vec3 relief = texture(gravel_normal, uv).rgb * 2.0 - 1.0;
	// UV runs along world +X/+Z; map the photographed slopes onto the basin normal.
	vec3 micro = mat3(VIEW_MATRIX) * vec3(relief.x, 0.0, -relief.y);
	NORMAL = normalize(NORMAL + micro * (0.52 - 0.26 * silt));
	ALBEDO = floor_color;
	ROUGHNESS = mix(0.94, 0.69, wet_edge);
}
