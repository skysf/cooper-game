shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D loam : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D loam_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camp_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camp_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camp_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mine_gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mine_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 portal_origin;
uniform float portal_sign = 1.0;
varying vec2 world_xz;
varying float world_height;
void vertex() { vec3 position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; world_xz = position.xz; world_height = position.y; }
uniform float wetness = 0.0;
void fragment() {
	vec2 uv = UV;
	float shade = smoothstep(.15,.63,texture(loam,uv*.05).g);
	vec3 leaf = mix(texture(loam,uv*1.07).rgb, texture(litter,uv*.93).rgb, .45+.34*shade);
	leaf *= mix(vec3(.79,.85,.67),vec3(.63,.77,.49),shade);
	vec3 stony = texture(gravel,uv*0.81).rgb;
	vec3 sandy = texture(sand,uv*0.69).rgb * vec3(.82,.79,.68);
	float arid = smoothstep(0.05,0.95,COLOR.r+(leaf.r-stony.g)*0.35);
	float trail = clamp(COLOR.g + COLOR.b*0.6,0.0,1.0);
	float macro = texture(gravel,uv*0.069+0.34).g;
	vec3 eastern = mix(mix(leaf,sandy,arid),stony,trail) * mix(.76,1.10,macro) * (1.0-wetness*.23);
	vec3 relief = mix(mix(mix(texture(loam_normal,uv*1.07).rgb,texture(litter_normal,uv*.93).rgb,.55),texture(sand_normal,uv*.69).rgb,arid),texture(gravel_normal,uv*.81).rgb,trail);
	float damp = COLOR.a;
	eastern = mix(eastern, mix(eastern,stony,.6)*vec3(.52,.50,.41),damp);
	relief = mix(relief,texture(gravel_normal,uv*.81).rgb,.50*damp);
	float verge = 3.0*sin(world_xz.y*.24)+2.4*sin(world_xz.y*.63+.4)+(macro-.42)*6.0;
	float blend = smoothstep(30.25,54.0,world_xz.x + verge*smoothstep(30.,40.,world_xz.x));
	vec2 legacy_uv=vec2(UV2.x,world_xz.y*.5);
	vec3 original = texture(camp_soil,legacy_uv).rgb*(206.0/255.0);
	vec3 arm = texture(camp_arm,legacy_uv).rgb;
	ALBEDO = mix(original,eastern,blend);
	NORMAL_MAP = mix(texture(camp_normal,legacy_uv).rgb,relief,blend);
	NORMAL_MAP_DEPTH = mix(.76,.78,blend);
	ROUGHNESS = mix(arm.g,mix(.94,.65,max(wetness,damp)),blend);
	SPECULAR = mix(.5,.2,blend);
	AO = mix(arm.r,1.0,blend);
	AO_LIGHT_AFFECT = .6;
	// Vertical projection preserves joints and grain on both faces of the roadcut.
	float x = world_xz.x;
	float depth = -45.0+(x-306.0)*.16+sin((x-289.0)*.16)-world_xz.y;
	if (x>280.0 && x<334.0 && depth>-.9 && depth<13.4) {
		float edges = smoothstep(280.,292.,x)*(1.-smoothstep(323.,334.,x));
		float rough_edge = (macro-.48)*1.4;
		float d = depth + rough_edge + .44*sin(x*1.05);
		float lower = smoothstep(-.8,.55,d)*(1.-smoothstep(2.6,4.4,d));
		float upper = smoothstep(6.65,7.9,d)*(1.-smoothstep(10.,12.6,d));
		float exposure = edges*max(lower,upper);
		vec2 face_uv = vec2(.193*x+.042*world_height,-.281*world_height+.019*x);
		vec3 stone = texture(mine_gravel,face_uv).rgb;
		vec3 wide = texture(mine_gravel,face_uv*.39+vec2(.37,.61)).rgb;
		stone = mix(stone,wide,.32);
		float grey = dot(stone,vec3(.30,.55,.15));
		stone = mix(vec3(grey),stone,.65)*vec3(.57,.57,.61)*(1.-wetness*.22);
		stone *= .94+.06*sin(world_height*2.7-x*.19+2.0*wide.r);
		ALBEDO=mix(ALBEDO,stone,exposure);
		NORMAL_MAP=mix(NORMAL_MAP,texture(mine_normal,face_uv*1.8).rgb,exposure*.74);
	}
	// Beyond the playable edge the relief carries rock exposure and scrub cover.
	if (UV2.y < 0.0) {
		float backcountry = min(-UV2.y,1.);
		vec2 strata_uv = mat2(vec2(.81,-.58),vec2(.58,.81))*uv*.19;
		vec3 granite = texture(mine_gravel,strata_uv).rgb*vec3(.67,.68,.67);
		vec3 scrub = mix(leaf, mix(sandy,stony,.38)*vec3(.76,.81,.75),arid);
		scrub *= mix(.53,1.03,COLOR.g);
		vec3 ridge = mix(scrub,granite,.19+.68*COLOR.b)*(1.-wetness*.24);
		ALBEDO = mix(ALBEDO,ridge,backcountry);
		NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH,.19,backcountry);
	}
	if (UV2.y > .001) {
		vec2 gallery_uv = (world_xz-portal_origin)*portal_sign*vec2(.61,-.61);
		ALBEDO = mix(ALBEDO,texture(mine_gravel,gallery_uv).rgb,UV2.y);
		NORMAL_MAP = mix(NORMAL_MAP,texture(mine_normal,gallery_uv).rgb,UV2.y);
		ROUGHNESS = mix(ROUGHNESS,.95,UV2.y);
	}
}
