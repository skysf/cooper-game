shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 pixel = (UV - vec2(0.5)) / SCREEN_PIXEL_SIZE;
	float radius = 0.445 / max(SCREEN_PIXEL_SIZE.x, SCREEN_PIXEL_SIZE.y);
	float edge = length(pixel) / radius;
	float outside = smoothstep(0.98, 1.005, edge);
	float rim = 0.55 * smoothstep(0.86, 0.985, edge);
	float x_axis = (1.0 - smoothstep(0.48, 1.28, abs(pixel.y))) * (1.0 - smoothstep(0.70, 0.76, abs(pixel.x) / radius));
	float y_axis = (1.0 - smoothstep(0.48, 1.28, abs(pixel.x))) * (1.0 - smoothstep(0.70, 0.76, abs(pixel.y) / radius));
	float center = 1.0 - smoothstep(1.4, 2.6, length(pixel));
	float line = max(max(x_axis, y_axis) * 0.88, center);
	vec3 ink = mix(vec3(0.012, 0.016, 0.014), vec3(0.94, 0.75, 0.48), center);
	COLOR = vec4(ink, strength * max(max(rim, outside), line));
}
