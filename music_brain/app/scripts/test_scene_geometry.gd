extends SceneTree
const History=preload("res://scripts/scene_history.gd")
const Graph=preload("res://scripts/scene_graph.gd")
const Stage=preload("res://scripts/spatial_stage.gd")
const Layout=preload("res://scripts/assembly_layout.gd")
const Design=preload("res://scripts/phrase_design.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1; push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# A child's world pose must inherit the parent's rotation and translation;
	# an absolute child pose must not accidentally apply the parent twice.
	var graph=Graph.new()
	graph.add(0,-1,Graph.Relation.ATTACHED); graph.add(1,0,Graph.Relation.EXTRUDED)
	var parent_base := Transform3D(Basis.IDENTITY,Vector3(2,0,0))
	var parent_action := Transform3D(Basis(Vector3.FORWARD,PI*.5),Vector3(0,1,0))
	graph.resolve(0,parent_base,parent_action)
	var child := graph.resolve(1,Transform3D(Basis.IDENTITY,Vector3(3,0,0)),Transform3D.IDENTITY)
	check(child.origin.is_equal_approx(graph.resolved[0]*Vector3(1,0,0)),"Child did not inherit parent transform")
	var history=History.new()
	var values := PackedFloat32Array(); values.resize(256); values.fill(.2)
	var bursts := PackedFloat32Array(); bursts.resize(256)
	var bands: Array=[]; bands.resize(16); bands.fill(.3)
	for i in range(200): history.observe(values,bursts,bands,[],.025)
	var d: Dictionary=history.describe(values,bursts)
	d.choreography=Design.compile(d,{})
	# Exercise the maximum recorded-response envelope, including sustained bass.
	d.choreography.depth=1.; d.choreography.amplitude=.85
	var stage=Stage.new(); root.add_child(stage)
	# Check every grammar, not just the few naturally selected in a 10s clip.
	# Smooth shader domains are bounded without clipping vertices. Parent/child
	# contacts are intentional; separate root assemblies require clear space.
	for family in range(12):
		d=d.duplicate(true); d.id=family; d.topology=family; d.name=str(family)
		graph=Graph.new(); graph.initialize(d); stage.configure(d,graph)
		check(stage.part_count>0 and stage.part_count==graph.count,"Missing render parts for family %s"%family)
		if family in [3,5,9,10]: check(stage.counts[2]==0,"Floating box debris returned")
		for development in [0.,.15,.35,.55,.75,.95,1.]:
			var bounds: Array[AABB]=[]; var ids: Array[int]=[]
			for i in range(stage.part_count):
				check(graph.parents[i]<i,"Graph is not topologically ordered")
				if graph.parents[i]>=0: continue
				var kind: int=stage.part_kind[i]
				var pose := Layout.pose(d,kind,stage.part_group[i],stage.part_order[i],development,1.)
				pose=graph.resolve(i,pose,Design.group_action(d,stage.part_group[i],development))
				# Reserve worst-case bounded neural translations and local turns,
				# not just the unanimated base transform.
				var extents := Vector3(.985,.985,1.06)
				if kind==2: extents=Vector3.ONE*.5
				elif kind==1: extents=Vector3(.85,.85,.50)
				elif kind==4: extents=Vector3.ONE*1.15
				var bound := pose*AABB(-extents,extents*2.)
				for j in range(bounds.size()):
					check(not bound.intersects(bounds[j]),"Reserved root volumes overlap: family=%s parts=%s,%s phase=%s"%[family,i,ids[j],development])
				bounds.append(bound); ids.append(i)
	stage.queue_free()
	print("SCENE_GEOMETRY failures=",failures)
	quit(0 if failures==0 else 1)
