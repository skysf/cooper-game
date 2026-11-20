shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

#include "res://vegetation/foliage_lod.gdshaderinc"

uniform bool coast_transition = false;
varying flat float coast_mix;

uniform sampler2D canopy_atlas : source_color, filter_linear_mipmap, repeat_disable;
varying vec2 atlas_uv;
varying vec3 crown_normal;
varying float tint;
varying float crown_light;

void vertex() {
	coast_mix = coast_transition ? coast_tree_fade(MODEL_MATRIX[3].xz, CAMERA_POSITION_WORLD.xz) : 1.0;
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 front = cross(right, up);
	mat4 card = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0), vec4(front, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * card;
	vec2 cell_uv = vec2(mix(UV.x, 1.0 - UV.x, INSTANCE_CUSTOM.a), UV.y);
	atlas_uv = (INSTANCE_CUSTOM.rg + cell_uv) * 0.5;
	crown_normal = mat3(VIEW_MATRIX) * normalize(up * 0.82 + front * 0.48 + right * (UV.x - 0.5) * 1.30);
	tint = INSTANCE_CUSTOM.b;
	crown_light = 0.74 + 0.26 * (1.0 - UV.y);
	if (coast_mix <= 0.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (coast_transition && coast_mix < 1.0 && foliage_lod_sample(FRAGCOORD.xy) >= coast_mix) {
		discard;
	}
	vec4 foliage = texture(canopy_atlas, atlas_uv);
	ALBEDO = foliage.rgb * tint * crown_light * vec3(0.87, 0.91, 0.86);
	NORMAL = normalize(crown_normal);
	ROUGHNESS = 1.0;
	ALPHA = foliage.a;
	ALPHA_SCISSOR_THRESHOLD = 0.23;
}
