extends RefCounted
## Compile once per phrase. Audio supplies cue times; the recorded downstream
## samples and neural history supply movement, ordering and spatial proportions.
static func score(phrase: Dictionary, attacks: Array) -> Dictionary:
	var start := float(phrase.start); var duration := maxf(.1,float(phrase.end)-start)
	var cues := PackedFloat32Array([0.,.20,.43,.72,.92,1.])
	var response := PackedFloat32Array([0.,0.,0.,0.,0.,0.])
	var counts := PackedInt32Array([0,0,0,0,0,0])
	for event in attacks:
		var voice := int(event.voice); var sample: Array=event.get("neural_sample",[])
		if voice<0 or voice>5 or sample.size()!=4: continue
		response[voice]+=clampf(float(sample[0])*.35+float(sample[1])*.65,0.,1.)
		counts[voice]+=1
	for i in range(6): response[i]/=maxi(1,counts[i])
	# Ordered windows prevent coincident cues. With no responding attack in a
	# window, retain a continuous neutral stage rather than inventing an accent.
	for stage in range(1,5):
		var ideal := cues[stage]; var best := -INF; var chosen := ideal
		for event in attacks:
			var at := (float(event.time)-start)/duration
			var sample: Array=event.get("neural_sample",[])
			if absf(at-ideal)>.075 or sample.size()!=4: continue
			var strength := float(sample[0])*.35+float(sample[1])*.65
			if strength<.025: continue
			var rank := strength-absf(at-ideal)*3.
			if rank>best: best=rank; chosen=at
		cues[stage]=chosen
	return {"cues":Array(cues),"response":Array(response)}

static func compile(d: Dictionary, phrase: Dictionary) -> Dictionary:
	var score_data: Dictionary=phrase.get("design_score",{})
	var response: Array=score_data.get("response",[0.,0.,0.,0.,0.,0.]).duplicate()
	var sustained: Array=d.get("voice_memory",[0.,0.,0.,0.,0.,0.])
	for i in range(6): response[i]=maxf(float(response[i]),float(sustained[i]))
	var trajectory: Array=d.trajectory
	var rise := 0.; var spread := 0.
	for b in range(16):
		rise+=float(trajectory[48+b])-float(trajectory[b])
		spread+=absf(float(trajectory[32+b])-float(trajectory[16+b]))
	rise/=16.; spread/=16.
	var axis := Vector2(float(d.axis_x),float(d.axis_y)).normalized()
	var mode := 0 if float(response[1])>float(response[4]) else 1
	if spread>.15 or float(response[2])>float(response[1])+.12: mode=2
	# These are different deformations of a construction, not a new random scene.
	return {"cues":score_data.get("cues",[0.,.20,.43,.72,.92,1.]),
		"mode":mode,"axis":axis,"rise":rise,
		"panel_columns":2 if mode==1 else 3,
		"panel_width":clampf(.84+float(response[1])*.10-spread*.12,.76,.92),
		"amplitude":clampf(float(d.mid)*.35+float(response[4])*.65+spread,.12,.85),
		"depth":clampf(float(d.low)*.4+float(response[1])*.7,.12,1.),
		"stagger":clampf(float(d.irregularity)*.08+float(d.high)*.05,.025,.12),
		"response":response}

static func stage_time(progress: float, plan: Dictionary) -> float:
	var cues: Array=plan.get("cues",[0.,.20,.43,.72,.92,1.])
	for i in range(5):
		if progress<=float(cues[i+1]):
			return float(i)+smoothstep(float(cues[i]),float(cues[i+1]),progress)
	return 5.

static func group_action(d: Dictionary, g: int, progress: float) -> Transform3D:
	var plan: Dictionary=d.get("choreography",{})
	if plan.is_empty(): return Transform3D.IDENTITY
	var phase := stage_time(progress,plan)
	var profile := float(d.profile[(g*3)%16])
	var delay := profile*float(plan.stagger)*3.
	var build := smoothstep(delay,1.+delay,phase)
	var open := smoothstep(1.3+delay,3.+delay,phase)
	var release := smoothstep(3.3+delay,5.,phase)
	var evolve := open*(1.-release*.55)
	var amount := float(plan.amplitude); var depth := float(plan.depth)
	var axis: Vector2=plan.axis
	var signum := -1. if g%2==0 else 1.
	var family := int(d.topology); var mode := int(plan.mode)
	var rot := Vector3.ZERO; var offset := Vector3.ZERO
	var scale := Vector3.ONE*(.68+.32*build-.16*release)
	if family in [2,3,5,8,11]:
		# Articulated depth levels turn and breathe independently. Bounded tilt
		# keeps them inside their own slabs, including the widest tunnel gates.
		rot.z=signum*(.15+amount*.55)*evolve+release*axis.x*.28
		rot.x=sin(float(g)*.8)*evolve*.055
		rot.y=cos(float(g)*.8)*evolve*.055
		offset.x=axis.x*sin(float(g)*.9+open*PI)*depth*.30
		offset.y=axis.y*cos(float(g)*.7+open*PI)*depth*.30
		if family==8: rot.z*=.25; offset*=.35
	else:
		# Held graphic plane -> hinged relief -> articulated collage. All parts
		# in a group inherit this transform, so attachments remain attached.
		rot.x=axis.y*evolve*(.10+amount*.16)
		rot.y=signum*evolve*(.16+depth*.20)
		rot.z=signum*evolve*.075 if mode==0 else sin(float(g)*1.7)*evolve*.12
		offset.z=signum*evolve*(.25+depth*.65)
		if mode==1: scale.y*=1.-evolve*.16
		if mode==2: scale.x*=1.-evolve*.18
		offset.y=clampf(float(plan.rise),-.4,.4)*evolve*.35
	# Breakdown closes the construction as a coherent gesture, not flying debris.
	rot.y+=signum*release*.10
	if family==1: rot.z*=.25
	if family==4: rot.z*=.15
	if family==5: rot.x*=.18; rot.y*=.18
	if family==8:
		rot*=.15; scale*=.92
	return Transform3D(Basis.from_euler(rot)*Basis.from_scale(scale),offset)
