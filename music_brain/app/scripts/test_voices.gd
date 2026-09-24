extends SceneTree
const Voices=preload("res://scripts/neural_voices.gd")

func _initialize() -> void:
	var v=Voices.new()
	var states: Array=[]
	for i in range(6): states.append([.5,.4,float(i)/5.,.3])
	v.observe(states,[10,20,30,40,50,60])
	assert(v.owners[3]==40 and v.contour[4]>.7)
	v.articulate(0,0.); v.articulate(3,0.)
	v.advance(.03)
	assert(v.motion[0]>v.motion[3])
	var old_phase: float=v.phase[4]
	v.advance(.2)
	assert(v.motion[3]<.001 and v.motion[1]>.3 and v.phase[4]>old_phase)
	# No raw-audio pulse can create a strong motion from a silent neural state.
	for i in range(6): states[i]=[0.,0.,0.,0.]
	v.observe(states,[]); v.articulate(2,0.); v.advance(.01)
	assert(is_zero_approx(v.motion[2]))
	# Loud and very loud downstream responses must retain different strengths.
	assert(Voices.response_strength(.7,.7)<Voices.response_strength(.9,.9))
	v.until_attack[0]=.035; v.next_strength[0]=.6
	v.accent[0]=0.; v.age[0]=100.; v.advance(.001)
	assert(v.motion[0]<0.)
	v.until_attack[0]=100.; v.articulate(0,0.,[.7,.8,.2,.1]); v.advance(.001)
	assert(v.motion[0]>.4 and is_zero_approx(v.motion[2]))
	assert(v.pixels.size()==192)
	v.new_phrase(); var motif: int=v.motif_id
	v.new_phrase(); assert(v.motif_id==motif and v.motif_variant==1)
	print("NEURAL_VOICES_OK distinct articulation / source identity / fixed storage / returning motif")
	quit()
