shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, world_vertex_coords;

uniform float fire_time;
uniform float fire_power = 1.0;
uniform vec2 fire_wind;
varying float fire_seed;

float hash_cell(vec2 cell) {
	vec3 key = fract(cell.xyx * vec3(0.1031, 0.11369, 0.13787));
	key += dot(key, key.yzx + 19.19);
	return fract((key.x + key.y) * key.z);
}

float noise_cell(vec2 point) {
	vec2 cell = floor(point);
	vec2 corner = fract(point);
	vec2 blend = corner * corner * (3.0 - 2.0 * corner);
	float near_edge = mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x);
	float far_edge = mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), blend.x);
	return mix(near_edge, far_edge, blend.y);
}

float lick(vec2 point, float center, float height, float phase) {
	float reach = height * (0.88 + 0.12 * sin(phase) + 0.07 * sin(phase * 1.87));
	float age = clamp(point.y / reach, 0.0, 1.0);
	float spread = mix(0.14, 0.018, pow(age, 0.72));
	float curling = sin(point.y * 12.0 - phase) * age * 0.057;
	float contour = spread - abs(point.x - center - curling);
	return smoothstep(-0.023, 0.047, min(contour, (reach - point.y) * 0.7));
}

float sparks(vec2 point, float time) {
	float brightness = 0.0;
	for (int i = 0; i < 4; i++) {
		float seed = float(i) * 0.247 + fire_seed;
		float life = fract(time * (0.69 + 0.24 * seed) + seed);
		vec2 center = vec2((seed - 0.76) * 0.24 + life * sin(seed * 23.0) * 0.11,
			0.20 + life * (0.29 + 0.18 * seed));
		float core = 1.0 - smoothstep(0.001, 0.010, length((point - center) * vec2(1.0, 0.72)));
		brightness = max(brightness, core * smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.52, 0.94, life)));
	}
	return brightness;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 right = normalize(INV_VIEW_MATRIX[0].xz);
	float lift = 1.0 - UV.y;
	float across = (UV.x - 0.5) * 0.93;
	vec2 gust = fire_wind * (0.23 * lift * lift);
	VERTEX = origin + vec3(right.x * across + gust.x, lift * 1.16, right.y * across + gust.y);
	fire_seed = fract(dot(origin.xz, vec2(0.523, 0.219)));
}

void fragment() {
	vec2 point = vec2(UV.x - 0.5, 1.0 - UV.y);
	float time = fire_time + fire_seed * 11.0;
	float grain = noise_cell(point * vec2(14.0, 25.0) - vec2(0.0, time * 5.2));
	float broad = noise_cell(point * vec2(8.0, 11.0) - vec2(0.0, time * 2.1));
	vec2 flame_at = point;
	flame_at.y /= mix(0.46, 1.0, fire_power);
	flame_at.x += (grain - 0.5) * (0.026 + flame_at.y * 0.086);
	float flame = max(lick(flame_at, -0.098, 0.34, time * 6.4), lick(flame_at, 0.025, 0.46, time * 4.9 + 2.3));
	flame = max(flame, lick(flame_at, 0.117, 0.29, time * 8.2 + 1.1));
	float base = smoothstep(0.0, 0.043, point.y);
	float flame_alpha = flame * base * mix(0.74, 0.97, broad) * fire_power;
	float center = smoothstep(0.32, 0.92, flame) * (1.0 - smoothstep(0.10, 0.36, flame_at.y));
	float filament = noise_cell(point * vec2(31.0, 54.0) - vec2(0.0, time * 9.5));
	center *= mix(0.58, 1.0, smoothstep(0.22, 0.82, grain * 0.63 + filament * 0.37));
	vec3 fire_color = mix(vec3(0.66, 0.071, 0.004), vec3(1.0, 0.35, 0.027), smoothstep(0.05, 0.62, flame));
	fire_color = mix(fire_color, vec3(1.0, 0.83, 0.55), center);
	float embers = sparks(point, time) * fire_power;
	fire_color = mix(fire_color, vec3(1.0, 0.70, 0.25), embers);
	flame_alpha = max(flame_alpha, embers * 0.88);
	float plume_width = mix(0.17, 0.42, point.y);
	float plume_x = point.x + sin(point.y * 8.5 - time * 2.1) * 0.058 * point.y;
	float smoke = (1.0 - smoothstep(plume_width * 0.22, plume_width, abs(plume_x))) * smoothstep(0.24, 0.55, point.y);
	smoke *= (1.0 - smoothstep(0.77, 1.0, point.y)) * smoothstep(0.25, 0.77, broad) * 0.26 * fire_power;
	vec3 smoke_color = mix(vec3(0.115, 0.103, 0.087), vec3(0.20, 0.19, 0.17), point.y);
	ALPHA = flame_alpha + smoke * (1.0 - flame_alpha);
	ALBEDO = (fire_color * flame_alpha + smoke_color * smoke * (1.0 - flame_alpha)) / max(ALPHA, 0.001);
}
