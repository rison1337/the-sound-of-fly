shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/design_palette.gdshaderinc"
#include "res://shaders/graphic_language.gdshaderinc"
#include "res://shaders/editorial_mask.gdshaderinc"
uniform sampler2D trajectory : filter_linear, repeat_disable;
uniform sampler2D populations : filter_nearest, repeat_disable;
uniform sampler2D history_view : source_color, filter_linear, repeat_disable;
uniform float history_valid=0.;
uniform float background=1.;
uniform float topology=0.;
uniform float palette=0.;
uniform float polarity=0.;
uniform float progress=0.;
uniform float graphic_mode=0.;
uniform float edit_kind=0.;
uniform float edit_age=1.;
uniform float edit_strength=0.;
uniform float morph=0.5;
uniform float layout_mode=0.;
uniform float view_index=0.;
uniform float anticipation=0.;
void fragment() {
	vec3 paper=design_paper(palette),ink=design_ink(palette),accent=design_accent(palette);
	if(polarity>.5) {vec3 swap=paper;paper=ink;ink=swap;}
	vec3 base=background>.5?paper:ink;
	if(background>1.5) base=accent;
	vec2 p=UV;
	vec4 bass_voice=musical_voice(1.);
	// A known approaching phrase boundary prepares the existing geometry.
	p=(p-.5)/(1.+anticipation*bass_voice.x*.22)+.5;
	float impulse=exp(-edit_age/.09)*edit_strength;
	// Bounded editorial operations change the existing graphic, not an overlay.
	if(edit_kind<.5) p=(p-.5)/(1.+impulse*.8)+.5;
	if(edit_kind>4.5) p=graphic_rotate(p-.5,impulse*.08)+.5;
	float layout=mod(layout_mode+view_index,4.);
	vec2 cell_id=vec2(0.),uv=p;
	if(layout<.5) {
		// A folded print with unequal panels, never a matrix of motif thumbnails.
		float seam=.61+(framing_shape-.5)*.30;
		if(p.x<seam) {uv=vec2(p.x/seam,p.y)*.72+vec2(.18,.10);}
		else if(p.y<.28) {uv=vec2((p.x-seam)/(1.-seam),p.y/.28);cell_id=vec2(2.,1.);}
		else {uv=vec2((p.x-seam)/(1.-seam),(p.y-.28)/.72);cell_id=vec2(1.,0.);}
	} else if(layout<1.5) {
		// An asymmetric spread: one broad area and two narrower inserts.
		float split=.40+morph*.22;
		if(p.x<split) {uv=vec2(p.x/split,p.y);cell_id=vec2(0.,0.);}
		else {uv=vec2((p.x-split)/(1.-split),fract(p.y*2.));cell_id=vec2(1.,floor(p.y*2.));}
	} else if(layout<2.5) {
		// Editorial strips have different heights instead of an invariant grid.
		float a=.18+morph*.13,b=.74;
		if(p.y<a) {uv=vec2(p.x,p.y/a);cell_id=vec2(0.,0.);}
		else if(p.y<b) {uv=vec2(p.x,(p.y-a)/(b-a));cell_id=vec2(1.,0.);}
		else {uv=vec2(p.x,(p.y-b)/(1.-b));cell_id=vec2(2.,0.);}
	} else {
		// Macro crop with a inset showing a captured prior construction.
		uv=(p-.5)*.74+.5;
		if(p.x>.68 && p.y>.62) {uv=(p-vec2(.68,.62))/vec2(.32,.38);cell_id=vec2(3.,1.);}
	}
	// The split/aperture modes already define their screen architecture. Their
	// printed region is a single enlarged surface, not a second grid on top.
	if(presentation>2.5 && presentation<3.5) {
		uv=(p-vec2(.5))*(.86+framing_shape*.20)+.5;
		uv=graphic_rotate(uv-.5,(framing_shape-.5)*.5)+.5;
		cell_id=vec2(view_index,0.);
	}
	float voice_role=mod(cell_id.x+cell_id.y*3.,6.);
	float owner=mod(cell_id.x*41.+cell_id.y*77.+floor(morph*255.),256.);
	vec4 neural=texture(populations,(vec2(mod(owner,16.),floor(owner/16.))+.5)/16.);
	float contour=texture(trajectory,vec2((cell_id.x+cell_id.y*3.+.5)/16.,.15+progress*.65)).r;
	float panel=graphic_box((uv-.5)*2.,vec2(.965,.96));
	// Keep the print language alive between cuts: the neural voice bends the
	// composition continuously, while the audio transient still owns timing.
	vec4 local_voice=musical_voice(voice_role);
	float print_phase=progress*2.+local_voice.z*.45;
	float print_response=clamp(neural.g*2.+local_voice.x*.35,0.,1.8);
	vec3 sheet=graphic_print(uv,graphic_mode+cell_id.x+cell_id.y*2.,contour,print_phase,print_response,paper,ink,accent,voice_role);
	if(edit_kind>3.5 && edit_kind<4.5) {
		vec2 plunge=(uv-.5)/(1.+impulse*1.8)+.5;
		sheet=graphic_print(plunge,graphic_mode+cell_id.x+cell_id.y*2.,contour,print_phase,print_response,paper,ink,accent,voice_role);
	}
	if(history_valid>.5 && cell_id.x>2.5 && (topology==7. || topology==11.)) {
		float insert=graphic_box((uv-.5)*2.,vec2(.64,.55));
		sheet=mix(sheet,texture(history_view,uv).rgb,insert);
	}
	vec3 graphic=mix(paper,sheet,panel);
	float reveal=editorial_paper(UV);
	COLOR=vec4(mix(base,graphic,reveal),1.);
}
