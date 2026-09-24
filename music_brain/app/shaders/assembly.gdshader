shader_type spatial;
render_mode unshaded, cull_disabled, alpha_to_coverage;
#include "res://shaders/design_palette.gdshaderinc"
#include "res://shaders/graphic_language.gdshaderinc"
uniform sampler2D trajectory : filter_linear, repeat_disable;
uniform sampler2D populations : filter_nearest, repeat_disable;
uniform sampler2D cell_states : filter_nearest, repeat_disable;
uniform sampler2D cell_lookup : filter_nearest, repeat_disable;
uniform sampler2D memory_view : source_color, filter_linear, repeat_disable;
uniform float cells_ready=0.;
uniform float between_frames=0.;
uniform float memory_valid=0.;
uniform float shape_kind=0.;
uniform float family=0.;
uniform float development=0.;
uniform float articulation=0.;
uniform float mutation=0.;
uniform float palette=0.;
uniform float polarity=0.;
uniform float turnover=0.;
uniform float fold=0.;
uniform float contour_mode=0.;
uniform float silhouette=.5;
uniform float section_count=5.;
uniform float graphic_mode=0.;
uniform float material_shift=0.;
uniform float material_response=0.;
uniform float deformation_response=0.;
uniform float aperture_action=0.;
uniform float destruction=0.;
// Instance identity is categorical, not a surface gradient. Interpolation can
// turn a role of 1.0 into 0.999999 at individual fragments; floor() then selects
// the wrong voice and creates dense, apparently random material speckling.
varying flat vec4 identity;
varying flat float neural;
varying float surface_face;
varying vec3 surface_normal;
float smooth_profile(float u,float v) {
	float x=clamp(u,0.,1.)*15.;
	float a=floor(x),t=fract(x); t=t*t*(3.-2.*t);
	return mix(texture(trajectory,vec2((a+.5)/16.,v)).r,
		texture(trajectory,vec2((min(a+1.,15.)+.5)/16.,v)).r,t);
}
float cell_spike(vec2 grid,float owner) {
	vec2 at=clamp(grid,vec2(0.),vec2(7.,3.));
	float index=at.x+at.y*8.;
	vec4 lookup=texture(cell_lookup,vec2((index+.5)/32.,(owner+.5)/256.));
	vec4 packed=texture(cell_states,lookup.rg)*255.;
	float age=packed.a*.002+between_frames;
	return lookup.b*step(packed.a,254.)*exp(-age/.060);
}
float local_spike(vec2 uv,float owner) {
	if(cells_ready<.5) return 0.;
	vec2 p=clamp(uv,vec2(0.),vec2(1.))*vec2(7.,3.);
	vec2 a=floor(p),f=smoothstep(vec2(0.),vec2(1.),fract(p));
	return mix(mix(cell_spike(a,owner),cell_spike(a+vec2(1.,0.),owner),f.x),mix(cell_spike(a+vec2(0.,1.),owner),cell_spike(a+vec2(1.),owner),f.x),f.y);
}
vec3 deform(vec2 uv,vec4 id,float burst) {
	float u=uv.x,v=uv.y;
	vec4 bass_voice=musical_voice(1.),lead_voice=musical_voice(4.);
	vec4 impact_voice=musical_voice(0.),detail_voice=musical_voice(3.);
	vec4 snare_voice=musical_voice(2.),bed_voice=musical_voice(5.);
	float role=floor(id.w);
	// Impact is a shared structural pulse. Gating it to role 0 left most
	// visible sheets almost static while the actual impact voice was active.
	impact_voice*=.82; bass_voice*=1.-step(.5,abs(role-1.));
	snare_voice*=1.-step(.5,abs(role-2.)); detail_voice*=1.-step(.5,abs(role-3.));
	lead_voice*=1.-step(.5,abs(role-4.)); bed_voice*=1.-step(.5,abs(role-5.));
	// Closed domains must have matching vertices at u=0/1. A wrapped lookup
	// with clamped texture edges previously tore the silhouette at its seam.
	bool periodic=shape_kind>3.5 || (shape_kind>.5 && shape_kind<1.5);
	float lookup_u=periodic?.5+.43*cos(u*6.283185+id.w):clamp(u*.8+.1,0.,1.);
	float profile=smooth_profile(lookup_u,.16+development*.67);
	if(periodic) {
		// Reflective sculptures need a smooth curvature field. The unsmoothed
		// 16-bin history created tiny repeated dents amplified by the highlights.
		// Retain the same neural trajectory with a local, normalized low-pass.
		float row=.16+development*.67;
		profile=profile*.375+(smooth_profile(lookup_u-.09,row)+smooth_profile(lookup_u+.09,row))*.25
			+(smooth_profile(lookup_u-.18,row)+smooth_profile(lookup_u+.18,row))*.0625;
	}
	float hinge=clamp(fold*(.3+id.z*.6)+articulation*burst*.25,0.,1.1);
	float closed_response=shape_kind>3.5?.42:1.;
	vec3 p=vec3(u*2.-1.,(v*2.-1.)*.94,0.);
	if(shape_kind<.5 || (shape_kind>2.5 && shape_kind<3.5)) {
		p.x*=.94;
		p.z=sin(u*6.283185+id.w)*hinge*(v-.5)*.5+abs(u-.5)*hinge*.4;
		// A sheet has a smooth silhouette. Fine profile changes belong inside
		// it: varying horizontal scale per column could fold the UV domain back.
		p.y+=sin(u*3.14159)*.025*(smooth_profile(.3,.5)-smooth_profile(.7,.5));
		if(family==8. || family==11.) p.z*=.2;
		if(family==11.) {
			float a=u*6.283185;
			vec2 q=vec2(cos(a),sin(a));
			// Radial superellipse: sign(q)*pow(abs(q),.24) amplified the
			// floating-point sin(2*pi) residue into a visible seam/wedge.
			float norm=pow(pow(abs(q.x),8.)+pow(abs(q.y),8.),.125);
			p.xy=q/max(norm,.001)*(.68+v*.26);
			p.z=sin(a*2.+id.w)*hinge*.025;
		} else if(family==5.) {
			vec2 q=vec2(u,v)*2.-1.;
			p.xy=q*sqrt(max(vec2(.001),1.-q.yx*q.yx*.5))*.94;
		} else if(family==9.) {
			p.x*=.85+.08*cos(v*6.283185+id.z*7.);
		}
	} else if(shape_kind<1.5) {
		// A closed tube, including its back. An extruded flat annulus collapsed
		// to a razor edge at oblique angles and amplified the wrong normals.
		float a=u*6.283185+id.w*.08;
		float tube=v*6.283185;
		float radius=.090+profile*.015;
		float radial=.57+cos(tube)*radius;
		p=vec3(cos(a)*radial,sin(a)*radial,sin(tube)*radius);
		p.z+=sin(a*2.+id.w)*hinge*.020;
	} else if(shape_kind>3.5) {
		float a=u*6.283185,b=v*3.14159;
		float morphology=mod(floor(contour_mode+id.z*3.),4.);
		if(morphology<.5) {
			// Rounded extrusion: the profile controls its cross-section.
			vec3 q=vec3(cos(a)*sin(b),cos(b),sin(a)*sin(b));
			float exponent=2.5+silhouette*3.;
			float norm=pow(pow(abs(q.x),exponent)+pow(abs(q.y),exponent)+pow(abs(q.z),exponent),1./exponent);
			p=q/max(norm,.001)*.72;
			p.xz*=.92+profile*.07;
		} else if(morphology<1.5) {
			float tube=v*6.283185;
			// A torus is a graphic object first and a neural surface second. Keep
			// the tube round and let the song move it through scale/rotation rather
			// than making the silhouette buckle into random reflective blobs.
			float minor_radius=.108+profile*.018;
			float ring=.54+minor_radius*cos(tube);
			p=vec3(cos(a)*ring,sin(a)*ring,sin(tube)*minor_radius);
			p.z+=sin(a*2.)*silhouette*.025;
		} else if(morphology<2.5) {
			// A folded shell with an open centre, not another opaque sphere.
			float tube=v*6.283185;
			float ring=.53+.14*cos(tube+a*2.);
			p=vec3(cos(a)*ring,sin(a)*ring,sin(tube+a*2.)*(.10+profile*.07));
		} else {
			float r=.53+.065*cos(a*section_count)+profile*.045;
			p=vec3(cos(a)*sin(b)*r,cos(b)*.86,sin(a)*sin(b)*r);
			float turn=cos(b)*silhouette*1.2;
			p.xz=mat2(vec2(cos(turn),-sin(turn)),vec2(sin(turn),cos(turn)))*p.xz;
		}
	}
	// Actual last-spike age produces a local bump with a 60ms decay. Firing
	// rate RG bytes are NOT misread as a spike amplitude.
	// Normal estimation samples slightly outside [0,1]. Squaring with pow()
	// is undefined for the negative sine there, and can corrupt seam normals.
	float seam_gate=sin(u*3.14159265)*sin(v*3.14159265);
	float closed_gate=seam_gate*seam_gate;
	float kick=local_spike(uv,id.x)*closed_gate;
	p.z+=kick*.022;
	// Articulate the local domain without moving it outside its reserved lane.
	p.xy*=1.-impact_voice.x*.22*closed_response;
	p*=1.+bass_voice.x*.14*closed_gate*closed_response;
	p.z+=sin(u*6.283185+bass_voice.z+id.w)*bass_voice.x*.34*closed_gate*closed_response;
	p.y+=sin(u*3.14159+lead_voice.z)*(lead_voice.y-.5)*lead_voice.x*.30*closed_gate*closed_response;
	p.z+=pow(.5+.5*sin(u*37.699+id.z),8.)*detail_voice.x*.035*closed_gate*closed_response;
	p.x+=(smoothstep(.42,.58,v)*2.-1.)*snare_voice.x*.14*closed_gate*closed_response;
	p.z+=bed_voice.x*sin(u*3.14159)*.12*closed_gate*closed_response;
	// Slice displacement stays within the reserved deformation envelope.
	p.x+=sin(uv.y*6.283185+id.w)*mutation*.025*closed_gate;
	// Never clamp vertex positions: the derivative becomes zero at the clamp,
	// producing crumpled metallic borders and invalid surface normals.
	return p;
}
void vertex() {
	identity=INSTANCE_CUSTOM;
	surface_face=UV2.y;
	vec4 state=texture(populations,(vec2(mod(identity.x,16.),floor(identity.x/16.))+.5)/16.);
	neural=state.g;
	if(shape_kind<1.5 || shape_kind>2.5) {
		VERTEX=deform(UV,identity,state.g);
		vec3 du=deform(UV+vec2(.001,0.),identity,state.g)-deform(UV-vec2(.001,0.),identity,state.g);
		vec3 dv=deform(UV+vec2(0.,.001),identity,state.g)-deform(UV-vec2(0.,.001),identity,state.g);
		vec3 normal=normalize(cross(du,dv)+vec3(0.,0.,.00000001));
		if(shape_kind<.5) {
			VERTEX+=normal*UV2.x*.035;
			if(UV2.y>.5 && UV2.y<1.5) {
				NORMAL=normalize(du*NORMAL.x+dv*NORMAL.y);
			} else NORMAL=normal*UV2.x;
		} else {
			NORMAL=normal;
			// Latitude has zero azimuth tangent at the poles. A finite-difference
			// cross product there used to fall back to +Z and leave a dark pinhole.
			float morphology=mod(floor(contour_mode+identity.z*3.),4.);
			if(shape_kind>3.5 && (morphology<.5 || morphology>2.5)) {
				if(UV.y<.00001) NORMAL=vec3(0.,1.,0.);
				if(UV.y>.99999) NORMAL=vec3(0.,-1.,0.);
			}
		}
	} else {
		float role=floor(identity.w);
		vec4 voice=musical_voice(role);
		if(role<.5) VERTEX.xy*=1.-voice.x*.20;
		else if(role<2.5 && role>1.5) VERTEX.x+=sign(VERTEX.y)*voice.x*.10;
		else if(role<3.5 && role>2.5) VERTEX.z*=1.-voice.x*.18;
	}
	// Explicit inverse transpose includes the MultiMesh instance scale. Thin
	// sheets have e.g. 3:2:.15 proportions: treating normals like positions
	// magnified minute folds into dark cloth-like creases and flashing rings.
	surface_normal=transpose(inverse(mat3(MODELVIEW_MATRIX)))*NORMAL;
}
void fragment() {
	float role=identity.y;
	vec3 paper=design_paper(palette),ink=design_ink(palette),accent=design_accent(palette);
	if(polarity>.5) {vec3 swap=paper;paper=ink;ink=swap;}
	// Paper is the background colour, not the colour of solid objects. A
	// separate mid-tone keeps quiet panels and rings readable in either polarity.
	vec3 surface_tone=mix(ink,paper,.92);
	bool plane=shape_kind<.5 || (shape_kind>2.5 && shape_kind<3.5);
	vec3 n=normalize(surface_normal);
	// Choose the visible side by its normal, not the UV mesh winding.
	if(dot(n,VIEW)<0.) n=-n;
	float facing=abs(dot(n,normalize(VIEW)));
	float lighting=.54+.46*abs(dot(n,normalize(vec3(-.4,.7,.9))));
	vec3 color=role<.5?ink:(role<1.5?paper:accent);
	float coverage=1.;
	bool cutout=plane && role>3.5 && family!=11.;
	if(role>2.5 && role<3.5) {
		// Stable satin lighting. Reflection-vector bands were effectively a
		// moving texture: tiny normal changes produced the brown/white patches
		// and visible flicker on rings and rounded sculptures.
		vec3 light_dir=normalize(vec3(-.35,.72,.9));
		float ndl=clamp(dot(n,light_dir)*.5+.5,0.,1.);
		float fresnel=pow(1.-facing,2.);
		float highlight=smoothstep(.28,.82,ndl);
		color=mix(accent,paper,.16+.38*highlight);
		color=mix(color,ink,fresnel*.16);
		lighting=.94+.06*ndl;
	} else if(role>3.5) {
		vec2 crop=(UV-.5)/(1.+fract(turnover)*.3)+.5;
		vec4 print=graphic_composition(crop,graphic_mode+identity.z*5.+material_shift,identity.z,development,neural*2.,paper,ink,accent,floor(identity.w));
		vec3 own=print.rgb;
		if(cutout) coverage=print.a;
		vec3 recorded=texture(memory_view,crop).rgb;
		float aperture=graphic_edge(length((UV-.5)*2.)-(.35+aperture_action*.25));
		// Only an explicitly designated screen owns a past-world image.
		// A remembered frame is a short visual echo, never the material itself.
		// Keeping its contribution bounded prevents high-frequency old scenes from
		// turning a clean 3D screen into a noisy black/red patch.
		color=mix(own,recorded,memory_valid*aperture*.18*step(4.5,role)*(cutout?0.:1.)); lighting=1.;
	}
	if(role>.5 && role<1.5) {
		// Flat paper must read as a designed surface, not as wrinkled cloth.
		// Its motion comes from the transform and printed composition; the
		// material itself stays almost uniform so edges remain crisp.
		color=surface_tone;
		lighting=.94+.06*facing;
	}
	if(cutout && surface_face>.5) {
		// A rectangular substrate rim or back cannot frame a free-standing cut
		// shape. The front coverage below is the actual printed silhouette.
		coverage=0.;
	} else if(plane && !cutout && surface_face>.5) {
		// Rim and back carry a solid satin material, not a second stretched UV print.
		color=role<.5?ink:(role<1.5?surface_tone:accent);
		lighting=.90+.10*facing;
	}
	ALBEDO=color*lighting;
	ALPHA=coverage;
	ALPHA_SCISSOR_THRESHOLD=.5;
	ALPHA_ANTIALIASING_EDGE=.45;
	ALPHA_TEXTURE_COORDINATE=UV*1024.;
}
