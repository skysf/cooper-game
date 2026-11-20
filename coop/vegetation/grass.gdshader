shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://vegetation/wind_field.gdshaderinc"

uniform sampler2D grass_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wetness = 0.0;
varying flat vec2 variation;
varying float blade_height;

void vertex() {
	variation = INSTANCE_CUSTOM.rg;
	blade_height = VERTEX.y;
	vec2 root = MODEL_MATRIX[3].xz;
	float distance_to_viewer = distance(root, CAMERA_POSITION_WORLD.xz);
	float coverage = 1.0 - smoothstep(23.0, 31.0, distance_to_viewer);
	vec2 flow = woodland_flow(root);
	float flutter = sin(wind_time * 4.9 + dot(root, vec2(-0.86, 1.13)));
	float flex = clamp(VERTEX.y * 3.6, 0.0, 1.0);
	vec2 displacement = flow * (0.081 + flutter * 0.019) * flex * flex * coverage;
	VERTEX.xz += woodland_local_xz(displacement, MODEL_MATRIX);
	VERTEX.y = VERTEX.y * coverage - (1.0 - coverage) * 0.05;
}

void fragment() {
	vec2 atlas_uv = vec2(UV.x * 0.5 + variation.x * 0.5, UV.y);
	vec4 leaf = texture(grass_atlas, atlas_uv);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	float root_shade = mix(0.73, 1.0, smoothstep(0.0, 0.12, blade_height));
	ALBEDO = leaf.rgb * root_shade * mix(0.83, 1.06, variation.y) * mix(1.0, 0.82, wetness);
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up, 0.64));
	ROUGHNESS = mix(0.91, 0.68, wetness);
}
