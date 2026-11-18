shader_type sky;

uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D star_catalog : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D milky_way_photo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D lunar_surface : source_color, filter_linear_mipmap;
uniform bool photographic_galaxy = false;
uniform bool photographic_moon = false;
uniform vec3 sun_direction = vec3(-0.6, 0.5, 0.6);
uniform vec3 moon_direction = vec3(-0.8, 0.5, 0.5);
uniform vec3 celestial_north = vec3(0.0, 0.682, -0.731);
uniform vec3 galactic_center;
uniform vec3 galactic_east;
uniform vec3 galactic_north;
uniform vec4 sky_zenith : source_color = vec4(0.23, 0.43, 0.65, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.61, 0.72, 0.75, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.84, 0.57, 1.0);
uniform float star_visibility = 0.0;
uniform float night_tint = 0.0;
uniform float sunset = 0.0;
uniform float cloud_cover = 0.15;
uniform float rain_amount = 0.0;
uniform float room_seconds = 0.0;

float noise_field(vec2 p) {
	return texture(cloud_noise, p).r;
}

vec2 spherical_uv(vec3 d) {
	return vec2(0.5 - atan(d.y, d.x) / TAU, 0.5 - asin(clamp(d.z, -1.0, 1.0)) / PI);
}

vec3 galactic_dust(vec2 uv) {
	float longitude = (uv.x - 0.5) * TAU;
	float latitude = (uv.y - 0.5) * PI;
	float bulge = pow(max(cos(longitude * 0.5), 0.0), 14.0);
	vec2 dust_position = vec2(uv.x * 2.1, uv.y * 6.2);
	float filament = noise_field(dust_position) * 0.67 + noise_field(dust_position * 2.4 + vec2(0.52, 0.27)) * 0.33;
	float streak = noise_field(vec2(uv.x * 5.2, uv.y * 19.7) + vec2(0.27, 0.38));
	float disc = exp(-abs(latitude + (filament - 0.5) * 0.11) / (0.064 + bulge * 0.077));
	float lane = exp(-abs(latitude + (streak - 0.5) * 0.15) / 0.026) * smoothstep(0.31, 0.64, filament) * 0.94;
	float clouds = disc * (0.15 + filament * filament * 1.45) * (1.0 - lane);
	return mix(vec3(0.16, 0.19, 0.28), vec3(0.43, 0.36, 0.29), bulge * 0.7) * clouds;
}

vec3 starlight(vec3 d) {
	vec3 galactic = vec3(dot(d, galactic_center), dot(d, galactic_east), dot(d, galactic_north));
	vec2 uv = spherical_uv(galactic);
	if (photographic_galaxy) {
		vec3 photo = texture(milky_way_photo, uv).rgb;
		return max(photo - vec3(0.004), vec3(0.0)) * 0.78;
	}
	return galactic_dust(uv) + texture(star_catalog, uv).rgb * 2.15;
}

float mare(vec2 point, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.64, 1.25, length((point - center) / radius));
}

vec4 moon_disc(vec3 d) {
	vec3 right = normalize(cross(moon_direction, celestial_north));
	vec3 up = cross(right, moon_direction);
	// A 0.52 degree diameter, resolved across several pixels at the game FOV.
	vec2 q = vec2(dot(d, right), dot(d, up)) / 0.00454;
	float r2 = dot(q, q);
	float edge = 1.0 - smoothstep(0.72, 1.24, r2);
	float surface_depth = sqrt(max(1.0 - r2, 0.0));
	vec3 normal = normalize(right * q.x + up * q.y - moon_direction * surface_depth);
	float illumination = max(dot(normal, sun_direction), 0.0);
	float earthshine = 0.014 * night_tint;
	vec3 albedo;
	if (photographic_moon) {
		vec2 moon_uv = vec2(0.5 + atan(q.x, max(surface_depth, 0.0001)) / TAU, 0.5 - asin(clamp(q.y, -1.0, 1.0)) / PI);
		albedo = mix(vec3(0.3), vec3(1.15), texture(lunar_surface, moon_uv).rgb);
	} else {
		float detail = noise_field(q * 0.65 + vec2(0.5));
		float maria = max(mare(q, vec2(-0.43, 0.20), vec2(0.37, 0.45)), mare(q, vec2(0.16, 0.34), vec2(0.29, 0.25)));
		maria = max(maria, mare(q, vec2(0.37, 0.10), vec2(0.30, 0.22)));
		albedo = vec3(0.78 + 0.26 * detail - maria * (0.14 + detail * 0.31));
	}
	vec3 disc = vec3(0.98, 0.96, 0.88) * (pow(illumination, 0.52) * 1.48 + earthshine) * albedo;
	return vec4(disc, edge);
}

vec3 atmosphere(vec3 d) {
	float height = max(d.y, 0.0);
	float toward_sun = max(dot(d, sun_direction), 0.0);
	float toward_moon = max(dot(d, moon_direction), 0.0);
	vec3 result = mix(sky_horizon.rgb, sky_zenith.rgb, smoothstep(0.0, 0.76, pow(height, 0.66)));
	float horizon_mist = exp(-height * 8.8);
	float aerosols = smoothstep(-0.19, 0.04, sun_direction.y);
	float wet_shadow = 1.0 - rain_amount * 0.82;
	float glow = sunset * pow(toward_sun, 8.0) * horizon_mist * wet_shadow;
	result = mix(result, vec3(0.94, 0.54, 0.20), glow * 0.60);
	result += vec3(0.75, 0.24, 0.05) * glow * 0.23;
	result += sun_color.rgb * pow(toward_sun, 34.0) * aerosols * wet_shadow * (0.028 + sunset * 0.16);
	float lunar_bloom = max(-dot(sun_direction, moon_direction) * 0.5 + 0.5, 0.0) * smoothstep(-0.03, 0.1, moon_direction.y);
	if (star_visibility > 0.003 && d.y > -0.04) {
		float moon_washout = lunar_bloom * (0.19 + 0.46 * pow(toward_moon, 9.0));
		float extinction = smoothstep(-0.008, 0.24, height);
		result += starlight(d) * star_visibility * (1.0 - moon_washout) * extinction;
		result += vec3(0.053, 0.069, 0.106) * pow(toward_moon, 35.0) * lunar_bloom * night_tint;
	}
	if (toward_sun > 0.99996 && sun_direction.y > -0.014) {
		float disc = smoothstep(0.999985, 0.999992, toward_sun);
		result += mix(vec3(1.0, 0.49, 0.20), vec3(1.0, 0.95, 0.86), smoothstep(-0.012, 0.10, sun_direction.y)) * disc * 1.36;
	}
	if (toward_moon > 0.99997 && moon_direction.y > -0.009) {
		vec4 moon = moon_disc(d);
		result = mix(result, moon.rgb + result * (1.0 - night_tint * 0.94), moon.a * 0.97);
	}
	return result;
}

vec3 cloudy_atmosphere(vec3 d, vec3 below) {
	float height = max(d.y, 0.0);
	vec2 projected = d.xz / (height + 0.21);
	vec2 drift = vec2(room_seconds * 0.00012, room_seconds * -0.000068);
	vec2 high_uv = projected * vec2(0.124, 0.254) + drift * 0.52;
	float high_cloud = noise_field(high_uv + vec2(0.38, 0.83)) * 0.72 + noise_field(high_uv * 2.48 + vec2(0.08, 0.34)) * 0.28;
	float high_alpha = smoothstep(0.51 - cloud_cover * 0.11, 0.76, high_cloud) * (0.34 + cloud_cover * 0.12);
	float rise = smoothstep(-0.035, 0.12, d.y);
	float solar_side = pow(max(dot(d, sun_direction), 0.0), 4.2);
	float glowing_clouds = sunset * solar_side * (1.0 - rain_amount * 0.82);
	vec3 lit_cloud = mix(vec3(0.65, 0.73, 0.78), vec3(0.94, 0.46, 0.24), glowing_clouds * 0.84);
	vec3 dark_cloud = sky_horizon.rgb * 0.77 + vec3(0.009, 0.011, 0.018);
	vec3 high_color = mix(lit_cloud, dark_cloud, night_tint);
	vec3 result = mix(below, high_color, high_alpha * rise);

	vec2 uv = projected * vec2(0.152, 0.229) + drift + vec2(0.26, 0.47);
	float body = noise_field(uv);
	float masses = body * 0.61 + noise_field(uv * 2.78 + vec2(0.79, 0.16)) * 0.27;
	float fine = noise_field(uv * 6.15 + vec2(0.33, 0.58));
	float shape = masses + fine * 0.12;
	float edge = mix(0.61, 0.27, cloud_cover);
	float thickness = smoothstep(edge - 0.05, edge + 0.18, shape);
	thickness = mix(thickness, 0.93, rain_amount * 0.51);
	float edge_light = clamp((noise_field(uv - sun_direction.xz * 0.031) - body) * 5.5 + 0.28, 0.0, 1.0);
	vec3 rim = mix(vec3(0.81, 0.85, 0.86), vec3(1.0, 0.53, 0.25), glowing_clouds * 0.86);
	vec3 underside = mix(vec3(0.36, 0.44, 0.52), vec3(0.23, 0.28, 0.33), rain_amount);
	vec3 cumulus = mix(underside, rim, edge_light * (1.0 - rain_amount * 0.78));
	cumulus = mix(cumulus, sky_zenith.rgb * 1.05, rain_amount * 0.44);
	cumulus = mix(cumulus, dark_cloud * (0.73 + edge_light * 0.57), night_tint);
	float coverage = thickness * mix(0.76, 0.965, cloud_cover) * rise;
	return mix(result, cumulus, coverage);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		// Compatibility keeps this cubemap tiny. Direct lighting and water use the room palette.
		COLOR = mix(sky_horizon.rgb, sky_zenith.rgb, max(EYEDIR.y, 0.0));
	} else {
		vec3 direction = normalize(EYEDIR);
		COLOR = cloudy_atmosphere(direction, atmosphere(direction));
	}
}
