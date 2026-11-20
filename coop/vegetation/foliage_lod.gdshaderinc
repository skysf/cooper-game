float foliage_lod_sample(vec2 pixel) {
	return fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
}

float coast_tree_fade(vec2 root, vec2 eye) {
	return smoothstep(36.0, 43.0, distance(root, eye));
}
