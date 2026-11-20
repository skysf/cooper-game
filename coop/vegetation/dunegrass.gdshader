shader_type spatial;
render_mode cull_disabled;

#include "res://vegetation/wind_field.gdshaderinc"
#include "res://vegetation/foliage_lod.gdshaderinc"

uniform sampler2D plant_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float surface_roughness = 0.84;
varying flat float fade;

void vertex() {
	vec2 root = MODEL_MATRIX[3].xz;
	fade = smoothstep(18.0, 25.0, distance(root, CAMERA_POSITION_WORLD.xz));
	float stem = smoothstep(0.017, 0.69, VERTEX.y);
	float blade = smoothstep(0.07, 0.43, length(VERTEX.xz));
	float shiver = sin(wind_time * 5.4 + dot(VERTEX.xz, vec2(14.2, -11.8)) + dot(root, vec2(2.9, 3.4)));
	vec2 flow = woodland_flow(root) * (1.0 - fade);
	vec2 displacement = flow * stem * (0.092 + blade * (0.038 + 0.015 * shiver));
	VERTEX.xz += woodland_local_xz(displacement, MODEL_MATRIX);
	if (fade >= 1.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (fade > 0.0 && foliage_lod_sample(FRAGCOORD.xy) < fade) {
		discard;
	}
	ALBEDO = texture(plant_color, UV).rgb * COLOR.rgb;
	ROUGHNESS = surface_roughness;
}
