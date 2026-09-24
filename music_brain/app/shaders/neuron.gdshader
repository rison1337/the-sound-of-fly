shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform sampler2D neural_frame : filter_nearest, repeat_disable;
uniform bool has_frame=false;
varying vec4 cell_color;
void vertex() {
	ivec2 address=ivec2(INSTANCE_CUSTOM.xy+vec2(.5));
	vec4 p=texelFetch(neural_frame,address,0)*255.;
	float hz=has_frame?(p.r+256.*p.g)/32.:0.;
	float fresh=has_frame?exp(-p.a*.002*24.)*step(p.a,254.):0.;
	float heat=clamp(hz/85.,0.,1.);
	vec3 col=mix(vec3(.12,.42,1.),vec3(1.,.15,.48),heat);
	col=mix(col,vec3(1.,.95,.83),fresh*.8);
	cell_color=vec4(col,.17+heat*.65+fresh*.65);
	VERTEX*=.4+heat*.8+fresh*.6;
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
	float radius=length(UV-.5)*2.;
	float halo=exp(-radius*radius*4.5)*(1.-smoothstep(.7,1.,radius));
	ALBEDO=cell_color.rgb;
	ALPHA=cell_color.a*halo;
}
