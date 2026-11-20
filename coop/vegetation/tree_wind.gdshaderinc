#include "res://vegetation/wind_field.gdshaderinc"
#include "res://vegetation/foliage_lod.gdshaderinc"

uniform float source_tree_height = 7.0;
uniform float branch_flexibility = 1.0;
uniform bool coast_transition = false;
uniform bool branch_lod = false;
uniform vec2 lod_clip = vec2(0.0, 1.0);
varying flat float coast_mix;

vec2 tree_branch_bend(vec3 vertex, mat4 model, vec2 flow) {
	float relative_height = clamp(vertex.y / source_tree_height, 0.0, 1.0);
	float height_weight = smoothstep(0.13, 0.89, relative_height);
	float branch_weight = smoothstep(0.025, 0.28, length(vertex.xz) / source_tree_height);
	float stature = clamp(length(model[1].xyz) * source_tree_height / 4.7, 0.14, 1.0);
	return woodland_local_xz(flow * height_weight * stature * (0.016 + branch_weight * 0.082)
		* branch_flexibility, model);
}

bool tree_branch_visible(float branch_rank) {
	return !branch_lod || (branch_rank >= lod_clip.x && branch_rank < lod_clip.y);
}

bool tree_lod_visible(vec2 pixel) {
	if (branch_lod) {
		return true;
	}
	float low = max(lod_clip.x, coast_mix);
	if (low <= 0.0 && lod_clip.y >= 1.0) {
		return true;
	}
	float sample = foliage_lod_sample(pixel);
	return sample >= low && sample < lod_clip.y;
}
