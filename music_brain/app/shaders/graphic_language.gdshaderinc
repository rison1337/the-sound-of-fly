// Shared print language: the same opaque design can be a flat frame or the
// material of a moving 3D panel. No random full-screen noise or stock images.
uniform sampler2D voices : filter_linear, repeat_disable;
vec4 musical_voice(float id) {
	return texture(voices,vec2((id+.5)/6.,.25));
}
float graphic_edge(float distance_value) {
	float aa=max(.0008,fwidth(distance_value));
	return 1.-smoothstep(-aa,aa,distance_value);
}
float graphic_stripe(float phase_value,float width) {
	// Filter the phase BEFORE sin(): derivatives of the already-aliased sine
	// can miss distant subpixel lines. Unresolved ribs become their coverage.
	float footprint=max(fwidth(phase_value),.00035);
	float coverage=2.*asin(clamp(width,0.,1.))/3.14159265;
	float line=1.-smoothstep(width-footprint*.55,width+footprint*.55,abs(sin(phase_value)));
	// At extreme perspective a repeated line is smaller than a pixel. Replace
	// it with its analytic coverage instead of letting it shimmer into grain.
	return mix(line,coverage,smoothstep(.75,1.8,footprint));
}
float graphic_box(vec2 p,vec2 half_size) {
	vec2 q=abs(p)-half_size;
	return graphic_edge(max(q.x,q.y));
}
vec2 graphic_rotate(vec2 p,float a) {
	float c=cos(a),s=sin(a); return vec2(c*p.x-s*p.y,s*p.x+c*p.y);
}
// RGB is the ink; A is its actual cut-paper silhouette. Keeping coverage
// separate from paper colour lets spatial panels have real negative space.
vec4 graphic_composition(vec2 uv,float mode,float motif,float phase,float response,vec3 paper,vec3 ink,vec3 accent,float voice_role) {
	vec2 q=(uv-.5)*2.;
	vec4 impact=musical_voice(0.),bass=musical_voice(1.),crack=musical_voice(2.);
	vec4 detail=musical_voice(3.),lead=musical_voice(4.),bed=musical_voice(5.);
	// Each surface belongs to a persistent role; other voices stay elsewhere.
	impact*=1.-step(.5,abs(voice_role-0.)); bass*=1.-step(.5,abs(voice_role-1.));
	crack*=1.-step(.5,abs(voice_role-2.)); detail*=1.-step(.5,abs(voice_role-3.));
	lead*=1.-step(.5,abs(voice_role-4.)); bed*=1.-step(.5,abs(voice_role-5.));
	// Preserve the graphic silhouette. Audio moves the print through phase and
	// proportion; large per-pixel displacement made panels look like dirty cloth.
	q/=1.+impact.x*.20;
	q.x+=sin(q.y*3.+bass.z)*bass.x*.20;
	q.y+=sin(q.x*3.14159+lead.z)*lead.x*(lead.y-.5)*.42;
	q.x+=sin(q.y*3.14159)*crack.x*.14;
	phase+=lead.z*1.25+bass.z*.22+crack.z*.12;
	float family=mod(floor(mode+.5),6.);
	float morph=clamp(motif*.65+lead.y*.25+bass.x*.10,0.,1.);
	float response_shape=clamp(response*.42+bass.x*.58+bed.x*.20+impact.x*.24,0.,1.);
	vec3 color=paper;
	// Tint internal lines toward the active accent so they stay part of the
	// motif instead of reading as detached black guide marks.
	vec3 line_ink=mix(ink,accent,.50);
	float coverage=0.;
	if(family<.5) {
		// Cropped graphic score: big opaque silhouette, fine lines INSIDE it.
		vec2 p=graphic_rotate(q,(morph-.5)*1.2+phase*.18);
		float silhouette=graphic_box(p,vec2(.72,.92));
		float line=graphic_stripe((p.x+sin(p.y*3.+morph*4.)*.2)*(6.+morph*4.),.22);
		color=mix(color,accent,silhouette);
		color=mix(color,line_ink,silhouette*line);
		color=mix(color,paper,graphic_box(p-vec2(.0,.34-response_shape*.5),vec2(.8,.075)));
		coverage=silhouette*(1.-graphic_box(p-vec2(.0,.34-response_shape*.5),vec2(.8,.075)));
	} else if(family<1.5) {
		// Guilloche rosette. A bounded silhouette, crisp negative apertures.
		vec2 p=graphic_rotate(q,phase*.3);
		float a=atan(p.y,p.x),r=length(p);
		float lobes=3.+floor(morph*6.);
		float boundary=.67+.17*cos(a*lobes+phase*.8)+response_shape*.10;
		float body=graphic_edge(r-boundary);
		float rings=graphic_stripe((r+.07*cos(a*lobes))*(9.+morph*8.),.22);
		color=mix(paper,accent,body);
		color=mix(color,line_ink,body*rings*.72);
		color=mix(color,paper,graphic_edge(r-(.12+morph*.18)));
		coverage=body*(1.-graphic_edge(r-(.12+morph*.18)));
	} else if(family<2.5) {
		// Segmented slabs, emphatic graphic proportions instead of a waveform.
		float columns=4.+floor(morph*7.);
		float id=floor(uv.x*columns),x=fract(uv.x*columns)*2.-1.;
		float h=.25+.5*(.5+.5*sin(id*.65+phase+response_shape*1.5));
		float bar=graphic_box(vec2(x,q.y),vec2(.82,h));
		color=mix(paper,mix(ink,accent,step(.5,fract(id*.5))),bar);
		coverage=bar;
	} else if(family<3.5) {
		// Optical ribbon. Bright raster remains clipped to its broad outline.
		vec2 p=graphic_rotate(q,(morph-.5)*1.4);
		float curve=sin(p.x*3.8+phase*.5)*(.26+response_shape*.12);
		float ribbon=graphic_edge(abs(p.y-curve)-(.18+morph*.2));
		float scan=graphic_stripe((p.y-curve)*(9.+response_shape*5.)+p.x*3.,.22);
		color=mix(paper,accent,ribbon);
		color=mix(color,line_ink,ribbon*scan*.68);
		coverage=ribbon;
	} else if(family<4.5) {
		// Repeated asymmetric lens / screen contents.
		vec2 p=graphic_rotate(q,(morph-.5)*.5);
		float lens=graphic_edge(length(p*vec2(.78,1.5))-.86);
		float ribs=graphic_stripe((p.x+p.y*p.y*.8)*(6.+morph*5.),.22);
		color=mix(paper,ink,lens);
		color=mix(color,mix(accent,line_ink,.28),lens*ribs);
		color=mix(color,paper,graphic_box(p-vec2(response_shape*.22-.11,0.),vec2(.09,.8)));
		coverage=lens*(1.-graphic_box(p-vec2(response_shape*.22-.11,0.),vec2(.09,.8)));
	} else {
		// Cut paper with sharp stepped edges and an off-centre aperture.
		vec2 p=graphic_rotate(q,(morph-.5)*.8);
		// Discontinuous terraces caused aliased horizontal tears in perspective.
		float body=graphic_edge(abs(p.x)-(.46+.16*sin(p.y*3.4+morph*5.)));
		body*=graphic_box(p,vec2(.95,.92));
		color=mix(paper,ink,body);
		float aperture=graphic_edge(length(p-vec2(morph*.3-.15,.15))-(.30+response_shape*.07));
		color=mix(color,accent,aperture*body);
		color=mix(color,paper,graphic_box(p-vec2(0.,-.5),vec2(.9,.02)));
		coverage=body*(1.-graphic_box(p-vec2(0.,-.5),vec2(.9,.02)));
	}
	// Percussion opens short notches IN existing ink; no screen-wide dust.
	float tooth=graphic_box(vec2(fract(uv.x*9.+detail.z)*2.-1.,q.y-.62),vec2(.12,detail.x*.045));
	color=mix(color,paper,tooth*step(.15,detail.x));
	coverage*=1.-tooth*step(.15,detail.x);
	return vec4(color,coverage);
}
vec3 graphic_print(vec2 uv,float mode,float motif,float phase,float response,vec3 paper,vec3 ink,vec3 accent,float voice_role) {
	return graphic_composition(uv,mode,motif,phase,response,paper,ink,accent,voice_role).rgb;
}
