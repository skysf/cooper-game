shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://vegetation/wind_field.gdshaderinc"
#include "res://vegetation/foliage_lod.gdshaderinc"

uniform sampler2D plant_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool shrub = false;
uniform float rain = 0.0;
uniform float waterline = -0.075;
varying flat float fade;
varying float wetness;

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	fade = smoothstep(21.0, 30.0, distance(root, CAMERA_POSITION_WORLD.xz));
	float height = smoothstep(0.05, 1.47, VERTEX.y);
	float outside = smoothstep(0.12, 0.63, length(VERTEX.xz));
	vec2 flow = woodland_flow(root) * (1.0 - fade);
	float flex = shrub ? height * (0.020 + 0.070 * outside) : height * height * 0.17;
	VERTEX.xz += woodland_local_xz(flow * flex, MODEL_MATRIX);
	if (shrub && UV.x < 0.53) {
		float tip = (1.0 - UV.y) * (1.0 - UV.y);
		float flutter = sin(wind_time * 5.2 + dot(VERTEX.xz, vec2(16.4, -9.9)) + VERTEX.y * 8.9);
		VERTEX.y += tip * flutter * length(flow) * 0.008;
	}
	float world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	wetness = max(rain, shrub ? 0.0 : 1.0 - smoothstep(waterline - 0.10, waterline + 0.11, world_height));
	if (fade >= 1.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fade > 0.0 && foliage_lod_sample(FRAGCOORD.xy) < fade) {
		discard;
	}
	ALBEDO = texture(plant_color, UV).rgb * COLOR.rgb * (1.0 - wetness * 0.09);
	ROUGHNESS = mix(0.87, 0.54, wetness);
}
