extends RefCounted
## Editorial views of a persistent construction. Timing comes from scored
## attacks; selection and proportions come from downstream population output.
## This does not resample the world or reset neural/composition history.
var presentation := 0
var serial := 0
var previous := -1
var crop := .5
var framing := 0
var mask_from := 0
var mask_crop := .5
var mask_duration := .26
var hold := .5
var since_change := 0.
var last_signature := PackedFloat32Array([0.,0.,0.,0.,0.,0.])

func establish(d: Dictionary) -> void:
	presentation=1 if int(d.get("flat_mode",2))==0 else (2 if int(d.get("flat_mode",2))==1 else 0)
	since_change=0.; previous=-1; serial+=1
	crop=clampf(float(d.get("profile",[.5])[0]),.25,.75)
	framing=int(d.get("camera",0))%4
	mask_from=presentation; mask_crop=crop

func advance(dt: float) -> void:
	since_change+=dt

func articulate(voice: int, voices: RefCounted, d: Dictionary, synchrony: float) -> bool:
	if voice<0 or voice>=6: return false
	# No periodic wallpaper cycling. Even long phrases require a real onset
	# plus a downstream response to alter the framing.
	var strength: float=voices.accent[voice]
	if strength<.08 or since_change<hold: return false
	var change := 0.
	for i in range(6): change+=absf(voices.level[i]-last_signature[i])/6.
	if voice==3 and change<.10 and since_change<1.2: return false
	var scores: Array[float]=[
		voices.level[1]*.8+voices.level[5]*.45+synchrony*.3,
		voices.level[2]*.5+voices.attack[0]*.8+float(d.mid)*.4,
		voices.level[4]*.65+voices.level[3]*.5+change*2.,
		voices.level[5]*.65+voices.contour[4]*.4+float(d.depth)*.25,
		voices.attack[3]*.65+voices.level[2]*.5+change*1.5]
	scores[presentation]-=.85
	if previous>=0: scores[previous]-=.30
	var next := 0
	for i in range(1,5):
		if scores[i]>scores[next]: next=i
	mask_from=presentation; mask_crop=crop
	previous=presentation; presentation=next
	crop=clampf(voices.contour[voice]*.7+voices.level[1]*.3,.2,.8)
	# Wide, oblique, macro and depth views are selected by the population
	# balance. They are not a four-step camera carousel on successive beats.
	var views: Array[float]=[
		voices.level[5]*.8+voices.level[4]*.25,
		voices.contour[4]*.6+voices.level[2]*.5,
		voices.attack[0]*.65+voices.level[1]*.5,
		voices.level[3]*.5+synchrony*.7+change]
	views[framing]-=.55
	var next_view := 0
	for i in range(1,4):
		if views[i]>views[next_view]: next_view=i
	framing=next_view
	hold=clampf(.95-strength*.55-change*.5,mask_duration+.06,1.1)
	for i in range(6): last_signature[i]=voices.level[i]
	since_change=0.; serial+=1
	return true

func mask_progress() -> float:
	return smoothstep(0.,mask_duration,since_change)
