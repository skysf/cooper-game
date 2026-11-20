extends RefCounted

# Prevailing wind follows the existing low cloud drift (east, north-east).
static func sample(elapsed: float, rain: float) -> Vector4:
	var heading := -0.4115 + sin(elapsed * 0.052) * 0.24 + sin(elapsed * 0.143) * 0.12 - rain * 0.31
	var direction := Vector2.from_angle(heading)
	var pulse := 0.5 + 0.5 * sin(elapsed * 0.62 + sin(elapsed * 0.191) * 0.68)
	return Vector4(direction.x, direction.y, lerpf(0.32, 0.66, rain),
		pulse * pulse * lerpf(0.44, 1.28, rain))

# Match the spatial gust sampled by wind_field.gdshaderinc for local precipitation.
static func at_point(field: Vector4, elapsed: float, point: Vector2) -> Vector2:
	var heading := Vector2(field.x, field.y)
	var along := point.dot(heading)
	var across := point.dot(Vector2(-heading.y, heading.x))
	var passing := 0.5 + 0.5 * sin(elapsed * 0.79 - along * 0.23 + sin(across * 0.071) * 0.73)
	return heading * (field.z + field.w * (0.29 + passing * 0.71))
