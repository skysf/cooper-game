shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D shore_reflection : hint_default_black, repeat_disable, filter_linear;
uniform float reflection_strength = 0.0;
uniform bool lake_surface = false;
uniform vec2 lake_center = vec2(-26.0, -50.0);
uniform vec2 lake_radius = vec2(15.0, 17.0);
uniform vec3 sun_direction = vec3(-0.74, 0.3, 0.6);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec4 sky_zenith : source_color = vec4(0.24, 0.42, 0.59, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.57, 0.68, 0.72, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.79, 0.53, 1.0);
uniform vec4 moon_color : source_color = vec4(0.52, 0.62, 0.8, 1.0);
uniform float water_time;
uniform float rain_amount;
uniform float cloud_cover;
uniform vec4 impacts[6];
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float lake_distance(vec2 point) {
	vec2 local = (point - lake_center) / lake_radius;
	float angle = atan(local.y, local.x);
	float edge = 1.0 + 0.047 * sin(angle * 3.0 + 0.9) + 0.025 * cos(angle * 5.0 + 0.4)
		+ 0.018 * sin(angle * 9.0 + 0.3);
	return length(local) / edge;
}

vec2 wave(vec2 point, vec2 direction, float frequency, float amplitude, float phase) {
	float angle = dot(point, direction) * frequency + phase;
	float detail = 1.0 - smoothstep(0.38, 2.5, fwidth(angle));
	return direction * cos(angle) * amplitude * detail;
}

vec2 hash2(vec2 cell) {
	vec2 h = vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)));
	return fract(sin(h) * 43758.55);
}

vec2 rain_ripple(vec2 point, float frequency, float time) {
	vec2 grid = point * frequency;
	vec2 h = hash2(floor(grid));
	float clock = time * (1.7 + h.x * 0.55) + h.y * 16.0;
	vec2 center = mix(vec2(0.27), vec2(0.73), fract(h + floor(clock) * vec2(0.379, 0.613)));
	vec2 offset = fract(grid) - center;
	float age = fract(clock);
	float radius = length(offset);
	float ring = radius - age * 0.30;
	float envelope = (1.0 - age) * exp(-ring * ring * 440.0);
	return offset / max(radius, 0.04) * sin(ring * 106.0) * envelope;
}

float glint(vec3 normal, vec3 to_camera, vec3 direction, float sharpness) {
	vec3 half_direction = normalize(to_camera + direction);
	float n_dot_h = max(dot(normal, half_direction), 0.0);
	return pow(n_dot_h, sharpness);
}

void fragment() {
	vec2 point = world_position.xz;
	if (!lake_surface && lake_distance(point) < 1.0) {
		discard;
	}

	float time = water_time;
	float slope = mix(1.0, 1.62, rain_amount);
	vec2 waves = wave(point, vec2(0.88, 0.475), 4.1, 0.023, time * 1.7);
	waves += wave(point, vec2(-0.32, 0.947), 7.6, 0.017, time * 2.16);
	waves += wave(point, vec2(0.63, -0.777), 15.8, 0.015, time * 3.14);
	waves += wave(point, vec2(-0.71, -0.704), 26.0, 0.009, time * 3.92);
	if (!lake_surface) {
		waves += wave(point, vec2(0.22, -0.975), 11.0, 0.034, time * 3.4);
	}
	waves *= slope;
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - world_position);
	float close_detail = 1.0 - smoothstep(10.0, 24.0, distance(world_position, CAMERA_POSITION_WORLD));
	if (rain_amount > 0.01 && close_detail > 0.0) {
		waves += (rain_ripple(point, 2.9, time) + rain_ripple(point + vec2(0.23, 0.74), 2.1, time))
			* rain_amount * close_detail * 0.045;
	}

	float splash_glow = 0.0;
	for (int i = 0; i < 6; i++) {
		float age = time - impacts[i].z;
		if (impacts[i].w > 0.0 && age >= 0.0 && age < 2.9) {
			vec2 offset = point - impacts[i].xy;
			float radius = length(offset);
			float ring = radius - age * (1.4 - age * 0.11);
			float envelope = exp(-ring * ring * 27.0 - age * 0.87) * smoothstep(0.0, 0.09, age);
			waves += offset / max(radius, 0.045) * sin(ring * 39.0) * envelope * 0.125;
			splash_glow += envelope * max(0.0, cos(ring * 39.0)) * 0.13;
		}
	}

	vec3 normal = normalize(vec3(waves.x, 1.0, waves.y));
	vec3 reflected = reflect(-to_camera, normal);
	float sky_height = max(0.0, reflected.y);
	vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, pow(sky_height, 0.60));
	vec3 reflected_color = sky;
	if (reflection_strength > 0.001) {
		vec2 mirrored = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + waves * vec2(0.87, 1.4);
		vec2 edge = min(mirrored, 1.0 - mirrored);
		float visible = smoothstep(0.0, 0.035, min(edge.x, edge.y));
		reflected_color = mix(sky, texture(shore_reflection, mirrored).rgb, visible * reflection_strength);
	}
	float fresnel = 0.026 + 0.974 * pow(1.0 - max(dot(normal, to_camera), 0.0), 5.0);

	float raw_depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 scene_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float depth = max(0.0, -scene_position.z / scene_position.w + VERTEX.z);
	float absorption = 1.0 - exp(-depth * 0.94);
	vec3 water = mix(vec3(0.15, 0.25, 0.18), vec3(0.018, 0.082, 0.072), absorption);
	float ambient = clamp(max(sky_zenith.g, sky_horizon.r * 0.78) * 1.36 + 0.13, 0.10, 1.0);
	water *= ambient;
	vec3 color = mix(water, reflected_color, fresnel);

	float sun_visible = smoothstep(-0.018, 0.025, sun_direction.y) * (1.0 - cloud_cover * 0.88);
	float moon_phase = clamp((1.0 - dot(sun_direction, moon_direction)) * 0.5, 0.0, 1.0);
	float moon_visible = smoothstep(0.0, 0.055, moon_direction.y) * smoothstep(0.035, 0.20, -sun_direction.y)
		* pow(moon_phase, 1.4) * (1.0 - cloud_cover * 0.86);
	float sun_glint = glint(normal, to_camera, sun_direction, mix(1580.0, 860.0, rain_amount));
	sun_glint = sun_glint * 2.72 + glint(normal, to_camera, sun_direction, 155.0) * 0.20;
	float moon_glint = glint(normal, to_camera, moon_direction, 1100.0) * 0.33;
	color += sun_color.rgb * sun_glint * sun_visible + moon_color.rgb * moon_glint * moon_visible;
	color += splash_glow * mix(vec3(0.24, 0.35, 0.35), vec3(0.73, 0.82, 0.74), ambient);

	ALBEDO = color;
	float shore_opacity = smoothstep(0.005, 0.09, depth);
	float opacity = mix(0.22 + absorption * 0.75, 0.98, fresnel);
	ALPHA = clamp(opacity * shore_opacity + (sun_glint * sun_visible * 0.18 + splash_glow * 1.5) * shore_opacity, 0.0, 0.98);
}
