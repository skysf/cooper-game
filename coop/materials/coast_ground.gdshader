shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D cliff_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D cliff_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D seaside_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D seaside_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D forest_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float sea_level = -0.075;
uniform vec4 carving_frame;
uniform float room_seconds;
uniform float rain_amount;
uniform float sunlight = 1.0;
uniform bool solid_stone = false;
varying vec3 world_at;
varying vec3 rock_at;
varying vec3 world_normal;
varying vec4 ground_mix;
varying float sandstone;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 offset = world_at.xz - carving_frame.xy;
	vec2 facing = carving_frame.zw;
	vec2 local = vec2(dot(offset, vec2(facing.y, -facing.x)), dot(offset, facing));
	sandstone = dot(facing, facing) * (1.0 - smoothstep(30.0, 65.0, abs(local.x)))
		* (1.0 - smoothstep(14.0, 38.0, abs(local.y)));
	// Shift the projection gradually along the wall to break up repeated tiles.
	rock_at = world_at + 0.56 * sin(world_at.zxy * vec3(0.29, 0.23, 0.31)
		+ world_at.yzx * vec3(0.16, 0.37, 0.22));
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	ground_mix = solid_stone ? vec4(0.0, 0.03, 0.0, 0.38) : COLOR;
}

void fragment() {
	vec3 point = world_at;
	vec3 n = normalize(world_normal);
	vec3 axes = abs(n);
	vec3 side = pow(axes, vec3(5.0));
	float shelf = 1.0;
	if (!solid_stone) {
		// The broad baked normal lights the wall smoothly, but can point
		// across the wrong axis on an individual steep heightfield facet.
		vec3 face = abs(normalize(cross(dFdx(point), dFdy(point))));
		float agreement = smoothstep(0.82, 0.97, dot(face, axes));
		side = pow(mix(face, axes, agreement), vec3(5.0));
		side *= smoothstep(vec3(0.08), vec3(0.34), face);
		// These deposits are projected from above. A near-vertical facet
		// cannot carry the sand weights of its adjacent shoal vertices.
		shelf = smoothstep(0.42, 0.83, face.y);
	}
	side /= max(dot(side, vec3(1.0)), 0.001);
	float sand_weight = ground_mix.r * shelf;
	vec3 p = rock_at;
	vec2 a = vec2(p.z + p.y * 0.22, p.y - p.z * 0.17) * 0.26;
	vec2 b = vec2(p.x + p.z * 0.21, p.z - p.x * 0.19) * 0.51 + vec2(0.43, 0.19);
	vec2 c = vec2(p.x - p.y * 0.24, p.y + p.x * 0.19) * 0.23 + vec2(0.27, 0.59);

	// The fractured scan covers steep faces. Gentler exposed ledges use the beach rock scan.
	vec3 cliff = texture(cliff_color, a).rgb * side.x + texture(cliff_color, c).rgb * side.z;
	vec3 stone = cliff * vec3(0.76, 0.85, 0.94) + texture(seaside_color, b).rgb * side.y;
	stone *= 0.79 + ground_mix.a * 0.40;
	float beds = sin(0.78 * point.y + 0.12 * point.z + 1.2 * sin(point.x * 0.16))
		+ 0.32 * sin(point.y * 2.3 + point.z * 0.19);
	stone *= mix(vec3(1.0), mix(vec3(0.92, 0.73, 0.65), vec3(1.13, 0.88, 0.73),
		smoothstep(-1.1, 1.1, beds)), sandstone);
	vec3 sand = texture(sand_color, point.xz * 0.69 + vec2(0.28, 0.20)).rgb;
	sand = mix(sand * vec3(1.04, 1.0, 0.91), vec3(0.83, 0.77, 0.63), 0.33);

	vec3 woodland = texture(forest_color, point.xz * 0.52).rgb;
	vec3 scrub = mix(woodland * vec3(0.67, 0.93, 0.58), vec3(0.19, 0.29, 0.116), 0.50);
	float sunward = 0.74 + ground_mix.a * 0.47;
	vec3 soil = mix(stone, sand, sand_weight);
	soil = mix(soil, scrub * sunward, ground_mix.g * (0.82 + ground_mix.a * 0.18));
	float approach = smoothstep(-54.0, -32.0, point.x);
	soil = mix(soil, woodland * (0.78 + ground_mix.a * 0.24), approach);
	vec3 grit = mix(stone, sand, 0.50 * shelf) * vec3(0.89, 0.83, 0.74);
	soil = mix(soil, grit, ground_mix.b * (0.56 - 0.28 * approach));

	vec2 normal_a = texture(cliff_normal, a).xy * 2.0 - 1.0;
	vec2 normal_b = mix(texture(seaside_normal, b).xy, texture(sand_normal, point.xz * 0.69).xy, sand_weight) * 2.0 - 1.0;
	vec2 normal_c = texture(cliff_normal, c).xy * 2.0 - 1.0;
	vec3 grain = vec3(0.0, normal_a.y, normal_a.x) * side.x
		+ vec3(normal_b.x, 0.0, -normal_b.y) * side.y + vec3(normal_c.x, normal_c.y, 0.0) * side.z;
	grain -= n * dot(n, grain);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + grain * 0.79), 0.0)).xyz);

	float depth = max(0.0, sea_level - point.y) * (1.0 - smoothstep(-78.0, -75.0, point.x));
	float soaked = (1.0 - smoothstep(0.0, 0.47, abs(point.y - sea_level))) * (1.0 - approach);
	ALBEDO = soil * (1.0 - soaked * 0.15 - rain_amount * 0.15);
	ROUGHNESS = clamp(0.92 - soaked * 0.24 - rain_amount * 0.24, 0.47, 1.0);
	SPECULAR = 0.31;
	if (depth > 0.0 && depth < 16.0) {
		vec2 flow = point.xz * 1.92 + vec2(room_seconds * 0.42, -room_seconds * 0.29);
		float first = sin(flow.x * 1.36 + sin(flow.y) * 1.7);
		float second = sin(flow.y * 1.14 - cos(flow.x * 0.71) * 1.9 + depth * 0.42);
		float light = smoothstep(0.73, 0.98, 1.0 - min(abs(first), abs(second)));
		float path = smoothstep(0.06, 0.78, depth) * exp(-depth * 0.21);
		EMISSION = soil * vec3(0.52, 0.84, 0.83) * light * path * sunlight * 0.21;
	}
}
