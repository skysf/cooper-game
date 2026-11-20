shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, world_vertex_coords;

#include "res://vegetation/wind_field.gdshaderinc"

uniform float fallen;
uniform vec2 rain_drift;
uniform float wet;
uniform float light_level = 1.0;
uniform int shelter_rows = 0;
uniform sampler2D shelter_boxes : filter_nearest, repeat_disable;
varying float drop_visibility;

float clipped_length(vec3 foot, vec3 upstream, float drop_length) {
	vec2 projected = foot.xz - upstream.xz * foot.y;
	float cut = 0.0;
	for (int row = 0; row < shelter_rows; row++) {
		vec4 box = texelFetch(shelter_boxes, ivec2(0, row), 0);
		vec2 offset = projected - (box.xz - upstream.xz * box.y);
		if (dot(offset, offset) > box.w * box.w) {
			continue;
		}
		vec4 a = texelFetch(shelter_boxes, ivec2(1, row), 0);
		vec4 b = texelFetch(shelter_boxes, ivec2(2, row), 0);
		vec4 c = texelFetch(shelter_boxes, ivec2(3, row), 0);
		vec3 extent = vec3(a.w, b.w, c.w);
		vec3 relative = foot - box.xyz;
		vec3 start = vec3(dot(relative, a.xyz), dot(relative, b.xyz), dot(relative, c.xyz));
		vec3 ray = vec3(dot(upstream, a.xyz), dot(upstream, b.xyz), dot(upstream, c.xyz));
		bvec3 parallel = lessThan(abs(ray), vec3(0.00001));
		if (any(bvec3(parallel.x && abs(start.x) > extent.x,
				parallel.y && abs(start.y) > extent.y, parallel.z && abs(start.z) > extent.z))) {
			continue;
		}
		vec3 reciprocal = mix(vec3(-1.0), vec3(1.0), greaterThanEqual(ray, vec3(0.0))) / max(abs(ray), vec3(0.00001));
		vec3 low = (-extent - start) * reciprocal;
		vec3 high = (extent - start) * reciprocal;
		vec3 near = mix(min(low, high), vec3(-100000.0), parallel);
		vec3 far = mix(max(low, high), vec3(100000.0), parallel);
		float enter = max(0.0, max(near.x, max(near.y, near.z)));
		float leave = min(far.x, min(far.y, far.z));
		if (leave >= enter) {
			cut = max(cut, leave + 0.002);
			if (cut >= drop_length) {
				return drop_length;
			}
		}
	}
	return cut;
}

void vertex() {
	vec3 seed = INSTANCE_CUSTOM.xyz;
	vec3 focus = MODEL_MATRIX[3].xyz;
	// Recycle distant drops at the edge of the volume. The positions inside
	// the volume are sampled in world coordinates, independent of the camera.
	float y = mod(seed.y * 10.0 - fallen - focus.y + 2.0, 10.0) - 2.0;
	vec2 base = mod(seed.xz * 18.0 + rain_drift - focus.xz + 9.0, 18.0) - 9.0;
	vec3 center = focus + vec3(base.x, y, base.y);
	vec2 rain_slope = woodland_flow(center.xz) * 0.21;
	center.xz += rain_slope * 1.8;
	vec3 direction = vec3(-rain_slope.x, 1.0, -rain_slope.y);
	float size = fract(dot(seed, vec3(11.73, 16.33, 24.61)));
	float drop_length = mix(0.10, 0.21, size);
	float half_drop = drop_length * 0.5;
	vec3 from_eye = center - CAMERA_POSITION_WORLD;
	drop_visibility = smoothstep(0.55, 1.85, length(from_eye));
	drop_visibility *= 1.0 - smoothstep(5.8, 8.2, length(from_eye.xz));
	drop_visibility *= smoothstep(-1.9, -1.1, from_eye.y) * (1.0 - smoothstep(6.6, 8.0, from_eye.y));
	drop_visibility *= smoothstep(size * 0.76, size * 0.76 + 0.24, wet);
	float lift = 0.0;
	// Streaks entirely behind the eye need no shelter intersection tests.
	if (shelter_rows > 0 && drop_visibility > 0.001 && dot(from_eye, INV_VIEW_MATRIX[2].xyz) < 0.22) {
		lift = clipped_length(center - direction * half_drop, direction, drop_length);
	}
	if (lift >= drop_length || drop_visibility <= 0.001) {
		VERTEX = center;
	} else {
		float height = mix(half_drop, lift - half_drop, UV.y);
		vec2 right = normalize(INV_VIEW_MATRIX[0].xz);
		float width = (UV.x - 0.5) * mix(0.006, 0.014, size);
		VERTEX = center + direction * height + vec3(right.x, 0.0, right.y) * width;
	}
}

void fragment() {
	ALBEDO = vec3(0.67, 0.77, 0.82);
	float radius = mix(0.16, 0.5, smoothstep(0.04, 0.72, UV.y));
	float side = 1.0 - smoothstep(radius * 0.35, radius, abs(UV.x - 0.5));
	float ends = smoothstep(0.0, 0.46, UV.y) * (1.0 - smoothstep(0.84, 1.0, UV.y));
	ALPHA = wet * light_level * 0.51 * drop_visibility * side * ends;
}
