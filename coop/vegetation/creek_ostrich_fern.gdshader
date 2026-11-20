shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://vegetation/wind_field.gdshaderinc"
#include "res://vegetation/foliage_lod.gdshaderinc"

uniform sampler2D fern_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool near_mesh = true;
uniform vec4 distances = vec4(8.0, 11.5, 22.0, 29.0);
uniform float rain = 0.0;

varying flat float near_fade;
varying flat float far_fade;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float range = distance(root, CAMERA_POSITION_WORLD);
	near_fade = smoothstep(distances.x, distances.y, range);
	far_fade = smoothstep(distances.z, distances.w, range);
	bool hidden = near_mesh ? near_fade >= 1.0 : near_fade <= 0.0 || far_fade >= 1.0;
	if (hidden) {
		VERTEX = vec3(0.0);
	} else {
		vec2 flow = woodland_flow(root.xz) * (1.0 - far_fade);
		float crown = smoothstep(0.043, 0.87, VERTEX.y);
		float reach = smoothstep(0.02, 0.56, length(VERTEX.xz));
		vec2 flex = flow * crown * (0.029 + reach * 0.030);
		VERTEX.xz += woodland_local_xz(flex, MODEL_MATRIX);
		// Geometry on both sides of a costa uses the same small vertical displacement.
		float sway = sin(wind_time * 4.1 + dot(root.xz, vec2(0.56, -0.85)) + VERTEX.y * 8.8);
		VERTEX.y += crown * reach * length(flow) * 0.0041 * sway;
	}
}

void fragment() {
	if (near_fade > 0.0 || far_fade > 0.0) {
		float sample_point = foliage_lod_sample(FRAGCOORD.xy);
		if (near_mesh ? sample_point < near_fade : sample_point >= near_fade || sample_point < far_fade) {
			discard;
		}
	}
	vec4 tissue = texture(fern_atlas, UV);
	if (tissue.a < (near_mesh ? 0.43 : 0.37)) {
		discard;
	}
	vec3 shade = tissue.rgb * COLOR.rgb;
	if (UV.y > 0.52) {
		if (!FRONT_FACING) {
			shade = shade * vec3(1.16, 1.11, 1.36) + vec3(0.008, 0.01, 0.015);
		}
		vec3 canopy = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, canopy, 0.25));
	}
	ALBEDO = shade * mix(1.0, 0.92, rain);
	ROUGHNESS = mix(0.88, 0.61, rain);
	SPECULAR = mix(0.19, 0.26, rain);
}
