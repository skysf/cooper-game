extends Node3D

const SKY_SHADER := preload("res://materials/camp_sky.gdshader")
const STAR_CATALOG := preload("res://textures/milky_way_stars.png")
const DAY_SECONDS := 420.0
const FIRST_SUNSET := 122.0
const LATITUDE := 0.75049158 # 43 degrees north
const SOLAR_LONGITUDE := 2.87341195 # Early September
const OBLIQUITY := 0.4090928
const GALACTIC_CENTER := Vector2(266.4051, -28.936175)
const GALACTIC_EAST := Vector2(318.0044, 48.32964)
const GALACTIC_NORTH := Vector2(192.85948, 27.12825)

const DAY_ZENITH := Color("#427db9")
const DAY_HORIZON := Color("#b1c5c9")
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
var sky_material := ShaderMaterial.new()

var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN
var sky_zenith := DAY_ZENITH
var sky_horizon := DAY_HORIZON
var sun_color := Color.WHITE
var moon_color := Color("#b4caff")
var cloud_cover := 0.2
var day_part := "day"
var sun_energy := 0.0
var moon_energy := 0.0

var _last_sky_time := -1.0
var _last_sky_rain := -1.0
var daylight_shadow_range := 38.0

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	_init_sky()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
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
	update_weather(Vector3.ZERO, 0.0, 0.0, 0.0, false)

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
	var dusk := 1.0 - smoothstep(1.5, 20.0, absf(solar_altitude + 0.8))
	var fair_clouds := 0.17 + (sin(elapsed * 0.019 + 0.6) + 1.0) * 0.085
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
	environment.ambient_light_color = Color("#bccfe3").lerp(Color("#849ab5"), night)
	environment.ambient_light_energy = lerpf(0.77, 0.23, night) * lerpf(1.0, 0.78, wet) * lerpf(0.82, 1.0, maxf(daylight, night))
	environment.fog_light_color = sky_horizon.lerp(Color("#ac9778"), dusk * (1.0 - wet) * 0.22).lerp(Color("#35495a"), night * 0.21)
	environment.fog_depth_begin = lerpf(20.0, 8.0, wet)
	environment.fog_depth_end = lerpf(103.0, 49.0, wet)

	sky_material.set_shader_parameter("sun_direction", sun_direction)
	sky_material.set_shader_parameter("moon_direction", moon_direction)
	sky_material.set_shader_parameter("sky_zenith", sky_zenith)
	sky_material.set_shader_parameter("sky_horizon", sky_horizon)
	sky_material.set_shader_parameter("sun_color", sun_color)
	sky_material.set_shader_parameter("star_visibility", (1.0 - smoothstep(-21.0, -6.0, solar_altitude)) * (1.0 - wet * 0.89))
	sky_material.set_shader_parameter("night_tint", night)
	sky_material.set_shader_parameter("sunset", dusk)
	sky_material.set_shader_parameter("cloud_cover", cloud_cover)
	sky_material.set_shader_parameter("rain_amount", wet)
	sky_material.set_shader_parameter("room_seconds", elapsed)
	sky_material.set_shader_parameter("galactic_center", _stars_axis(sidereal_angle, GALACTIC_CENTER))
	sky_material.set_shader_parameter("galactic_east", _stars_axis(sidereal_angle, GALACTIC_EAST))
	sky_material.set_shader_parameter("galactic_north", _stars_axis(sidereal_angle, GALACTIC_NORTH))

func _init_streaks() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;
uniform float fallen;
uniform float wet;
uniform bool repaired;
varying vec3 world_point;
void vertex() {
	vec3 s = INSTANCE_CUSTOM.xyz;
	float y = mod(s.y * 10.0 - fallen, 10.0) - 2.0;
	VERTEX += vec3((s.x-.5)*18.0 + VERTEX.y*.16, y, (s.z-.5)*18.0);
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if(repaired && abs(world_point.x-1.9)<2.6 && abs(world_point.z+89.6)<2.7 && world_point.y<2.7) discard;
	ALBEDO = vec3(.67, .77, .82);
	ALPHA = wet*.45;
}
"""
	streaks.shader = shader
	var quad := QuadMesh.new()
	quad.size = Vector2(.012, .20)
	quad.material = streaks
	var drops := MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	drops.use_custom_data = true
	drops.mesh = quad
	drops.instance_count = 960
	var rng := RandomNumberGenerator.new()
	rng.seed = 29121
	for i in drops.instance_count:
		drops.set_instance_transform(i, Transform3D.IDENTITY)
		drops.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 1))
	drops.custom_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 13, 20))
	rain.multimesh = drops
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

func update_weather(at: Vector3, yaw: float, elapsed: float, wet: float, repaired: bool) -> void:
	if absf(elapsed - _last_sky_time) >= 1.0 / 30.0 or absf(wet - _last_sky_rain) > 0.01:
		_last_sky_time = elapsed
		_last_sky_rain = wet
		_update_sky(elapsed, wet)
		streaks.set_shader_parameter("wet", wet)
	rain.visible = wet > .005
	rain.position = at
	rain.rotation.y = yaw
	streaks.set_shader_parameter("fallen", elapsed * 15.)
	streaks.set_shader_parameter("repaired", repaired)
