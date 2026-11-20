vec3 water_rain_hash(vec3 key) {
	vec3 value = fract(key * vec3(0.1127, 0.1379, 0.1911));
	value += dot(value, value.zxy + vec3(13.917, 37.813, 24.701));
	return fract(vec3(value.x * value.z + value.y, value.x * value.y + value.z, value.y * value.z + value.x));
}

vec2 water_rain_cell(vec2 grid, vec2 pixel_x, vec2 pixel_y, float time, float rain, float density) {
	vec2 cell = floor(grid);
	vec3 seed = water_rain_hash(vec3(cell, 4.71));
	float clock = time * (1.43 + 0.91 * seed.x) + seed.y * 41.3;
	float age = fract(clock);
	vec3 impact = water_rain_hash(vec3(cell, floor(clock)) + vec3(11.0, 37.0, 79.0));
	float arrival = smoothstep(impact.z, impact.z + 0.13, rain * density);
	float life = smoothstep(0.02, 0.15, age) * (1.0 - smoothstep(0.15, 0.87, age)) * arrival;
	if (life <= 0.002) {
		return vec2(0.0);
	}

	// Ring support stays within the cell. Age, ellipse and maximum size vary at each impact.
	vec2 offset = fract(grid) - (0.25 + 0.50 * impact.xy);
	float bearing = fract(impact.x * 5.18 + impact.y * 11.73 + seed.z) * 6.2831853;
	vec2 axis = vec2(cos(bearing), sin(bearing));
	vec2 cross_axis = vec2(-axis.y, axis.x);
	float stretch = mix(1.03, 1.42, fract(impact.y * 9.13 + impact.z * 3.13));
	vec2 local = vec2(dot(offset, axis), dot(offset, cross_axis) * stretch);
	float distance_from_drop = length(local);
	float inverse_radius = 1.0 / max(distance_from_drop, 0.009);
	vec2 radial = (axis * local.x + cross_axis * local.y * stretch) * inverse_radius;
	float size = mix(0.54, 1.13, fract(impact.x * 7.17 + impact.z * 2.83));
	float radius = (0.011 + 0.155 * sqrt(age)) * size;
	float band = mix(0.039, 0.031, age) * sqrt(size);

	// Filter the signed slope across a pixel. Growing filter support must carry less energy.
	float footprint = abs(dot(radial, pixel_x)) + abs(dot(radial, pixel_y));
	float filtered = max(band, footprint * 0.64);
	float resolved = band / filtered;
	float q = clamp((distance_from_drop - radius) / min(filtered, 0.060), -1.0, 1.0);
	float envelope = 1.0 - q * q;
	float crest_shape = 0.86 + 0.14 * local.x * inverse_radius;
	float strength = mix(0.054, 0.112, size) * life * resolved * resolved * crest_shape;
	return radial * (3.4939 * q * envelope * envelope * strength);
}

vec2 water_rain_ripples(vec2 point, vec2 current, float eye_distance, float time, float rain, float strength) {
	// The dry material skips hashing, derivative filtering and the profile entirely.
	if (rain <= 0.01) {
		return vec2(0.0);
	}
	vec2 surface = point + current * 0.115;
	vec2 pixel_x = dFdx(surface);
	vec2 pixel_y = dFdy(surface);
	float footprint = max(length(pixel_x), length(pixel_y));
	float detail = (1.0 - smoothstep(7.5, 22.0, eye_distance)) * (1.0 - smoothstep(0.055, 0.13, footprint));
	if (detail <= 0.002) {
		return vec2(0.0);
	}
	// Independent rotated grids and sparse impact times prevent aligned rows.
	mat2 wide_axes = mat2(vec2(0.891, -0.454), vec2(0.454, 0.891));
	mat2 fine_axes = mat2(vec2(0.7547, 0.6561), vec2(-0.6561, 0.7547));
	mat2 wide_grid = wide_axes * 2.08;
	mat2 fine_grid = fine_axes * 3.59;
	vec2 broad = water_rain_cell(wide_grid * surface, wide_grid * pixel_x, wide_grid * pixel_y, time, rain, 0.67);
	vec2 fine = water_rain_cell(fine_grid * surface + vec2(4.72, 1.36), fine_grid * pixel_x,
		fine_grid * pixel_y, time + 2.35, rain, 0.45);
	return (transpose(wide_axes) * broad + transpose(fine_axes) * fine * 0.76) * (detail * strength);
}
