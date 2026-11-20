shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D ground_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ground_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_data : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float base_roughness = 0.85;
uniform float normal_depth = 0.76;
uniform float ao_light_affect = 0.6;
uniform bool stone = false;
// Retained moisture and current rain amount.
uniform vec2 moisture = vec2(0.0);
varying vec3 world_position;
varying float up_facing;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up_facing = (MODEL_NORMAL_MATRIX * NORMAL).y;
}

void fragment() {
	vec3 albedo = texture(ground_color, UV).rgb * COLOR.rgb;
	vec3 data = texture(surface_data, UV).rgb;
	float roughness = base_roughness * data.g;
	if (moisture.x > 0.001) {
		// Use the photographed recess signal at a second, world-space scale.
		// The large damp patches stay in place as the camera or chunk moves.
		vec2 patch_uv = vec2(world_position.x * 0.19 + world_position.z * 0.074,
			world_position.z * 0.17 - world_position.x * 0.104 + world_position.y * 0.18);
		vec2 patch = texture(surface_data, patch_uv + vec2(0.29, 0.59)).rg;
		float damp_recess = clamp(0.44 + (0.89 - patch.r) * 7.0 + (0.79 - patch.g) * 1.45, 0.0, 1.0);
		float pore = 1.0 - smoothstep(0.78, 0.93, data.r);
		float patch_weight = smoothstep(0.26, 0.81, damp_recess * 0.78 + pore * 0.22);
		float shelf = smoothstep(0.26, 0.96, up_facing);
		float absorption = moisture.x * (0.24 + patch_weight * 0.76) * mix(0.56, 1.0, shelf);
		vec3 wet_color = stone ? vec3(0.72, 0.76, 0.81) : vec3(0.65, 0.70, 0.75);
		albedo *= mix(vec3(1.0), wet_color, absorption);

		// A thin film softens the roughness in depressions without becoming a
		// mirror. Keep the photographed normal detail at full strength.
		float thin_film = moisture.y * patch_weight * shelf;
		float smoothing = moisture.x * (0.19 + patch_weight * 0.43) * mix(0.53, 1.0, shelf)
			+ thin_film * 0.13;
		roughness = mix(roughness, min(roughness, stone ? 0.33 : 0.29), smoothing);
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	AO = data.r;
	AO_LIGHT_AFFECT = ao_light_affect;
	NORMAL_MAP = texture(ground_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
