extends RefCounted
## Six persistent visual voices. Content is sampled ONLY from model readouts.
## Audio IDs schedule articulation; role envelopes/contours never bypass cells.
const COUNT := 6
var level := PackedFloat32Array()
var attack := PackedFloat32Array()
var contour := PackedFloat32Array()
var memory := PackedFloat32Array()
var owners := PackedInt32Array()
var age := PackedFloat32Array()
var accent := PackedFloat32Array()
var motion := PackedFloat32Array()
var phase := PackedFloat32Array()
var pixels := PackedByteArray()
var image: Image
var texture: ImageTexture
var phrase := 0
var upcoming := -1.
var prepare_amount := 0.
var motif_memory: Array[Dictionary]=[]
var motif_id := 0
var motif_variant := 0
var phrase_age := 0.
var release := PackedFloat32Array([.065,.110,.050,.026,.100,.350])
var until_attack := PackedFloat32Array([100.,100.,100.,100.,100.,100.])
var next_strength := PackedFloat32Array([0.,0.,0.,0.,0.,0.])
var prepare_s := PackedFloat32Array([.07,.12,.07,.07,.12,.12])

func _init() -> void:
	level.resize(COUNT); attack.resize(COUNT); contour.resize(COUNT); memory.resize(COUNT)
	age.resize(COUNT); age.fill(100.); accent.resize(COUNT); motion.resize(COUNT); phase.resize(COUNT)
	owners.resize(COUNT); pixels.resize(COUNT*2*16)
	for i in range(COUNT): owners[i]=i*41
	image=Image.create_from_data(COUNT,2,false,Image.FORMAT_RGBAF,pixels)
	texture=ImageTexture.create_from_image(image)

func configure_timing(values: PackedFloat32Array) -> void:
	if values.size()!=COUNT: return
	release=values

static func response_strength(rate: float, spikes: float) -> float:
	return pow(clampf(rate*.35+spikes*.65,0.,1.),1.5)

func observe(states: Array, ids: Array) -> void:
	if states.size()!=COUNT: return
	for i in range(COUNT):
		level[i]=clampf(float(states[i][0]),0.,1.)
		attack[i]=clampf(float(states[i][1]),0.,1.)
		contour[i]=clampf(float(states[i][2]),0.,1.)
		if ids.size()==COUNT: owners[i]=int(ids[i])

func articulate(voice: int, event_age: float, sample: Array=[]) -> void:
	if voice<0 or voice>=COUNT: return
	age[voice]=maxf(0.,event_age)
	# Actual neural firing strength, not raw audio amplitude.
	accent[voice]=response_strength(float(sample[0]),float(sample[1])) if sample.size()==4 else response_strength(level[voice],attack[voice])

func new_phrase() -> void:
	phrase+=1; phrase_age=0.
	# Match the neural contour of a returning phrase, retaining its identity.
	var best := -1; var distance := .16
	for j in range(motif_memory.size()):
		var difference := 0.
		for i in range(COUNT): difference+=absf(memory[i]-float(motif_memory[j].shape[i]))/COUNT
		if difference<distance: distance=difference; best=j
	if best>=0:
		motif_id=int(motif_memory[best].id); motif_variant=int(motif_memory[best].visits)+1
		motif_memory[best].visits=motif_variant
	else:
		motif_id=phrase; motif_variant=0
		motif_memory.append({"id":motif_id,"shape":Array(memory),"visits":0})
		if motif_memory.size()>24: motif_memory.pop_front()

func advance(dt: float) -> void:
	phrase_age+=dt
	prepare_amount=clampf(1.-upcoming/.65,0.,1.) if upcoming>=0. else 0.
	for i in range(COUNT):
		age[i]+=dt
		memory[i]=lerpf(memory[i],level[i],1.-exp(-dt/1.2))
		phase[i]+=dt*(level[i]*1.3+attack[i]*.7)
		var a := age[i]
		var windup := 0.
		if until_attack[i]>0. and until_attack[i]<prepare_s[i]:
			windup=-next_strength[i]*.3*sin(PI*(1.-until_attack[i]/prepare_s[i]))
		match i:
			0: motion[i]=accent[i]*(exp(-a/maxf(.018,release[i]))-.36*exp(-a/maxf(.04,release[i]*2.8))*sin(a*26.))
			1: motion[i]=level[i]*.82+accent[i]*exp(-a/maxf(.025,release[i]*1.45))*.18
			2: motion[i]=accent[i]*exp(-a/maxf(.018,release[i]))
			3: motion[i]=accent[i]*exp(-a/maxf(.014,release[i]))
			4: motion[i]=level[i]*.7+accent[i]*exp(-a/maxf(.025,release[i]*1.3))*.3
			5: motion[i]=memory[i]*.45+level[i]*.25+accent[i]*exp(-a/maxf(.045,release[i]*2.))*.30
		motion[i]+=windup
		# Row0: articulation, contour, continuous phase, neural level.
		pixels.encode_float(i*16,motion[i]); pixels.encode_float(i*16+4,contour[i])
		pixels.encode_float(i*16+8,phase[i]); pixels.encode_float(i*16+12,level[i])
		# Row1: source ensemble, current spike response, motif and release age.
		pixels.encode_float((i+COUNT)*16,float(owners[i])); pixels.encode_float((i+COUNT)*16+4,attack[i])
		pixels.encode_float((i+COUNT)*16+8,float(motif_id)); pixels.encode_float((i+COUNT)*16+12,age[i])
	image.set_data(COUNT,2,false,Image.FORMAT_RGBAF,pixels); texture.update(image)
