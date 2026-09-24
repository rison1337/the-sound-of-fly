extends SceneTree
const History=preload("res://scripts/scene_history.gd")
const Pool=preload("res://scripts/visual_events.gd")
const Graph=preload("res://scripts/scene_graph.gd")

func _initialize() -> void:
	var bass=History.new(); var treble=History.new(); var reversed=History.new()
	var values := PackedFloat32Array(); values.resize(256); values.fill(.2)
	var bursts := PackedFloat32Array(); bursts.resize(256)
	for sample in range(160):
		var low: Array=[]; var high: Array=[]; var reverse: Array=[]
		for b in range(16):
			var increase := float(sample)/160.
			low.append((.15+increase*.6) if b<5 else .04)
			high.append((.15+increase*.6) if b>10 else .04)
			reverse.append((.15+(1.-increase)*.6) if b<5 else .04)
		var timing: Array=[{"id":sample/20,"age_ms":0}] if sample%20==0 else []
		bass.observe(values,bursts,low,timing,.025)
		treble.observe(values,bursts,high,timing,.025)
		reversed.observe(values,bursts,reverse,timing,.025)
	var a: Dictionary=bass.describe(values,bursts)
	var b: Dictionary=treble.describe(values,bursts)
	var c: Dictionary=reversed.describe(values,bursts)
	assert(is_equal_approx(float(a.rhythm_density),float(b.rhythm_density)))
	assert(absf(float(a.fov)-float(b.fov))>5.)
	assert(a.profile!=b.profile and a.trajectory.size()==64)
	assert(float(a.trend)>0. and float(c.trend)<0.)
	assert(a.trajectory!=c.trajectory)
	# A world survives several independent, deduplicated audio articulations.
	var pool=Pool.new(); var phases := PackedFloat32Array(); phases.resize(256)
	var bands: Array=[]; bands.resize(16); bands.fill(.3)
	pool.ingest(values,bursts,phases,bands,[],.025)
	var identity: int=pool.scene_descriptor.id
	var trajectory: Array=pool.scene_descriptor.trajectory.duplicate()
	for i in range(1,5):
		pool.advance(.4)
		pool.ingest(values,bursts,phases,bands,[{"id":i,"age_ms":0}],.025)
	assert(pool.scene_descriptor.id==identity and pool.view_serial>1)
	assert(pool.scene_descriptor.trajectory==trajectory and pool.trigger_count==4)
	# True bounded detail budget even when the next circular slot was empty.
	for i in range(80): pool._spawn_detail(i,Pool.GRAPHIC,.8)
	assert(pool.count_by_kind[Pool.GRAPHIC]<=24)
	var graph=Graph.new(); graph.initialize(a)
	var root:=graph.add(0,-1,0); graph.add(1,root,1); graph.add(2,root,3)
	assert(graph.count==int(graph.metadata().count))
	assert(graph.metadata().phase=="birth")
	var saw_relation := false
	for node in graph.metadata().nodes:
		if node.relation in ["extruded_from","attached_to","frames"]: saw_relation=true
	assert(saw_relation)
	graph.advance(1.2, .8, .7)
	assert(graph.phase>=1 and graph.build_amount>0.)
	print("SCENE_HISTORY_OK musical morphology / temporal order / world continuity / editorial timing / detail budget")
	quit()
