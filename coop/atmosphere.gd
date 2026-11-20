extends Node3D

const WindField = preload("res://vegetation/wind_field.gd")
const RainShelter = preload("res://rain_shelter.gd")
const RAIN_SHADER = preload("res://materials/rain_streaks.gdshader")
const SKY_SHADER := preload("res://materials/camp_sky.gdshader")
const STAR_CATALOG := preload("res://textures/milky_way_stars.png")
const EVENING_SKY := preload("res://textures/evening_sky.jpg")
const DAY_SECONDS := 420.0
const FIRST_SUNSET := 122.0
const RAIN_FALL_SPEED := 15.0
const RAIN_PREVAILING_DRIFT := Vector2(2.6, -1.7)
const LATITUDE := 0.75049158 # 43 degrees north
const SOLAR_LONGITUDE := 2.87341195 # Early September
const OBLIQUITY := 0.4090928
const GALACTIC_CENTER := Vector2(266.4051, -28.936175)
const GALACTIC_EAST := Vector2(318.0044, 48.32964)
const GALACTIC_NORTH := Vector2(192.85948, 27.12825)

const DAY_ZENITH := Color("#427bb4")
const DAY_HORIZON := Color("#bbced8")
const DUSK_ZENITH := Color("#3b5682")
const DUSK_HORIZON := Color("#968986")
const NIGHT_ZENITH := Color("#080d1c")
const NIGHT_HORIZON := Color("#1d2a3d")
const STORM_ZENITH := Color("#444f5e")
const STORM_HORIZON := Color("#788789")

var environment := Environment.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var rain := MultiMeshInstance3D.new()
var streaks := ShaderMaterial.new()
var _rain_shelter := RainShelter.new()
var sky_material := ShaderMaterial.new()

var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN
var sky_zenith := DAY_ZENITH
var sky_horizon := DAY_HORIZON
var sun_color := Color.WHITE
var moon_color := Color("#b4caff")
var cloud_cover := 0.2
var twilight := 0.0
var evening_weight := 0.0
var underwater := false
var immersion := 0.0
var eye_depth := 0.0
var day_part := "day"
var sun_energy := 0.0
var moon_energy := 0.0

var _last_sky_time := -1.0
var _last_sky_rain := -1.0
var daylight_shadow_range := 38.0
var coastal_view := 0.0

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	_init_sky()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_sky_affect = 0.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if OS.has_feature("web"):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		daylight_shadow_range = 30.0
	# Keep the shadow pass configured across dawn, dusk and storms.
	sun.shadow_enabled = true
	sun.directional_shadow_fade_start = 0.78
	add_child(sun)
	add_child(moon)
	_init_streaks()
	update_weather(Vector3.ZERO, 0.0, 0.0, false)

func _init_sky() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 192739
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.024
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var cloud_texture := NoiseTexture2D.new()
	cloud_texture.width = 256
	cloud_texture.height = 256
	cloud_texture.seamless = true
	cloud_texture.seamless_blend_skirt = 0.27
	cloud_texture.noise = noise

	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", cloud_texture)
	sky_material.set_shader_parameter("star_catalog", STAR_CATALOG)
	sky_material.set_shader_parameter("evening_sky", EVENING_SKY)
	var galaxy_path := "res://textures/milky_way_photo.jpg"
	if ResourceLoader.exists(galaxy_path):
		sky_material.set_shader_parameter("milky_way_photo", load(galaxy_path))
		sky_material.set_shader_parameter("photographic_galaxy", true)
	var moon_path := "res://textures/lunar_surface.jpg"
	if ResourceLoader.exists(moon_path):
		sky_material.set_shader_parameter("lunar_surface", load(moon_path))
		sky_material.set_shader_parameter("photographic_moon", true)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY

func _equatorial(longitude: float, latitude: float) -> Vector2:
	var x := cos(latitude) * cos(longitude)
	var y := cos(latitude) * sin(longitude) * cos(OBLIQUITY) - sin(latitude) * sin(OBLIQUITY)
	var z := cos(latitude) * sin(longitude) * sin(OBLIQUITY) + sin(latitude) * cos(OBLIQUITY)
	return Vector2(atan2(y, x), asin(z))

func _horizontal(hour_angle: float, declination: float) -> Vector3:
	var sin_latitude := sin(LATITUDE)
	var cos_latitude := cos(LATITUDE)
	var on_equator := cos(declination) * cos(hour_angle)
	return Vector3(
		-cos(declination) * sin(hour_angle),
		sin_latitude * sin(declination) + cos_latitude * on_equator,
		-cos_latitude * sin(declination) + sin_latitude * on_equator,
	)

func _stars_axis(sidereal_angle: float, equatorial_degrees: Vector2) -> Vector3:
	return _horizontal(sidereal_angle - deg_to_rad(equatorial_degrees.x), deg_to_rad(equatorial_degrees.y))

func _update_sky(elapsed: float, wet: float) -> void:
	var days := elapsed / DAY_SECONDS
	var solar_coordinates := _equatorial(SOLAR_LONGITUDE, 0.0)
	var sunset_hour_angle := acos(-tan(LATITUDE) * tan(solar_coordinates.y))
	var solar_hour_angle := sunset_hour_angle + (elapsed - FIRST_SUNSET) * TAU / DAY_SECONDS
	var sidereal_angle := solar_hour_angle + solar_coordinates.x + days * deg_to_rad(0.986)
	sun_direction = _horizontal(solar_hour_angle, solar_coordinates.y)
	var moon_longitude := SOLAR_LONGITUDE + deg_to_rad(28.0) + days * TAU / 29.53
	var moon_latitude := sin(moon_longitude + 0.34) * deg_to_rad(4.9)
	var moon_coordinates := _equatorial(moon_longitude, moon_latitude)
	moon_direction = _horizontal(sidereal_angle - moon_coordinates.x, moon_coordinates.y)
	var solar_altitude := rad_to_deg(asin(sun_direction.y))
	var rising := sin(solar_hour_angle) < 0.0
	if solar_altitude > 7.0:
		day_part = "day"
	elif solar_altitude < -7.0:
		day_part = "night"
	else:
		day_part = "dawn" if rising else "dusk"

	var night := 1.0 - smoothstep(-18.0, -3.0, solar_altitude)
	var daylight := smoothstep(-11.0, 12.0, solar_altitude)
	twilight = smoothstep(-14.0, -1.0, solar_altitude) * (1.0 - smoothstep(2.0, 15.0, solar_altitude))
	twilight *= 1.0 - smoothstep(0.04, 0.64, wet)
	evening_weight = 0.82 * twilight if not rising else 0.0
	var fair_clouds := 0.24 + (sin(elapsed * 0.019 + 0.6) + 1.0) * 0.10
	cloud_cover = lerpf(fair_clouds, 0.97, sqrt(wet))
	var overcast := wet * (1.0 - night * 0.87)
	sky_zenith = DUSK_ZENITH.lerp(DAY_ZENITH, daylight).lerp(NIGHT_ZENITH, night).lerp(STORM_ZENITH, overcast * 0.88)
	sky_horizon = DUSK_HORIZON.lerp(DAY_HORIZON, daylight).lerp(NIGHT_HORIZON, night).lerp(STORM_HORIZON, overcast * 0.86)
	sun_color = Color("#ffa76c").lerp(Color("#fff1d7"), smoothstep(-2.0, 38.0, solar_altitude)).lerp(Color("#bccde1"), wet * 0.66)
	var sunlight := smoothstep(-1.0, 13.0, solar_altitude)
	var last_sunlight := smoothstep(-1.1, 2.8, solar_altitude) * 0.50
	sun_energy = maxf(sunlight, last_sunlight) * lerpf(1.08, 0.16, wet)
	var lunar_phase := (1.0 - sun_direction.dot(moon_direction)) * 0.5
	moon_energy = pow(lunar_phase, 1.4) * smoothstep(-0.02, 0.25, moon_direction.y) * night * (1.0 - wet * 0.85) * 0.23

	sun.look_at(-sun_direction, Vector3.UP)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_opacity = smoothstep(0.02, 0.48, sun_energy) * (1.0 - smoothstep(0.55, 0.82, wet))
	sun.directional_shadow_max_distance = lerpf(4.0, daylight_shadow_range, sun.shadow_opacity)
	moon.look_at(-moon_direction, Vector3.UP)
	moon.light_color = moon_color
	moon.light_energy = moon_energy
	var ambient_color := Color("#bccfe3").lerp(Color("#efc39c"), twilight * 0.42)
	environment.ambient_light_color = ambient_color.lerp(Color("#849ab5"), night)
	environment.ambient_light_energy = lerpf(0.77, 0.23, night) * lerpf(1.0, 0.78, wet) * lerpf(0.82, 1.0, maxf(daylight, night))
	var valley_haze := sky_horizon.lerp(Color("#d2ac87"), twilight * 0.31).lerp(Color("#35495a"), night * 0.21)
	var sea_haze := valley_haze.lerp(sky_zenith, 0.22).darkened(0.12)
	# Let haze separate the distant headlands while retaining the contrast of rock and trees.
	var sea_density := lerpf(0.34, 0.62, wet)
	environment.fog_density = lerpf(1.0, sea_density, coastal_view * (1.0 - immersion))
	environment.fog_light_color = valley_haze.lerp(sea_haze, coastal_view)
	environment.fog_depth_begin = lerpf(lerpf(20.0, 8.0, wet), lerpf(58.0, 20.0, wet), coastal_view)
	environment.fog_depth_end = lerpf(lerpf(103.0, 49.0, wet), lerpf(248.0, 169.0, wet), coastal_view)
	environment.fog_sky_affect = immersion * 0.91
	if immersion > 0.0:
		var depth_weight := smoothstep(0.10, 1.85, eye_depth)
		var scatter := Color("#639185").lerp(Color("#345f5a"), depth_weight)
		scatter = scatter.lerp(Color("#60a8ad").lerp(Color("#235c78"), depth_weight), coastal_view)
		scatter = scatter.lerp(Color("#415f60"), wet * 0.63).lerp(Color("#102932"), night)
		scatter = scatter.lerp(Color("#67786a"), twilight * 0.27)
		environment.fog_light_color = environment.fog_light_color.lerp(scatter, immersion)
		environment.fog_depth_begin = lerpf(environment.fog_depth_begin, 0.20, immersion)
		var visibility := lerpf(15.2, 10.5, depth_weight) + coastal_view * 11.0 - wet * 2.0 - night * 3.8
		environment.fog_depth_end = 1.0 / lerpf(1.0 / environment.fog_depth_end, 1.0 / visibility, immersion)
		environment.ambient_light_color = environment.ambient_light_color.lerp(Color("#83b4a3"), immersion * 0.58)
		environment.ambient_light_energy *= 1.0 - immersion * lerpf(0.16, 0.37, depth_weight)

	sky_material.set_shader_parameter("sun_direction", sun_direction)
	sky_material.set_shader_parameter("moon_direction", moon_direction)
	sky_material.set_shader_parameter("sky_zenith", sky_zenith)
	sky_material.set_shader_parameter("sky_horizon", sky_horizon)
	sky_material.set_shader_parameter("sun_color", sun_color)
	sky_material.set_shader_parameter("star_visibility", (1.0 - smoothstep(-21.0, -6.0, solar_altitude)) * (1.0 - wet * 0.89))
	sky_material.set_shader_parameter("night_tint", night)
	sky_material.set_shader_parameter("twilight", twilight)
	sky_material.set_shader_parameter("evening_weight", evening_weight)
	sky_material.set_shader_parameter("cloud_cover", cloud_cover)
	sky_material.set_shader_parameter("rain_amount", wet)
	sky_material.set_shader_parameter("room_seconds", elapsed)
	sky_material.set_shader_parameter("galactic_center", _stars_axis(sidereal_angle, GALACTIC_CENTER))
	sky_material.set_shader_parameter("galactic_east", _stars_axis(sidereal_angle, GALACTIC_EAST))
	sky_material.set_shader_parameter("galactic_north", _stars_axis(sidereal_angle, GALACTIC_NORTH))

func _init_streaks() -> void:
	streaks.shader = RAIN_SHADER
	var quad := QuadMesh.new()
	quad.material = streaks
	var drops := MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	drops.use_custom_data = true
	drops.mesh = quad
	drops.instance_count = 1280
	var rng := RandomNumberGenerator.new()
	rng.seed = 29121
	for i in drops.instance_count:
		drops.set_instance_transform(i, Transform3D.IDENTITY)
		drops.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 1))
	drops.custom_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 13, 20))
	rain.multimesh = drops
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

func set_rain_roofs(records: Dictionary) -> void:
	_rain_shelter.set_roofs(records)

func update_weather(at: Vector3, elapsed: float, wet: float, repaired: bool,
		below_water := false, camera_water_depth := NAN, sea_view := 0.0) -> void:
	# Older callers supply just whether the eye is submerged. A real camera can
	# cross the waterline continuously, including in third person or from the ship.
	var depth := camera_water_depth if not is_nan(camera_water_depth) else (1.0 if below_water else -1.0)
	var blend := smoothstep(-0.045, 0.17, depth)
	if (absf(elapsed - _last_sky_time) >= 1.0 / 30.0 or absf(wet - _last_sky_rain) > 0.01
			or below_water != underwater or absf(immersion - blend) > 0.012 or absf(coastal_view - sea_view) > 0.008):
		underwater = below_water
		immersion = blend
		coastal_view = sea_view
		eye_depth = maxf(depth, 0.0)
		_last_sky_time = elapsed
		_last_sky_rain = wet
		_update_sky(elapsed, wet)
		streaks.set_shader_parameter("wet", wet)
		streaks.set_shader_parameter("light_level", clampf(environment.ambient_light_energy / 0.5, 0.28, 1.0))
	rain.visible = wet > .005 and not underwater
	if rain.visible:
		rain.global_position = at
		streaks.set_shader_parameter("wind_time", elapsed)
		streaks.set_shader_parameter("wind_field", WindField.sample(elapsed, wet))
		streaks.set_shader_parameter("fallen", fposmod(elapsed * RAIN_FALL_SPEED, 10.0))
		streaks.set_shader_parameter("rain_drift", Vector2(fposmod(elapsed * RAIN_PREVAILING_DRIFT.x, 18.0),
			fposmod(elapsed * RAIN_PREVAILING_DRIFT.y, 18.0)))
		_rain_shelter.apply(at, repaired, streaks)
