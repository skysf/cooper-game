shader_type sky;

#include "res://materials/twilight.gdshaderinc"

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
uniform float cloud_cover = 0.15;
uniform float rain_amount = 0.0;
uniform float room_seconds = 0.0;
uniform float altitude_km = 0.0;
uniform vec2 ground_origin_km;
uniform float ground_rain = 0.0;
uniform float above_clouds = 0.0;

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
	float scattering_angle = dot(d, sun_direction);
	float toward_sun = max(scattering_angle, 0.0);
	float toward_moon = max(dot(d, moon_direction), 0.0);
	float air_mass = exp(-height * 4.8);
	float rayleigh_phase = 0.75 * (1.0 + scattering_angle * scattering_angle);
	vec3 result = mix(sky_zenith.rgb, sky_horizon.rgb, air_mass);
	float clear_day = smoothstep(-0.03, 0.26, sun_direction.y) * (1.0 - rain_amount * 0.94);
	result += vec3(0.15, 0.23, 0.31) * (rayleigh_phase - 0.75) * clear_day * (1.0 - air_mass);
	result = twilight_color(result, d, sun_direction, 0.0);
	float aerosols = smoothstep(-0.19, 0.04, sun_direction.y);
	float wet_shadow = 1.0 - rain_amount * 0.82;
	// A broad aerosol halo joins the narrow glow around the solar disc.
	result += sun_color.rgb * (pow(toward_sun, 13.0) * twilight * 0.10
		+ pow(toward_sun, 44.0) * aerosols * wet_shadow * 0.060);
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
	if (d.y <= -0.015) {
		return below;
	}
	float height = max(d.y, 0.0);
	float horizon = smoothstep(-0.015, 0.19, d.y);
	float toward_sun = max(dot(d, sun_direction), 0.0);
	float warm_clouds = twilight * mix(0.18, 1.0, pow(toward_sun, 3.5));
	vec3 shade = mix(vec3(0.56, 0.62, 0.69), vec3(0.50, 0.39, 0.43), warm_clouds);
	vec3 highlight = mix(vec3(0.96, 0.96, 0.94), vec3(1.0, 0.72, 0.49), warm_clouds);
	vec3 night_cloud = sky_horizon.rgb * 0.75 + vec3(0.009, 0.011, 0.018);

	// Separate wind and perspective for thin high clouds and thicker low clouds.
	vec2 high_wind = vec2(0.00032, 0.00014) * room_seconds;
	vec2 high_uv = d.xz / (height + 0.24) * vec2(0.17, 0.26) + high_wind + vec2(0.42, 0.67);
	float high_mass = noise_field(high_uv);
	float threads = noise_field(high_uv * vec2(1.8, 2.7) + high_mass * 0.14);
	float high_alpha = smoothstep(0.51, 0.76, high_mass * 0.66 + threads * 0.34);
	vec3 high_color = mix(highlight, night_cloud, night_tint);
	vec3 result = mix(below, high_color, high_alpha * horizon * (0.29 - evening_weight * 0.26));

	vec2 wind = vec2(0.00055, -0.00024) * room_seconds;
	vec2 projected = d.xz / (height + 0.18);
	vec2 uv = projected * 0.125 + wind + vec2(0.27, 0.66);
	float local_cover = noise_field(projected * 0.063 + wind + vec2(0.55, 0.33));
	float body = noise_field(uv);
	float billows = noise_field(uv * 2.65 + vec2(0.79, 0.16));
	float wisps = noise_field(uv * 6.4 + vec2(0.33, 0.58));
	float shape = body * 0.53 + billows * 0.35 + wisps * 0.12;
	float base = mix(0.62, 0.36, cloud_cover) + (0.5 - local_cover) * 0.19;
	float density = smoothstep(base - 0.026, base + 0.16, shape);
	density = mix(density, 0.96, rain_amount * 0.68);
	float coverage = (1.0 - exp(-density * mix(2.9, 4.0, rain_amount))) * horizon;
	vec2 sun_offset = sun_direction.xz * 0.036;
	float gradient = (body - noise_field(uv - sun_offset)) * 5.8;
	float rim = pow(toward_sun, 12.0) * (1.0 - density) * 0.48;
	float lit = clamp(0.78 - density * 0.43 + gradient + rim, 0.08, 1.0);
	vec3 cumulus = mix(shade, highlight, lit);
	cumulus = mix(cumulus, vec3(0.28, 0.33, 0.39) * (0.82 + lit * 0.38), rain_amount * 0.86);
	cumulus = mix(cumulus, night_cloud * (0.66 + lit * 0.62), night_tint);
	return mix(result, cumulus, coverage * (1.0 - evening_weight * 0.53));
}

// The camera stays over the playable coast. Intersect the view ray with a distant curved
// surface in planet radii, then sample its coastline and weather in ground-fixed kilometres.
vec3 aerial_view(vec3 d, vec3 clear_sky) {
	float h = altitude_km / 6371.0;
	float height_term = h * (2.0 + h);
	float horizon_y = -sqrt(height_term) / (1.0 + h);
	float elevation = d.y - horizon_y;
	float thin_air = smoothstep(5.0, 72.0, altitude_km);
	float daylight = smoothstep(-0.15, 0.16, sun_direction.y);
	vec3 rim = mix(vec3(0.026, 0.069, 0.16), vec3(0.18, 0.54, 0.85), daylight);
	vec3 upper = clear_sky;
	if (thin_air > 0.0) {
		vec3 space = vec3(0.004, 0.007, 0.016);
		if (elevation > -0.005) {
			space += starlight(d) * mix(0.85, 0.17, daylight);
			space += sun_color.rgb * smoothstep(0.99998, 0.999994, dot(d, sun_direction)) * 1.5;
			if (dot(d, moon_direction) > 0.99997) {
				vec4 moon = moon_disc(d);
				space = mix(space, moon.rgb, moon.a);
			}
		}
		upper = mix(clear_sky, space + rim * exp(-max(elevation, 0.0) * 62.0), thin_air);
	}
	if (elevation >= 0.002) {
		return upper;
	}
	float b = -(1.0 + h) * d.y;
	float travel_km = 6371.0 * height_term / max(b + sqrt(max(b * b - height_term, 0.0)), 0.00001);
	vec2 surface = ground_origin_km + d.xz * travel_km;
	float hills = noise_field(surface * 0.004 + vec2(0.31, 0.57));
	float ridges = noise_field(surface * 0.018 + hills * 0.12);
	// West is out to sea, east is the mainland. Finer noise breaks the shoreline into headlands.
	vec2 local_uv = surface * 0.25 + vec2(0.27, 0.42);
	float relief = noise_field(local_uv);
	float grain = noise_field(local_uv * 7.1);
	float local_coast = surface.x + 0.06 + sin(surface.y * 1.9) * 0.46 + (relief - 0.5) * 0.7;
	float regional_coast = surface.x + (hills - 0.5) * 92.0 + (ridges - 0.5) * 13.0;
	float coast = mix(local_coast, regional_coast, smoothstep(0.9, 20.0, length(surface)));
	vec3 sea = mix(vec3(0.035, 0.16, 0.29), vec3(0.078, 0.30, 0.37), exp(-abs(coast) * 0.95));
	vec3 land = mix(vec3(0.15, 0.23, 0.16), vec3(0.40, 0.37, 0.25), smoothstep(0.30, 0.75, hills * 0.64 + ridges * 0.36));
	float relief_light = relief - noise_field(local_uv + sun_direction.xz * 0.026);
	land *= 0.78 + relief * 0.36 + relief_light * 0.50 + grain * 0.13;
	float shore_width = 0.018 + min(travel_km * 0.0006, 0.36);
	vec3 planet = mix(sea, land, smoothstep(-shore_width, shore_width, coast));
	vec2 cloud_uv = (ground_origin_km + d.xz * travel_km * max(0.0, 1.0 - 2.0 / altitude_km)) * 0.002;
	cloud_uv += vec2(0.00008, -0.00004) * room_seconds;
	float weather_front = noise_field(cloud_uv * 0.73 + vec2(0.37, 0.12));
	cloud_uv.y += weather_front * 0.045;
	float billows = noise_field(cloud_uv * vec2(2.3, 3.8) + vec2(0.17, 0.61));
	float wisps = noise_field(cloud_uv * 11.2 + billows * 0.022);
	float detail = noise_field(cloud_uv * 37.0);
	float bank = smoothstep(0.46 - ground_rain * 0.035, 0.66, 0.45 * weather_front + 0.30 * billows + 0.18 * wisps + 0.07 * detail);
	vec3 clouds = mix(vec3(0.55, 0.64, 0.71), vec3(0.97, 0.97, 0.94), smoothstep(0.25, 0.75, billows * 0.4 + wisps * 0.4 + detail * 0.2));
	planet = mix(planet, clouds, bank * above_clouds);
	vec3 normal = normalize(vec3(d.x * travel_km, 6371.0 + altitude_km + d.y * travel_km, d.z * travel_km));
	float sunlight = smoothstep(-0.12, 0.30, dot(normal, sun_direction));
	planet *= mix(vec3(0.09, 0.13, 0.22), vec3(1.0), sunlight);
	planet = mix(planet, mix(sky_horizon.rgb, rim, thin_air), 0.86 * exp(min(elevation, 0.0) * 13.0));
	return mix(planet, upper, smoothstep(-0.002, 0.002, elevation));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		// Compatibility keeps this cubemap tiny. Direct lighting and water use the room palette.
		COLOR = mix(sky_horizon.rgb, sky_zenith.rgb, max(EYEDIR.y, 0.0));
	} else {
		vec3 direction = normalize(EYEDIR);
		vec3 clear_sky = atmosphere(direction);
		if (altitude_km <= 0.12) {
			COLOR = cloudy_atmosphere(direction, clear_sky);
		} else {
			vec3 aerial = aerial_view(direction, clear_sky);
			float blend = mix(smoothstep(0.12, 0.75, altitude_km), above_clouds, smoothstep(-0.03, 0.07, direction.y));
			COLOR = aerial;
			if (blend < 1.0) {
				COLOR = mix(cloudy_atmosphere(direction, clear_sky), aerial, blend);
			}
		}
	}
}
