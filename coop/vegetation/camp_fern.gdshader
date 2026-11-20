shader_type spatial;
render_mode cull_disabled;

uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int cover_count = 0;
uniform vec4 cover_poses[12];
uniform vec2 cover_shapes[12];
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	for (int i = 0; i < cover_count; i++) {
		vec4 pose = cover_poses[i];
		vec2 shape = cover_shapes[i];
		vec3 offset = world_point - pose.xyz;
		float heading_sin = sin(pose.w);
		float heading_cos = cos(pose.w);
		vec2 local = vec2(offset.x * heading_cos - offset.z * heading_sin,
			offset.x * heading_sin + offset.z * heading_cos);
		float distance_to_center = shape.y > 0.5 ? length(local) : max(abs(local.x), abs(local.y));
		if (distance_to_center < shape.x && offset.y > -.47 && offset.y < .78) {
			discard;
		}
	}
	vec4 leaf = texture(foliage, UV);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ALBEDO = leaf.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
