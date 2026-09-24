extends RefCounted
const History=preload("res://scripts/scene_history.gd")
const SceneGraph=preload("res://scripts/scene_graph.gd")
const Voices=preload("res://scripts/neural_voices.gd")
const ShotLanguage=preload("res://scripts/shot_language.gd")
const PhraseDesign=preload("res://scripts/phrase_design.gd")
var voices := Voices.new()
var editorial := ShotLanguage.new()
const CAPACITY := 512
const STRIDE := 32
const TYPE := 0
const GRAPHIC := 1
const SPATIAL := 2
const CHROME := 3
const DATA := 4
const TRACE := 5
const GLITCH := 6
const WORLD := 7
const STARTS := [192,56,12,28,256,384,480,0]
const ENDS := [256,192,28,56,384,480,512,4]
const LIFE_MIN := [.08,.10,.30,.30,.03,.03,.03,.70]
const LIFE_MAX := [.40,.70,1.50,1.50,.15,.15,.15,4.]
var history := History.new()
var bytes := PackedByteArray()
var birth := PackedFloat32Array()
var lifetime := PackedFloat32Array()
var source := PackedInt32Array()
var kind := PackedInt32Array()
var cursors := PackedInt32Array()
var enabled := PackedByteArray()
var activity := PackedFloat32Array()
var phases := PackedFloat32Array()
var bursts := PackedFloat32Array()
var credits := PackedFloat32Array()
var count_by_kind := PackedInt32Array()
var image_buffer: Image
var texture: ImageTexture
var clock := 0.
var serial := 0
var live_count := 0
var births_total := 0
var deaths_total := 0
var trigger_count := 0
var trigger_births := 0
var last_audio_id := -1
var world_age := 0.
var world_seed := 17
var tension := 0.
var surge := 0.
var density := 1.
var palette_override := -1
var dirty := true
var has_state := false
var scene_descriptor: Dictionary = {}
var scene_serial := 0
var scene_transition := 1.
var scene_progress := 0.
var scene_stage := "birth"
var shot_age := 0.
var next_text := 0.
var cut_requested := false
var mutation := 0.
var view_age := 0.
var view_index := 0
var view_serial := 0
var edit_kind := 0
var edit_impulse := 0.
var structure_impulse := 0.
var edit_strength := 0.
var view_polarity := false
var operation := "establish"
var phrase := {"index":0,"start":0.,"end":3.,"kind":"phrase"}
var phrase_index := -1
var graph := SceneGraph.new()
var material_shift := 0.

func _init() -> void:
	bytes.resize(CAPACITY*STRIDE*4)
	birth.resize(CAPACITY); lifetime.resize(CAPACITY); source.resize(CAPACITY)
	kind.resize(CAPACITY); kind.fill(-1); cursors.resize(8)
	enabled.resize(8); enabled.fill(1); count_by_kind.resize(8)
	activity.resize(256); phases.resize(256); bursts.resize(256); credits.resize(256)
	for i in range(CAPACITY): _put(i,0,-1.)
	image_buffer=Image.create_from_data(8,CAPACITY,false,Image.FORMAT_RGBAF,bytes)
	texture=ImageTexture.create_from_image(image_buffer)

static func hash_value(value: float) -> float:
	return fposmod(sin(value*12.9898+78.233)*43758.5453,1.)

func _put(slot: int, column: int, value: float) -> void:
	bytes.encode_float((slot*STRIDE+column)*4,value)

func _retire(slot: int) -> void:
	if kind[slot]<0: return
	count_by_kind[kind[slot]]-=1; kind[slot]=-1
	live_count-=1; deaths_total+=1; _put(slot,0,-1.); dirty=true

func advance(delta: float) -> void:
	clock+=delta; world_age+=delta
	voices.advance(delta)
	editorial.advance(delta)
	surge*=exp(-delta/.09); mutation*=exp(-delta/.1)
	view_age+=delta; edit_impulse*=exp(-delta/.07); structure_impulse*=exp(-delta/.24)
	if not scene_descriptor.is_empty():
		shot_age+=delta
		graph.advance(delta,history.latest_rise,history.latest_synchrony)
		scene_progress=graph.progress
		scene_transition=1.
		scene_stage=SceneGraph.PHASES[graph.phase]
	for slot in range(CAPACITY):
		if kind[slot]>=0 and clock-birth[slot]>=lifetime[slot]: _retire(slot)

func ingest(values: PackedFloat32Array, impulses: PackedFloat32Array, clocks: PackedFloat32Array, neural_bands: Array, timing_events: Array, dt: float) -> void:
	if dt<=0.: return
	has_state=true
	activity=values; bursts=impulses; phases=clocks
	history.observe(values,impulses,neural_bands,timing_events,dt)
	tension=history.latest_load
	if scene_descriptor.is_empty() or (cut_requested and world_age>.18):
		_cut()
	# No persistent screen-wide glitch plane: a neural burst changes the
	# geometry/material of existing objects during a bounded mutation window.
	mutation=maxf(mutation,history.latest_rise*.4)
	var d := scene_descriptor
	var topology := int(d.get("topology",0))
	var chapter_gain := .24 if scene_progress<.12 else (1.0 if scene_progress<.75 else .48)
	var clarity_budget := clampf(.55+float(d.get("layout_density",.5))*.35, .52, .88)
	for i in range(256):
		# The neural population still drives the events, but a quiet cell is not
		# allowed to accumulate a decorative mark indefinitely. This leaves room
		# for a transient to read as a clean musical gesture.
		credits[i]+=dt*(.012+values[i]*.09+impulses[i]*.38)*2.15*density*float(d.get("birth_rate",.6))*chapter_gain*clarity_budget
		if credits[i]>=1.:
			credits[i]-=1.
			var grammar := TRACE if (i%4)==0 else GRAPHIC
			if topology in [3,7] and i%4==0: grammar=DATA
			_spawn_detail(i,grammar,.6+values[i]*.3)
	# Music scenes have no typography; timing continues to drive geometry.
	articulate_events(timing_events)

func articulate_events(timing_events: Array) -> void:
	if scene_descriptor.is_empty(): return
	var d := scene_descriptor
	var topology := int(d.get("topology",0))
	for event in timing_events:
		var id := int(event.get("id",-1))
		if id<=last_audio_id: continue
		last_audio_id=id
		if float(event.get("age_ms",0.))>250.: continue
		trigger_count+=1
		var before := births_total
		var voice := int(event.get("voice",-1))
		voices.articulate(voice,float(event.get("age_ms",0.))/1000.,event.get("neural_sample",[]))
		if voice>=0 and voice<6 and voices.accent[voice]<=.001: continue
		if editorial.articulate(voice,voices,d,history.latest_synchrony):
			view_serial+=1; view_age=0.; view_index=editorial.framing
		var owner := voices.owners[voice] if voice>=0 and voice<6 else _choose_source(trigger_count*53)
		# Every timing event articulates a neural component immediately. Larger
		# editorial operations use a separate cadence inside the same world.
		# Micro percussion acts locally. Phrase/meso cadence owns large edits.
		if voice!=3: edit_impulse=1.
		edit_strength=clampf(.2+history.drives[owner]*.5+bursts[owner]*.3,.2,1.)
		if voice!=3: structure_impulse=maxf(structure_impulse,edit_strength)
		if voice!=3 and view_age>=float(d.get("view_duration",.4)) and world_age>.16:
			view_age=0.; view_serial+=1
			edit_kind=graph.choose_operation(history.drives,bursts,history.latest_synchrony)
			operation=SceneGraph.OPERATIONS[edit_kind]
			if edit_kind==1: view_index=(view_index+1)%4
			if edit_kind==2: material_shift=fmod(material_shift+1.,3.)
			view_polarity=edit_kind==2 and topology in [2,3,5,8,10]
		surge=maxf(surge,.5+bursts[owner]*.5)
		mutation=maxf(mutation,bursts[owner]*.8)
		# The timing path guarantees a visible registration/contour event even
		# when that shot has no typography. Content is still from the owner.
		_spawn_detail(owner,GRAPHIC,1.)
		# One local trace is enough for an ordinary onset. A second mark is
		# reserved for a genuinely strong downstream burst.
		if bursts[owner]>.18:
			_spawn_detail(_choose_source(owner+31),TRACE,.7+bursts[owner]*.3)
		if bursts[owner]>.65:
			_spawn_detail(_choose_source(owner+62),GRAPHIC,.6+bursts[owner]*.25)
		trigger_births+=births_total-before
		# Onsets can accelerate development or land the cut; waveform amplitude
		# never selects geometry. Sharp neural bursts are the early-cut cause.
		# Local edits stay inside the phrase. Only the score may change worlds.

func _cut() -> void:
	scene_descriptor=history.describe(activity,bursts)
	scene_descriptor["phrase_kind"]=phrase.get("kind","phrase")
	scene_descriptor["phrase_index"]=int(phrase.get("index",0))
	scene_descriptor["voice_owners"]=Array(voices.owners)
	scene_descriptor["voice_memory"]=Array(voices.memory)
	scene_descriptor["duration"]=maxf(.1,float(phrase.get("end",3.))-float(phrase.get("start",0.)))
	scene_descriptor["choreography"]=PhraseDesign.compile(scene_descriptor,phrase)
	# A remembered neural phrase may return as a different spatial role.
	scene_descriptor["motif_id"]=voices.motif_id
	scene_descriptor["motif_variant"]=voices.motif_variant
	if voices.motif_variant>0:
		scene_descriptor.graphic_mode=posmod(voices.motif_id,6)
		scene_descriptor.layout_mode=posmod(voices.motif_variant,3)
	graph.initialize(scene_descriptor)
	editorial.establish(scene_descriptor)
	material_shift=0.
	scene_serial+=1; shot_age=0.; world_age=0.; scene_progress=0.; scene_transition=0.
	view_age=0.; view_index=int(scene_descriptor.camera)%2; view_serial+=1
	edit_kind=0; view_polarity=false; operation="establish"
	world_seed=posmod(int(absf(float(scene_descriptor.fingerprint))*100000.)+int(scene_descriptor.topology)*97+int(scene_descriptor.primitive)*53,65521)
	cut_requested=false; next_text=clock+.34
	# Preserve short-lived real spike/trace identities through a world change.
	# The stage also carries its own GPU-rendered view into selected surfaces.
	for slot in range(CAPACITY):
		if kind[slot]>=0 and kind[slot]!=TRACE: _retire(slot)
	for j in range(8):
		_spawn_detail(int(scene_descriptor.owners[j]),GRAPHIC,.75)

func set_phrase(value: Dictionary) -> void:
	var next := int(value.get("index",0))
	if next==phrase_index: return
	phrase=value; phrase_index=next
	voices.new_phrase()
	if not scene_descriptor.is_empty() and world_age>.18:
		cut_requested=true

func _choose_source(seed_value: int) -> int:
	var candidate := posmod(seed_value,256); var best := -1.
	for j in range(12):
		var index := posmod(seed_value+j*53,256)
		var score := activity[index]*.15+history.drives[index]+bursts[index]*.8
		if score>best: best=score; candidate=index
	return candidate

func _spawn_detail(ensemble: int, grammar: int, strength: float) -> void:
	# Budget occupied area, not neural inputs. Detail may be dense at a drop,
	# but the normal frame keeps a small readable vocabulary of marks.
	var cap: int = [14,14,36,18,8,36,6,2][grammar]
	if count_by_kind[grammar]>=cap:
		var oldest := -1; var age := -1.
		for slot in range(STARTS[grammar],ENDS[grammar]):
			if kind[slot]==grammar and clock-birth[slot]>age: age=clock-birth[slot]; oldest=slot
		if oldest>=0: _retire(oldest)
	spawn(ensemble,grammar,strength)

func spawn(ensemble: int, grammar: int, strength: float) -> int:
	if enabled[grammar]==0: return -1
	var start: int=STARTS[grammar]; var end: int=ENDS[grammar]
	var slot := start+cursors[grammar]%(end-start)
	cursors[grammar]+=1; _retire(slot); serial+=1
	var a := activity[ensemble]; var b := bursts[ensemble]; var p := phases[ensemble]
	var r := hash_value(ensemble*17.+p*31.+serial*.71)
	var life := lerpf(LIFE_MIN[grammar],LIFE_MAX[grammar],r)*float(scene_descriptor.get("life_scale",1.))
	life=clampf(life,LIFE_MIN[grammar],LIFE_MAX[grammar])
	var angle := float(scene_descriptor.get("axis_x",1.)+scene_descriptor.get("axis_y",0.))
	var u := float(ensemble%8)/7.; var v := float((ensemble/8)%8)/7.
	var topology := int(scene_descriptor.get("topology",0))
	var x := .1+u*.8; var y := .15+v*.68
	if topology in [3,4,6,8,12,13]:
		var theta := u*TAU
		x=.50+cos(theta)*(.16+v*.30); y=.50+sin(theta)*(.10+v*.30)
	elif topology in [0,1,9,10]:
		x=.09+float(ensemble%6)*.165; y=.14+float((ensemble/6)%5)*.17
	var sx := .025+r*.07; var sy := .015+a*.035
	var contrast := .85
	match grammar:
		TYPE:
			sx=.24 if int(scene_descriptor.get("text",1))==1 else .62
			sy=.042 if sx<.3 else .16
			x=.24 if sx<.3 else .49; y=.76 if sx<.3 else .5
			life=.34; angle=float(scene_descriptor.get("text_angle",0.))
		GRAPHIC:
			sx=.045+r*.15; sy=.025+r*.12
			if topology in [0,10]: sx*=1.8; sy*=1.8
		DATA: sx=.052; sy=.012
		TRACE: sx=.04+r*.11; sy=.014+b*.02
		SPATIAL,CHROME: sx=.12+r*.12; sy=sx
		GLITCH: sx=.02; sy=.01
		WORLD: x=.5; y=.5; sx=1.; sy=1.
	birth[slot]=clock; lifetime[slot]=life; source[slot]=ensemble; kind[slot]=grammar
	count_by_kind[grammar]+=1; live_count+=1; births_total+=1
	_put(slot,0,grammar); _put(slot,1,ensemble); _put(slot,2,clock); _put(slot,3,life)
	_put(slot,4,x); _put(slot,5,y); _put(slot,6,sx); _put(slot,7,sy)
	_put(slot,8,float(scene_descriptor.get("axis_x",1.))*.04); _put(slot,9,float(scene_descriptor.get("axis_y",0.))*.04)
	_put(slot,10,.9); _put(slot,11,angle*.05 if grammar!=TYPE else angle)
	_put(slot,12,strength); _put(slot,13,r)
	_put(slot,14,0. if ensemble%5!=0 else 1.)
	_put(slot,15,posmod(ensemble+int(p),8))
	_put(slot,16,a); _put(slot,17,b); _put(slot,18,p); _put(slot,19,contrast)
	_put(slot,20,posmod(ensemble,32)); _put(slot,21,serial); _put(slot,22,world_seed); _put(slot,23,-1.)
	dirty=true
	return slot

func upload() -> void:
	if not dirty: return
	image_buffer.set_data(8,CAPACITY,false,Image.FORMAT_RGBAF,bytes)
	texture.update(image_buffer); dirty=false

func toggle_grammar(index: int) -> void:
	enabled[index]=1-enabled[index]
	if enabled[index]==0:
		for slot in range(STARTS[index],ENDS[index]): _retire(slot)
