uniform sampler2D evening_sky : source_color, repeat_enable, filter_linear_mipmap;
uniform float evening_weight = 0.0;
uniform float twilight = 0.0;

vec3 twilight_color(vec3 base, vec3 direction, vec3 sun, float mip_level) {
	if (twilight <= 0.001) {
		return base;
	}
	float height = max(direction.y, 0.0);
	if (evening_weight > 0.001 && height > 0.035) {
		// The panorama's warmest point lies at the center of the photograph.
		vec2 forward = normalize(sun.xz);
		vec2 right = vec2(-forward.y, forward.x);
		vec2 uv = vec2(0.5 + atan(dot(direction.xz, right), dot(direction.xz, forward)) / TAU,
			clamp(1.0 - asin(min(height, 1.0)) * 2.0 / PI, 0.001, 0.999));
		vec3 photo = textureLod(evening_sky, uv, mip_level).rgb;
		base = mix(base, photo, evening_weight * smoothstep(0.035, 0.20, height));
	}
	float sunward = max(dot(direction, sun), 0.0);
	float haze = twilight * exp(-height * 8.0) * pow(sunward, 6.0);
	return mix(base, vec3(0.96, 0.58, 0.29), haze * 0.56);
}
