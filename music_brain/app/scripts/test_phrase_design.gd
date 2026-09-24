extends SceneTree
const Design=preload("res://scripts/phrase_design.gd")
const Graph=preload("res://scripts/scene_graph.gd")
const History=preload("res://scripts/scene_history.gd")
var failures := 0
func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)
func _initialize() -> void:
	var phrase := {"start":10.,"end":14.}
	var attacks: Array=[]
	for time in [10.72,11.84,12.92,13.60]:
		attacks.append({"time":time,"voice":1,"neural_sample":[.8,.7,.5,0.]})
	var score := Design.score(phrase,attacks)
	for i in range(4):
		check(absf(float(score.cues[i+1])-(float(attacks[i].time)-10.)/4.)<.00001,"Stage missed its scored attack")
	var shifted: Array=attacks.duplicate(true)
	for event in shifted: event.time+=.04
	var later := Design.score(phrase,shifted)
	check(score.response==later.response,"Timing contaminated downstream response")
	check(score.cues!=later.cues,"Different musical timing produced identical cue times")
	var quiet: Array=attacks.duplicate(true)
	for event in quiet: event.neural_sample=[0.,0.,0.,0.]
	check(Design.score(phrase,quiet).response==[0.,0.,0.,0.,0.,0.],"Audio was substituted for a silent readout")
	var history=History.new()
	var values := PackedFloat32Array(); values.resize(256); values.fill(.3)
	var bursts := PackedFloat32Array(); bursts.resize(256)
	for i in range(160): history.observe(values,bursts,[.2,.3,.5,.6,.5,.4,.3,.2,.2,.1,.1,.2,.3,.2,.1,.1],[],.025)
	var d: Dictionary=history.describe(values,bursts)
	d.choreography=Design.compile(d,{"design_score":score})
	var unvoiced := d.duplicate(true)
	var empty_plan := Design.compile(unvoiced,{})
	unvoiced.voice_memory=[0.,.9,0.,0.,0.,.7]
	var held_plan := Design.compile(unvoiced,{})
	check(float(held_plan.depth)>float(empty_plan.depth)+.3,"Sustained neural bass was lost without attacks")
	check(float(held_plan.response[1])==.9,"Continuous response is not the recorded neural memory")
	for family in range(12):
		d.topology=family
		var a:=Design.group_action(d,0,.10); var b:=Design.group_action(d,0,.64)
		check(not a.is_equal_approx(b),"Static construction at topology %d"%family)
		var last := a
		for i in range(11,100):
			var pose := Design.group_action(d,0,float(i)/100.)
			check(pose.basis.determinant()>.05,"Singular pose during phrase")
			check(pose.origin.distance_to(last.origin)<.16,"Discontinuous phrase motion")
			last=pose
	# A rotated thin parent must not squeeze a circular child into an ellipse.
	var graph=Graph.new(); graph.add(0,-1,0); graph.add(1,0,0)
	var panel := Transform3D(Basis.from_scale(Vector3(3.,2.,.1)),Vector3.ZERO)
	var turn := Transform3D(Basis.from_euler(Vector3(.35,.6,.25)),Vector3.ZERO)
	graph.resolve(0,panel,turn)
	var child := graph.resolve(1,Transform3D(Basis.IDENTITY,Vector3(0.,0.,1.)),Transform3D.IDENTITY)
	check(child.basis.get_scale().is_equal_approx(Vector3.ONE),"Parent's nonuniform scale sheared attached sculpture")
	check(absf(child.basis.x.dot(child.basis.y))<.00001,"Nonorthogonal child axes")
	print("PHRASE_DESIGN failures=",failures)
	quit(0 if failures==0 else 1)
