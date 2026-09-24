shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/design_palette.gdshaderinc"
#include "res://shaders/editorial_mask.gdshaderinc"
uniform sampler2D neural_frame : filter_nearest, repeat_disable;
uniform sampler2D ensemble_map : filter_nearest, repeat_disable;
uniform sampler2D ensemble_frame : filter_nearest, repeat_disable;
uniform sampler2D scene_anchors : filter_nearest, repeat_disable;
uniform float world_light=0.;
uniform vec2 view_size=vec2(1440.,900.);
uniform float phase=0.; // model seconds
uniform float between_frames=0.;
uniform float shot=0.;
uniform int lens=0;
uniform int palette=0;
uniform float density=1.;
uniform float trace_fraction=1.;
varying vec4 trace_color;
float hash(float n) {return fract(sin(n*127.1)*43758.5453);}
void vertex() {
	ivec2 address=ivec2(INSTANCE_CUSTOM.xy+vec2(.5));
	int id=address.x+address.y*512;
	vec4 packed=texelFetch(neural_frame,address,0)*255.;
	float hz=(packed.r+256.*packed.g)/32.;
	float recorded_age=packed.a*.002;
	float age=recorded_age+between_frames;
	float spike_tick=floor((phase-recorded_age)*500.+.5);
	float seed=float(id)*.71+spike_tick*1.37;
	float lifespan=.030+hash(float(id)*2.17)*.120;
	float progress=age/lifespan;
	// A recent actual spike creates the event. No spike -> no particle. New
	// spikes overwrite the cell's bounded GPU slot; old events expire.
	float alpha=(1.-smoothstep(.45,1.,progress))*step(packed.a,254.)*step(0.,progress);
	alpha*=step(hash(seed+31.),trace_fraction)*(.25+min(hz/100.,.65));
	int group=int(texelFetch(ensemble_map,address,0).r*255.+.5);
	vec4 ensemble=texelFetch(ensemble_frame,ivec2(group%16,group/16),0);
	vec4 attachment=texelFetch(scene_anchors,ivec2(group%16,group/16),0);
	vec4 axes=texelFetch(scene_anchors,ivec2(group%16,group/16+16),0);
	vec2 anchor=attachment.xy;
	alpha*=attachment.w;
	float angle=ensemble.b*.3+float(group)*.71;
	vec2 direction=vec2(cos(angle),sin(angle));
	float spread=hash(seed)*2.-1.;
	// Stable cell identity chooses a place on the source component's projected
	// tangent plane. A real spike briefly articulates it; no central dust blob.
	vec2 origin=anchor+axes.xy*(hash(float(id)*.31)*2.-1.)+axes.zw*(hash(float(id)*.71)*2.-1.);
	vec2 pos=origin+direction*progress*(.007+ensemble.r*.03)*attachment.z;
	float c=hash(seed+17.);
	vec2 scale=vec2(1.+ensemble.r*2.,1.);
	if(c>.6) scale=vec2(2.+progress*15.,.8);
	if(c<.08) scale=vec2(1.,3.+ensemble.g*9.);
	vec2 quad=VERTEX*scale;
	quad=mat2(direction,vec2(-direction.y,direction.x))*quad;
	VERTEX=pos*view_size+quad;
	if(alpha<.02 || progress>=1.) VERTEX=vec2(-100.,-100.);
	vec3 accent=design_accent(float(palette));
	vec3 ink=world_light>.5?vec3(.055,.065,.09):vec3(.88,.92,1.);
	trace_color=vec4(mix(accent,ink,step(.4,c)),alpha*.42);
}
void fragment() {COLOR=vec4(trace_color.rgb,trace_color.a*(1.-editorial_paper(SCREEN_UV)));}
