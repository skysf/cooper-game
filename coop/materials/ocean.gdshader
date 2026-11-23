shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

#include "res://materials/water_rain.gdshaderinc"

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D wave_slopes : filter_linear_mipmap, repeat_enable;
uniform sampler2D tide_field : filter_linear, repeat_disable;
uniform sampler2D sand_color : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_color : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 field_rect;
uniform float water_time;
uniform float rain_amount;
uniform float sunlight = 1.0;
uniform vec3 sun_direction = vec3(-0.52, 0.73, 0.44);
uniform vec4 sky_zenith : source_color = vec4(0.25, 0.43, 0.63, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.73, 0.81, 0.85, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.93, 0.79, 1.0);
varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 point = world_at.xz;
	vec3 toward_eye = CAMERA_POSITION_WORLD - world_at;
	float distance_to_eye = length(toward_eye);
	vec3 eye = toward_eye / max(distance_to_eye, 0.01);
	vec2 current = texture(wave_slopes, point * 0.027 + vec2(-0.011, 0.007) * water_time).rg - 0.5;
	float swell = point.x * 0.266 + point.y * 0.106 - water_time * 1.52 + current.x * 8.7;
	float short_swell = point.x * 0.83 - point.y * 0.29 - water_time * 2.1 + current.y * 3.8;
	float swell_detail = (1.0 - smoothstep(0.5, 1.5, fwidth(swell)));
	vec2 wind = texture(wave_slopes, point * 0.216 + vec2(-0.063, 0.031) * water_time).rg - 0.5;
	vec2 chop = texture(wave_slopes, vec2(point.y, -point.x) * 0.478 + vec2(0.017, -0.041) * water_time).rg - 0.5;
	vec2 waves = wind * 0.25 + vec2(chop.y, -chop.x) * 0.13;
	waves += (vec2(0.036, 0.024) * cos(swell) + vec2(0.018, -0.015) * cos(short_swell)) * swell_detail * (1.0 - smoothstep(45.0, 105.0, distance_to_eye));
	waves *= 1.0 + rain_amount * 0.62;
	// The same impacts resolve against a broader sky reflection on the open sea.
	waves += water_rain_ripples(point, current, distance_to_eye, water_time, rain_amount, 1.32);
	vec3 normal = normalize(vec3(waves.x, 1.0, waves.y));
	float daylight = mix(0.09, 1.0, max(sunlight, clamp(sky_zenith.b * 0.72, 0.0, 0.44)));
	if (eye.y < 0.0) {
		float incidence = max(-dot(normal, eye), 0.0);
		float window = smoothstep(0.630, 0.703, incidence);
		vec3 through = refract(-eye, -normal, 1.333);
		vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, pow(clamp(through.y, 0.0, 1.0), 0.62));
		vec3 reflection = vec3(0.065, 0.29, 0.32) * daylight + sky_horizon.rgb * 0.045;
		ALBEDO = mix(reflection, sky, window);
		ALPHA = mix(0.93, 0.32, window);
	} else {
		float raw_depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
		vec4 bed = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float path = clamp((-bed.z / bed.w + VERTEX.z) * distance_to_eye / max(-VERTEX.z, 0.07), 0.0, 88.0);
		vec2 field_uv = (point - field_rect.xy) / field_rect.zw;
		vec2 field_size = vec2(textureSize(tide_field, 0));
		vec2 field_edge = min(field_uv, 1.0 - field_uv);
		float field_inside = smoothstep(0.0, 0.04, min(field_edge.x, field_edge.y));
		vec2 field_texel = (field_uv * (field_size - 1.0) + 0.5) / field_size;
		vec4 shore = texture(tide_field, field_texel);
		float sea_depth = mix(24.0, shore.x * 28.0, field_inside);
		vec3 transmitted = refract(-eye, normal, 0.75);
		float optical_path = min(88.0, sea_depth / max(0.50, -transmitted.y));
		vec2 bottom_uv = field_texel + transmitted.xz * optical_path / field_rect.zw;
		vec4 bottom = texture(tide_field, bottom_uv);
		sea_depth = mix(sea_depth, bottom.r * 28.0, field_inside * 0.24);
		optical_path = sea_depth / max(0.50, -transmitted.y);

		vec3 reflected = reflect(-eye, normal);
		vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, pow(max(0.0, reflected.y), 0.67));
		float fresnel = 0.024 + 0.976 * pow(1.0 - max(dot(normal, eye), 0.0), 5.0);
		vec3 lagoon = mix(vec3(0.13, 0.65, 0.55), vec3(0.018, 0.49, 0.49), smoothstep(0.65, 5.1, sea_depth));
		vec3 ocean = mix(lagoon, vec3(0.013, 0.16, 0.317), smoothstep(3.8, 19.0, sea_depth));
		vec3 wet_ocean = mix(vec3(0.113, 0.444, 0.437), vec3(0.067, 0.212, 0.283), smoothstep(1.2, 16.0, sea_depth));
		ocean = mix(ocean, wet_ocean, rain_amount * 0.62) * daylight;
		float scatter = (1.0 - fresnel) * (1.0 - exp(-optical_path * (0.188 + rain_amount * 0.075)));
		float substrate_weight = field_inside * (1.0 - fresnel) * exp(-optical_path * 0.185) * 0.92;
		vec2 bed_point = point + transmitted.xz * optical_path;
		vec3 sand = texture(sand_color, bed_point * 0.67).rgb * vec3(0.94, 0.95, 0.88);
		vec3 rock = texture(rock_color, bed_point * 0.41).rgb * vec3(0.49, 0.65, 0.56);
		float contrast = smoothstep(0.29, 0.74, bottom.a + current.x * 0.16);
		vec3 floor_color = mix(sand, rock, contrast) * daylight;
		floor_color *= exp(-vec3(0.24, 0.064, 0.041) * optical_path);
		float caustic = pow(max(0.0, cos(short_swell * 2.7 + wind.x * 7.8)), 8.0);
		floor_color *= 0.91 + caustic * 0.14 * sunlight;
		float opacity = max(0.012, fresnel + scatter + substrate_weight);
		vec3 color = ocean * scatter + sky * fresnel + floor_color * substrate_weight;
		float half_reflect = max(dot(normal, normalize(eye + sun_direction)), 0.0);
		float glint = sunlight * (pow(half_reflect, mix(890.0, 410.0, rain_amount)) * mix(1.26, 0.64, rain_amount)
			+ pow(half_reflect, 98.0) * 0.16);
		color += sun_color.rgb * glint;

		vec2 shift = vec2(0.61 + .36 * sin(swell), 0.21 * sin(short_swell + 1.5)) / field_rect.zw;
		float breaker = texture(tide_field, field_texel + shift).g * field_inside;
		float foam_distortion = texture(wave_slopes, point * 0.41 + wind * 0.39 - vec2(water_time * 0.074, 0.0)).g;
		float broken = smoothstep(0.21, 0.76, foam_distortion + cos(swell) * 0.15);
		float lace = broken * smoothstep(0.24, 0.86, sin(short_swell * 1.48 + wind.y * 8.1));
		float breakers = smoothstep(0.515, 0.84, breaker) * (0.17 + 0.61 * broken + 0.22 * lace);
		float wash = shore.b * field_inside * (0.061 + 0.73 * smoothstep(0.32, 0.93, cos(short_swell * 0.75)) * broken);
		float foam = clamp(max(wash, breakers), 0.0, 0.94);
		vec3 salt = vec3(0.81, 0.93, 0.91) * daylight + sky_horizon.rgb * 0.07;
		opacity = mix(opacity, 0.96, foam);
		color = mix(color, salt, foam);
		vec3 surface = color / max(opacity, 0.10);
		float haze = smoothstep(mix(94.0, 48.0, rain_amount), mix(275.0, 214.0, rain_amount), distance_to_eye);
		// Above the coast the finite wave mesh merges into the sea in the aerial panorama.
		float aerial = smoothstep(90.0, 710.0, toward_eye.y);
		ALBEDO = mix(surface, sky_horizon.rgb, haze * (1.0 - aerial * 0.85));
		ALPHA = clamp(opacity + glint * 0.12, 0.0, 1.0) * smoothstep(0.012, 0.072, path)
			* mix(1.0, field_inside, aerial) * (1.0 - smoothstep(1800.0, 4100.0, toward_eye.y));
	}
}
