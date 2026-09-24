shader_type spatial;
render_mode cull_disabled;
uniform vec4 ink : source_color=vec4(.16,.4,1.,1.);
uniform float material_family=0.;
uniform float clock=0.;
uniform float amount=.1;
uniform float mode=0.;
uniform float mutation=0.;
uniform float band_mid=0.;
uniform sampler2D shape_profile : filter_linear, repeat_disable;
uniform float source_offset=0.;
uniform float neural_drive=0.;
varying vec3 local;
void vertex() {
	local=VERTEX;
	float wave=sin(VERTEX.y*4.+clock)*sin(VERTEX.x*3.-clock*.4);
	float address=fract(atan(VERTEX.z,VERTEX.x)/6.283185+.5+source_offset);
	vec2 neural_shape=texture(shape_profile,vec2(address,.5)).rg;
	VERTEX.xz*=.74+neural_shape.r*.45+neural_shape.g*.18+neural_drive*.17*wave;
	if(mode<.5) VERTEX+=NORMAL*wave*amount*.18;
	else if(mode<1.5) {
		float twist=VERTEX.y*amount*.9*sin(clock*.6);
		VERTEX.xz=mat2(vec2(cos(twist),-sin(twist)),vec2(sin(twist),cos(twist)))*VERTEX.xz;
	} else VERTEX+=NORMAL*sign(wave)*amount*.15;
	// Structural glitch is a local mesh operation, never a noise overlay.
	float slice=floor(VERTEX.y*7.);
	VERTEX.x+=sin(slice*2.1)*mutation*.20;
	VERTEX.z=mix(VERTEX.z,floor(VERTEX.z*12.)/12.,mutation);
}
void fragment() {
	vec3 color=ink.rgb;
	float stripe=step(.92,fract(local.y*7.+local.x*2.));
	if(material_family<.5) {
		ALBEDO=color; METALLIC=.10; ROUGHNESS=.52;
	} else if(material_family<1.5) {
		float reflection=.5+.5*sin(local.y*5.+local.x*2.+clock*.1);
		ALBEDO=mix(color*.12,vec3(.88,.93,1.),pow(reflection,5.));
		METALLIC=.62; ROUGHNESS=.19;
	} else {
		ALBEDO=mix(color*.18,color,stripe);
		METALLIC=.16; ROUGHNESS=.38;
		EMISSION=color*stripe*.35;
	}
	float rim=pow(1.-abs(dot(normalize(NORMAL),normalize(VIEW))),3.);
	EMISSION+=color*rim*(.12+neural_drive*.32);
}
