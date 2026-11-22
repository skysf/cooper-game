shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
#include "res://materials/water_rain.gdshaderinc"

uniform sampler2D ripple : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 sky_horizon : source_color;
uniform vec4 sky_zenith : source_color;
uniform vec3 sun_direction;
uniform vec4 sun_color : source_color;
uniform float cloud_cover;
uniform float water_time;
uniform float rain;
varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = COLOR.r * 0.5;
	float shore = smoothstep(0.0, 0.065, depth);
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_at);
	vec2 p = world_at.xz;
	vec2 drift = texture(ripple, p * 0.12 + water_time * vec2(0.006,-0.004)).rg - 0.5;
	vec2 a = texture(ripple, p * 0.59 + drift * 0.22 + water_time * vec2(0.029,-0.014)).rg - 0.5;
	vec2 b = texture(ripple, p.yx * 0.84 - water_time * vec2(0.017,0.026)).rg - 0.5;
	vec2 slope = (a * 0.36 + b.yx * 0.18) * shore;
	float radius = length(UV - vec2(0.9,0.55));
	float pulse = radius * 22.0 - water_time * 4.2;
	slope += normalize(UV - vec2(0.9,0.55) + vec2(0.0001)) * cos(pulse) * exp(-radius * 1.65) * 0.065 * shore;
	slope += water_rain_ripples(p, drift, distance(CAMERA_POSITION_WORLD,world_at), water_time, rain, 1.0);
	vec3 normal = normalize(vec3(slope.x,1.0,slope.y));
	vec3 reflected = reflect(-to_eye,normal);
	vec3 sky = mix(sky_horizon.rgb, sky_zenith.rgb, sqrt(clamp(reflected.y,0.0,1.0)));
	float facing = clamp(dot(normal,to_eye),0.0,1.0);
	float reflection = 0.10 + 0.75 * pow(1.0-facing,3.6);
	float daylight = clamp(max(sky_horizon.g,sky_zenith.b)*1.5,0.06,1.0);
	vec3 water = mix(vec3(0.13,0.23,0.18),vec3(0.075,0.22,0.22),smoothstep(0.04,0.39,depth)) * daylight;
	float scatter = (1.0-reflection) * (1.0-exp(-depth*1.75/max(0.26,facing)));
	float highlight = pow(max(0.0,dot(normal,normalize(to_eye+sun_direction))),155.0) * smoothstep(-0.01,0.065,sun_direction.y) * (1.0-cloud_cover*0.91);
	float opacity = min(0.94,reflection+scatter+highlight*0.18);
	ALBEDO = (sky*reflection+water*scatter+sun_color.rgb*highlight*0.80)/max(opacity,0.001);
	ALPHA = shore*opacity;
}
