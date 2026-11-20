shader_type spatial;

#include "res://vegetation/tree_wind.gdshaderinc"

uniform sampler2D tree_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform vec4 uv_mapping = vec4(1.0, 1.0, 0.0, 0.0);
uniform bool vertex_tint = true;
uniform float surface_roughness = 0.93;
uniform bool has_normal_texture = false;
uniform sampler2D tree_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
uniform bool has_roughness_texture = false;
uniform sampler2D tree_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	coast_mix = coast_transition ? coast_tree_fade(root, CAMERA_POSITION_WORLD.xz) : 0.0;
	vec2 flow = woodland_flow(root) * (1.0 - coast_mix);
	VERTEX.xz += tree_branch_bend(VERTEX, MODEL_MATRIX, flow);
	if (coast_mix >= 1.0 || !tree_branch_visible(COLOR.a)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (!tree_lod_visible(FRAGCOORD.xy)) {
		discard;
	}
	vec2 uv = UV * uv_mapping.xy + uv_mapping.zw;
	ALBEDO = texture(tree_color, uv).rgb * surface_tint.rgb * (vertex_tint ? COLOR.rgb : vec3(1.0));
	ROUGHNESS = surface_roughness;
	if (has_roughness_texture) {
		ROUGHNESS *= dot(texture(tree_roughness, uv), roughness_channel);
	}
	if (has_normal_texture) {
		NORMAL_MAP = texture(tree_normal, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
