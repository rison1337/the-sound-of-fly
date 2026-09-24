extends RefCounted
const PhraseDesign=preload("res://scripts/phrase_design.gd")
## Topologically ordered, preallocated transform graph. Each node is a real
## rendered part. Children inherit the animated transform of their parent.
const CAPACITY := 320
enum Relation { ATTACHED, EXTRUDED, CLIPPED, FRAMES, AXIS, INSTANCE }
const RELATIONS := ["attached_to","extruded_from","clipped_by","frames","shares_vanishing_axis","instance_of"]
const OPERATIONS := ["zoom","cut","material_swap","aperture","camera_plunge","destruction"]
const PHASES := ["birth","build","camera move","transformation","breakdown","transition"]
var parents := PackedInt32Array()
var relations := PackedInt32Array()
var owners := PackedInt32Array()
var base: Array[Transform3D] = []
var resolved: Array[Transform3D] = []
var count := 0
var descriptor: Dictionary = {}
var age := 0.
var progress := 0.
var phase := 0
var build_amount := 0.
var travel := 0.
var unfold := 0.
var breakdown := 0.
var exit_amount := 0.
var operation_ages := PackedFloat32Array()
var scores := PackedFloat32Array()
var last_operation := -1

func _init() -> void:
	parents.resize(CAPACITY); relations.resize(CAPACITY); owners.resize(CAPACITY)
	base.resize(CAPACITY); resolved.resize(CAPACITY)
	operation_ages.resize(6); scores.resize(6); operation_ages.fill(10.)

func initialize(d: Dictionary) -> void:
	descriptor=d
	count=0; age=0.; progress=0.; phase=0
	build_amount=0.; travel=0.; unfold=0.; breakdown=0.; exit_amount=0.

func add(owner: int, parent: int, relation: int) -> int:
	assert(count<CAPACITY and parent<count)
	var id := count; count+=1
	owners[id]=owner; parents[id]=parent; relations[id]=relation
	base[id]=Transform3D.IDENTITY; resolved[id]=Transform3D.IDENTITY
	return id

func resolve(id: int, grammar_pose: Transform3D, local_action: Transform3D) -> Transform3D:
	base[id]=grammar_pose
	# Rotate the local domain BEFORE its anisotropic size is applied. S*R made
	# round attachments shear into thin serps when their parent was a flat panel.
	var oriented := grammar_pose.basis.orthonormalized()*local_action.basis*Basis.from_scale(grammar_pose.basis.get_scale())
	var acted := Transform3D(oriented,grammar_pose*local_action.origin)
	var parent := parents[id]
	if parent<0:
		resolved[id]=acted
	else:
		var relative := base[parent].affine_inverse()*acted
		resolved[id]=resolved[parent]*relative
	return resolved[id]

func advance(dt: float, burst: float, coactivity: float) -> void:
	# Scored attack windows own the phase clock; downstream state owns its
	# movement plan. A new onset does not reset or reverse the construction.
	age+=dt
	progress=clampf(age/maxf(.1,float(descriptor.get("duration",3.))),0.,1.)
	var scored := PhraseDesign.stage_time(progress,descriptor.get("choreography",{}))
	phase=0 if scored<.25 else (1 if scored<1. else (2 if scored<2. else (3 if scored<3.3 else (4 if scored<4.4 else 5))))
	build_amount=smoothstep(0.,1.,scored)
	travel=smoothstep(1.,4.,scored)
	unfold=smoothstep(1.3,3.2,scored)
	breakdown=smoothstep(3.3,5.,scored)
	exit_amount=smoothstep(4.,5.,scored)
	for i in range(6): operation_ages[i]+=dt

func choose_operation(drives: PackedFloat32Array, bursts: PackedFloat32Array, coactivity: float) -> int:
	var roles: Dictionary=descriptor.neural_roles
	var camera_id := int(roles.camera); var depth_id := int(roles.depth)
	var material_id := int(roles.material); var deform_id := int(roles.deformation)
	var cut_id := int(roles.cut)
	scores[0]=drives[camera_id]*.7+bursts[camera_id]*1.5+float(descriptor.low)*.25
	scores[1]=drives[cut_id]*.55+bursts[cut_id]*2.+float(descriptor.high)*.2
	scores[2]=drives[material_id]*.7+bursts[material_id]*1.6+float(descriptor.mid)*.25
	scores[3]=drives[deform_id]*.6+bursts[deform_id]*1.6+coactivity*.25
	scores[4]=drives[depth_id]*.7+bursts[depth_id]*1.8+float(descriptor.low)*.25
	scores[5]=drives[cut_id]*.3+bursts[deform_id]*2.+coactivity*.4
	var selected := 0
	for i in range(6):
		scores[i]-=maxf(0.,1.-operation_ages[i]/2.)*1.2
		if i==last_operation: scores[i]-=.55
		if i>0 and scores[i]>scores[selected]: selected=i
	operation_ages[selected]=0.; last_operation=selected
	return selected

func metadata() -> Dictionary:
	var nodes: Array=[]
	for i in range(count):
		nodes.append({"part":i,"parent":parents[i],"relation":RELATIONS[relations[i]],"owner":owners[i]})
	return {"nodes":nodes,"count":count,"phase":PHASES[phase]}
