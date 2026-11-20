shader_type spatial;
render_mode cull_disabled;

#include "res://vegetation/tree_wind.gdshaderinc"

uniform sampler2D tree_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform vec4 uv_mapping = vec4(1.0, 1.0, 0.0, 0.0);
uniform bool vertex_tint = true;
uniform float surface_roughness = 0.87;
uniform float leaf_cutoff = 0.36;
uniform float flutter_metres = 0.022;
uniform bool spray_tip_uv = true;

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	coast_mix = coast_transition ? coast_tree_fade(root, CAMERA_POSITION_WORLD.xz) : 0.0;
	vec2 flow = woodland_flow(root) * (1.0 - coast_mix);
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tip = spray_tip_uv ? 1.0 - UV.y : smoothstep(0.052, 0.31, length(VERTEX.xz) / source_tree_height);
	float flutter = sin(wind_time * 5.8 + dot(world_position.xz, vec2(3.24, -2.09)) + world_position.y * 1.37);
	float strength = length(flow) * tip * tip * flutter_metres;
	VERTEX.xz += tree_branch_bend(VERTEX, MODEL_MATRIX, flow)
		+ woodland_local_xz(vec2(-wind_field.y, wind_field.x) * flutter * strength, MODEL_MATRIX);
	VERTEX.y += flutter * strength * 0.40 / max(length(MODEL_MATRIX[1].xyz), 0.04);
	if (coast_mix >= 1.0 || !tree_branch_visible(COLOR.a)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (!tree_lod_visible(FRAGCOORD.xy)) {
		discard;
	}
	vec4 texel = texture(tree_color, UV * uv_mapping.xy + uv_mapping.zw) * surface_tint;
	ALBEDO = texel.rgb * (vertex_tint ? COLOR.rgb : vec3(1.0));
	ROUGHNESS = surface_roughness;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = leaf_cutoff;
}
