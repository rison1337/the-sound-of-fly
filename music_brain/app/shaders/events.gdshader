shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/design_palette.gdshaderinc"
#include "res://shaders/editorial_mask.gdshaderinc"
uniform sampler2D event_frame : filter_nearest, repeat_disable;
uniform sampler2D ensemble_frame : filter_nearest, repeat_disable;
uniform sampler2D glyph_atlas : filter_linear, repeat_disable;
uniform sampler2D scene_anchors : filter_nearest, repeat_disable;
uniform float event_clock=0.;
uniform vec2 view_size=vec2(1440.,900.);
uniform float world_light=0.;
uniform float palette_seed=0.;
uniform float scene_transition=1.;
varying flat vec4 identity;
varying flat vec4 motion;
varying flat vec4 style;
varying flat vec4 response;
varying flat vec4 extra;
varying float life;
varying float envelope;
varying float clock_age;
varying float depth_mix;
vec4 record(int slot,int column) {return texelFetch(event_frame,ivec2(column,slot),0);}
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
mat2 rotate(float a) {return mat2(vec2(cos(a),-sin(a)),vec2(sin(a),cos(a)));}
vec3 accent(float seed) {
	return design_accent(palette_seed);
}
void vertex() {
	int slot=int(INSTANCE_CUSTOM.x+.5);
	identity=record(slot,0);
	vec4 placement=record(slot,1);
	motion=record(slot,2);
	style=record(slot,3);
	response=record(slot,4);
	extra=record(slot,5);
	clock_age=max(0.,event_clock-identity.z);
	life=clamp(clock_age/max(.001,identity.w),0.,1.);
	envelope=min(1.,clock_age/.009)*(1.-smoothstep(.68,1.,life));
	if(identity.x<0. || life>=1.) {VERTEX=vec2(-100.,-100.);envelope=0.;}
	else {
		vec2 q=VERTEX;
		vec4 live=texelFetch(ensemble_frame,ivec2(int(identity.y)%16,int(identity.y)/16),0);
		depth_mix=clamp(motion.z,0.,1.);
		float expansion=1.-pow(1.-life,3.);
		float distortion=(live.r-response.x)*.35;
		if(identity.x<.5) {
			q.x+=q.y*sin(response.z+life*3.)*.14;
			q.y*=.88+expansion*.18+distortion;
			q.x+=step(.74,life)*sin(q.y*36.+style.y*18.)*(life-.74)*.4;
		} else if(identity.x<3.5 && identity.x>1.5) {
			q*=.78+expansion*.28+distortion;
		}
		q=rotate(motion.w+clock_age*(response.x-.3)*.18)*q;
		q*=mix(.72,1.24,depth_mix);
		vec2 drift=motion.xy*(life-.25)*mix(.72,1.18,depth_mix)*.18;
		vec2 parallax=vec2((depth_mix-.5)*.045,(.5-depth_mix)*.028);
		VERTEX=(placement.xy+parallax+drift+q*placement.zw)*view_size;
		if(identity.x>=0. && identity.x<6.5 && editorial_paper(vec2(.5))<.5) {
			int owner=int(identity.y);
			vec4 anchor=texelFetch(scene_anchors,ivec2(owner%16,owner/16),0);
			vec4 axes=texelFetch(scene_anchors,ivec2(owner%16,owner/16+16),0);
			if(identity.x<.5) VERTEX=(anchor.xy+axes.xy*q.x*1.35+axes.zw*(q.y*.20-.6))*view_size;
			else VERTEX=(anchor.xy+drift+q*placement.zw)*view_size;
			envelope*=anchor.w;
		}
		if(identity.x>6.5) VERTEX=(VERTEX/view_size-vec2(.5))*1.02*view_size+view_size*.5;
	}
}
float line(float distance_value,float width) {return 1.-smoothstep(width,width+fwidth(distance_value)*1.4,abs(distance_value));}
void fragment() {
	// No text even if a legacy descriptor or manual grammar emits TYPE.
	if(envelope<.002 || identity.x<.5) discard;
	int grammar=int(identity.x+.5);
	// SubViewport textures enter CanvasItem with the vertical origin inverted.
	// Flip the lookup only; motion and placement continue using the normal quad.
	vec2 uv=vec2(UV.x,1.-UV.y);
	vec2 p=uv-.5;
	float variant=style.w;
	float seed=style.y;
	vec3 ink=mix(vec3(.94,.94,.89),vec3(.025,.035,.05),world_light);
	vec3 deep=vec3(.035,.04,.06);
	vec3 color=accent(style.z);
	float alpha=0.;
	float grammar_alpha=1.;
	float a=response.x;
	float b=response.y;
	float phase=response.z;
	float step_life=floor(life*5.)/5.;
	if(grammar==0) {
		grammar_alpha=.94;
		// Text is an event-owned raster fragment, stretched, sliced and retired.
		int word=int(extra.x)%48;
		vec2 local=uv;
		float slice=floor(uv.y*9.);
		local.x+=(hash(vec2(slice,seed*37.))-.5)*smoothstep(.55,1.,life)*.28;
		vec2 atlas_uv=(vec2(float(word%4),float(word/4))+clamp(local,vec2(.004),vec2(.996)))/vec2(4.,12.);
		float glyph=texture(glyph_atlas,atlas_uv).a;
		color=variant<3.?ink:accent(style.z);
		if(variant>5.) {
			vec2 offset=vec2(.0015,0.);
			float edge=max(texture(glyph_atlas,atlas_uv+offset).a,texture(glyph_atlas,atlas_uv-offset).a)-glyph;
			glyph=max(edge,glyph*.12);
		}
		alpha=glyph*response.w;
	} else if(grammar==1) {
		grammar_alpha=.46;
		// Short contour/registration response attached to a 3D object.
		// No persistent halftone wallpaper or concentric background circles.
		if(variant<2.) {
			alpha=line(length(p)-(.18+life*.25),.009)*.9;
			color=ink;
		} else if(variant<4.) {
			alpha=max(line(p.x,.007)*step(abs(p.y),.16),line(p.y,.007)*step(abs(p.x),.16));
		} else if(variant<6.) {
			alpha=line(p.y+.32,.008)*step(uv.x,life)*step(life-.35,uv.x);
			color=ink;
		} else {
			alpha=max(line(p.x-.38,.008)*step(.2,abs(p.y)),line(p.y-.38,.008)*step(.2,abs(p.x)));
		}
		alpha*=response.w;
	} else if(grammar==2) {
		grammar_alpha=.27;
		// Spatial structure has its own vanishing point, perspective and lifetime.
		vec2 q=rotate(seed*6.28+life*(.2+a))*p;
		q.x*=1.15;
		float radius=max(abs(q.x),abs(q.y));
		float perspective=-log(max(radius,.018));
		float grids=fract(perspective*(2.+seed*2.)-clock_age*(.8+a*2.));
		float walls=step(.91,grids);
		float spokes=line(q.x-q.y,.002)+line(q.x+q.y,.002)+line(q.x,.001)+line(q.y,.001);
		alpha=(walls*.45+spokes*.45)*(1.-smoothstep(.42,.50,radius))*smoothstep(.005,.07,radius);
		color=mix(ink,color,seed);
		if(variant>4.) {
			float stripes=step(.92,fract(atan(q.y,q.x)*5.+perspective*2.+phase));
			alpha=max(alpha,stripes*.27);
		}
		alpha*=.6+response.w;
	} else if(grammar==3) {
		grammar_alpha=.60;
		// Analytic objects, not a pre-rendered clip. Each neural seed chooses a
		// different figure: inflated sphere, hexagonal prism, torus or star.
		vec2 q=p*2.3;
		q=rotate(motion.w+clock_age*(.5+a))*q;
		float angle=atan(q.y,q.x);
		float radius=length(q);
		float edge=radius;
		float mask=0.;
		float shell=0.;
		if(variant<2.) {
			float shape=1.+.12*sin(angle*(3.+floor(seed*5.))+phase+life*2.)*a;
			edge=radius/shape;
			mask=1.-smoothstep(.94,1.,edge);
			shell=smoothstep(.42,.78,edge)+.18*(1.-smoothstep(.78,.98,edge));
		} else if(variant<4.) {
			float sector=mod(angle+3.14159/6.,3.14159/3.)-3.14159/6.;
			float polygon=cos(3.14159/6.)/max(cos(sector),.001);
			edge=radius/polygon;
			mask=1.-smoothstep(.90,.98,edge);
			shell=line(edge-.74,.045)+line(edge-.94,.018);
		} else if(variant<6.) {
			edge=abs(radius-.57)*2.9;
			mask=1.-smoothstep(.90,1.,edge);
			shell=smoothstep(.20,.64,edge)+line(radius-.57,.028);
		} else {
			float lobes=5.+floor(seed*4.);
			float star=radius*(1.+.22*cos(angle*lobes+phase));
			edge=star/.82;
			mask=1.-smoothstep(.90,1.,edge);
			shell=smoothstep(.35,.76,edge)+line(edge-.82,.025);
		}
		vec3 n=normalize(vec3(q,sqrt(max(.001,1.-min(edge*edge,.98)))));
		vec3 reflection=reflect(vec3(0.,0.,-1.),n);
		float reflection_band=pow(.5+.5*sin(reflection.y*8.+reflection.x*3.+phase*.1),7.);
		float diffuse=max(dot(n,normalize(vec3(-.5,-.7,1.))),0.);
		color=color*(.15+diffuse*.55)+ink*reflection_band*.85;
		color+=pow(1.-n.z,4.)*.5;
		alpha=mask*shell*(.58+response.w*.22);
	} else if(grammar==4) {
		grammar_alpha=.36;
		int word=32+int(extra.x)%16;
		vec2 atlas_uv=(vec2(float(word%4),float(word/4))+uv)/vec2(4.,12.);
		float glyph=texture(glyph_atlas,atlas_uv).a;
		float frame=line(max(abs(p.x),abs(p.y))-.47,.008);
		alpha=max(glyph,frame*.45)*response.w;
		color=variant<4.?ink:color;
	} else if(grammar==5) {
		grammar_alpha=.40;
		float trajectory=sin(uv.x*(9.+a*14.)+phase+life*3.)*.12;
		float trace=line(p.y-trajectory,.006+style.x*.005);
		float gate=step(uv.x,.15+life*1.2)*step(max(0.,life-.35),uv.x);
		alpha=trace*gate*response.w;
		color=mix(ink,color,.6);
	} else if(grammar==6) {
		grammar_alpha=.30;
		// Ordered data bars replace hash noise. Neural response moves their
		// lengths and spacing; each mark remains a crisp graphic object.
		float row=floor(uv.y*5.); float column=fract(uv.x*(8.+floor(a*7.)));
		float dash=step(.18+fract(seed*3.+row*.37)*.28,column);
		float gate=step(.08,uv.y)*step(uv.y,.92);
		alpha=dash*(.22+style.x*.28)*gate*response.w;
		color=mix(color,ink,step(.62,fract(row*.31+seed)));
	} else {
		grammar_alpha=.055;
		// Long-lived world fields overlap. Broad plates/axes organize fast detail.
		vec2 q=rotate(seed*1.7-.85)*p;
		float plate=step(-.10,q.x)*step(q.x,.24+response.x*.18);
		float bars=step(.975,fract(q.y*(12.+floor(seed*18.))+phase*.07));
		color=mix(deep,accent(style.z),.12+seed*.23);
		alpha=plate*.35+bars*.11;
		if(variant>4.) {color=ink;alpha=plate*.45+bars*.12;}
		alpha*=response.w;
	}
	float depth_ink=mix(.42,1.,smoothstep(.12,.82,depth_mix));
	// Spatial marks belong to the depth-tested surface material. Canvas only
	// owns the small print annotations; it cannot occlude a 3D construction.
	alpha*=editorial_paper(SCREEN_UV);
	if(grammar!=0 && grammar!=4) alpha=0.;
	COLOR=vec4(clamp(color,0.,1.),clamp(alpha*envelope*style.x*grammar_alpha*depth_ink*smoothstep(0.,1.,scene_transition),0.,.94));
}
