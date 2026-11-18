shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;

// The shelter has an open front (+Z) and no environment reflection texture.
// Approximate that window of daylight on the curved glass in world space.
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 reflected = normalize(mat3(INV_VIEW_MATRIX) * reflect(-VIEW, n));
	float grazing = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	float opening = smoothstep(0.26, 0.45, reflected.z)
			* smoothstep(-0.12, 0.16, reflected.y)
			* (1.0 - smoothstep(0.44, 0.64, reflected.y));
	// Two edges of the sunlit doorway catch in the shoulder of the globe.
	float frame = 1.0 - smoothstep(0.012, 0.11, abs(abs(reflected.x) - 0.76));
	frame *= smoothstep(0.25, 0.55, reflected.z) * smoothstep(-0.35, -0.05, reflected.y);
	float sky = smoothstep(-0.12, 0.50, reflected.y);
	ALBEDO = mix(vec3(0.18, 0.23, 0.22), vec3(0.78, 0.84, 0.84), max(max(sky, opening), frame));
	ALPHA = 0.035 + 0.40 * grazing + 0.15 * opening + 0.32 * frame;
}
