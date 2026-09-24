extends TextureRect
## Connected neural assemblies. Five pooled parametric domains, GPU history
## views and camera segments replace the independent primitive carousel.
const MeshDomains=preload("res://scripts/assembly_meshes.gd")
const Layout=preload("res://scripts/assembly_layout.gd")
const PhraseDesign=preload("res://scripts/phrase_design.gd")
const MAX_PARTS := 320
const BATCH_CAPACITY := 192
var viewport: SubViewport
var camera: Camera3D
var root3d: Node3D
var assembly: Node3D
var batches: Array[MultiMesh]=[]
var materials: Array[ShaderMaterial]=[]
var counts := PackedInt32Array()
var part_kind := PackedInt32Array()
var part_slot := PackedInt32Array()
var part_group := PackedInt32Array()
var part_order := PackedInt32Array()
var group_roots := PackedInt32Array()
var surface_identity: Array[Color]=[]
var graph: RefCounted
var owner_ids := PackedInt32Array()
var positions := PackedVector3Array()
var directions_u := PackedVector3Array()
var directions_v := PackedVector3Array()
var part_count := 0
var descriptor: Dictionary={}
var current_id := -1
var last_clock := 0.
var progress := 0.
var camera_position := Vector3(0,0,14)
var camera_target := Vector3.ZERO
var camera_roll := 0.
var last_view := -1
var drive := PackedFloat32Array()
var transition_material := ShaderMaterial.new()
var shape_pixels := PackedFloat32Array()
var shape_image: Image
var shape_texture: ImageTexture
var anchor_texture: ImageTexture
var anchor_image: Image
var anchor_pixels := PackedFloat32Array()
var anchor_owner := PackedInt32Array()
var anchor_clock := 0.
var memories: Array[SubViewport]=[]
var memory_backgrounds: Array[ColorRect]=[]
var memory_read := 0
var memory_valid := false
var memory_busy := false
var memory_world := -1
var neural_texture: Texture2D
var cell_lookup_texture: ImageTexture
var cell_lookup_image: Image
var cell_lookup_pixels := PackedFloat32Array()
var neural_width := 512
var neural_height := 323
var panel_mesh: Mesh
var frame_mesh: Mesh

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	stretch_mode=TextureRect.STRETCH_SCALE; expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport=SubViewport.new(); viewport.size=Vector2i(1440,900)
	viewport.transparent_bg=true; viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	add_child(viewport); texture=viewport.get_texture()
	transition_material.shader=preload("res://shaders/transition.gdshader"); material=transition_material
	root3d=Node3D.new(); viewport.add_child(root3d)
	assembly=Node3D.new(); root3d.add_child(assembly)
	camera=Camera3D.new(); camera.near=.08; camera.far=180.
	camera.position=camera_position; root3d.add_child(camera)
	var environment := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color.TRANSPARENT
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment.environment=env; root3d.add_child(environment)
	counts.resize(5); part_kind.resize(MAX_PARTS); part_slot.resize(MAX_PARTS)
	part_group.resize(MAX_PARTS); part_order.resize(MAX_PARTS); owner_ids.resize(MAX_PARTS)
	group_roots.resize(32); group_roots.fill(-1); surface_identity.resize(MAX_PARTS)
	positions.resize(MAX_PARTS); directions_u.resize(MAX_PARTS); directions_v.resize(MAX_PARTS); drive.resize(256)
	shape_pixels.resize(16*4*4)
	shape_image=Image.create_from_data(16,4,false,Image.FORMAT_RGBAF,shape_pixels.to_byte_array())
	shape_texture=ImageTexture.create_from_image(shape_image)
	var domains := MeshDomains.create()
	panel_mesh=domains[0]; frame_mesh=MeshDomains.panel(true)
	for i in range(5):
		var mat := ShaderMaterial.new(); mat.shader=preload("res://shaders/assembly.gdshader")
		mat.set_shader_parameter("shape_kind",float(i)); mat.set_shader_parameter("trajectory",shape_texture)
		materials.append(mat)
		var mesh := MultiMesh.new(); mesh.transform_format=MultiMesh.TRANSFORM_3D
		mesh.use_custom_data=true; mesh.mesh=domains[i]
		mesh.instance_count=BATCH_CAPACITY; mesh.visible_instance_count=0
		mesh.custom_aabb=AABB(Vector3(-100,-100,-150),Vector3(200,200,300))
		var node := MultiMeshInstance3D.new(); node.multimesh=mesh; node.material_override=mat
		assembly.add_child(node); batches.append(mesh)
	anchor_pixels.resize(512*4); anchor_owner.resize(256)
	anchor_image=Image.create_from_data(16,32,false,Image.FORMAT_RGBAF,anchor_pixels.to_byte_array())
	anchor_texture=ImageTexture.create_from_image(anchor_image)
	# Two GPU targets. The stage samples only the disabled read target while
	# the other target copies the stage. No same-target read/write feedback.
	for i in range(2):
		var memory := SubViewport.new(); memory.size=Vector2i(960,600)
		memory.disable_3d=true; memory.render_target_update_mode=SubViewport.UPDATE_DISABLED
		add_child(memory); memories.append(memory)
		var bg := ColorRect.new(); bg.size=Vector2(960,600); memory.add_child(bg)
		memory_backgrounds.append(bg)
		var view := TextureRect.new(); view.texture=viewport.get_texture()
		view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; view.size=Vector2(960,600)
		memory.add_child(view)
	for mat in materials: mat.set_shader_parameter("memory_view",memories[0].get_texture())
	call_deferred("_prewarm")

func configure_neural(value: Texture2D) -> void:
	neural_texture=value
	for mat in materials: mat.set_shader_parameter("populations",value)

func configure_voices(value: Texture2D) -> void:
	for mat in materials: mat.set_shader_parameter("voices",value)

func configure_cells(value: Texture2D) -> void:
	for mat in materials:
		mat.set_shader_parameter("cell_states",value)
		mat.set_shader_parameter("cells_ready",1. if cell_lookup_texture!=null else 0.)

func set_cell_age(value: float) -> void:
	for mat in materials: mat.set_shader_parameter("between_frames",value)

func configure_ensemble_map(value: Texture2D) -> void:
	# Select 32 evenly spaced real cell identities from each ensemble once.
	# Bounded geometry probes complement the complete GPU spike renderer.
	var image := value.get_image()
	if image==null: return
	var data := image.get_data(); var total := data.size()
	if total<1: return
	neural_height=image.get_height()
	var members: Array[PackedInt32Array]=[]; members.resize(256)
	for cell in range(mini(total,165122)): members[int(data[cell])].append(cell)
	cell_lookup_pixels.resize(256*32*4); cell_lookup_pixels.fill(0.)
	for group in range(256):
		for slot in range(32):
			var k := (group*32+slot)*4
			if not members[group].is_empty():
				var cell := members[group][mini(members[group].size()-1,int(float(slot)*members[group].size()/32.))]
				cell_lookup_pixels[k]= (float(cell%neural_width)+.5)/float(neural_width)
				cell_lookup_pixels[k+1]=(float(cell/neural_width)+.5)/float(neural_height)
				cell_lookup_pixels[k+2]=1.
	cell_lookup_image=Image.create_from_data(32,256,false,Image.FORMAT_RGBAF,cell_lookup_pixels.to_byte_array())
	cell_lookup_texture=ImageTexture.create_from_image(cell_lookup_image)
	for mat in materials:
		mat.set_shader_parameter("cell_lookup",cell_lookup_texture)

func _prewarm() -> void:
	if current_id>=0: return
	for mesh in batches:
		mesh.visible_instance_count=1
		mesh.set_instance_transform(0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.001),Vector3(0,0,-2)))
	await RenderingServer.frame_post_draw
	if current_id<0:
		for mesh in batches: mesh.visible_instance_count=0

func _part(kind: int, role: int, group: int, order: int) -> void:
	if part_count>=MAX_PARTS or counts[kind]>=BATCH_CAPACITY: return
	# Thin coplanar line meshes produced ragged borders under perspective.
	# A closed panel already has a real edge; event ink lives in its material.
	if kind==3: return
	# In orbital and sculptural grammars the old tiny box meshes had no visual
	# attachment. Percussion is already carried by the parent surface and voices.
	if kind==2 and int(descriptor.topology) in [3,5,9,10]: return
	var parent := group_roots[group]
	# The printed surface already owns its graphic structure. Additional black
	# bars across it looked like unrelated objects slicing through the artwork.
	if kind==2 and parent>=0 and part_kind[parent]==0: return
	# Line domains are valid only on an actual parent surface. Inheriting its
	# transform AND shader identity keeps folds and contour lines coincident.
	if kind==3 and (parent<0 or part_kind[parent]!=0): return
	var i := part_count; var slot := counts[kind]
	var owner := int(descriptor.owners[posmod(group*3+order,descriptor.owners.size())])
	# Tonal parts hold the construction; percussion owns nodes/seams/details.
	# Voice identity persists inside a phrase and is inherited by surface lines.
	var musical_role: int=[1,4,5][group%3] if order==0 else [0,2,3][(order+group)%3]
	if descriptor.has("voice_owners"): owner=int(descriptor.voice_owners[musical_role])
	if kind==3: owner=owner_ids[parent]
	part_kind[i]=kind; part_slot[i]=slot; part_group[i]=group; part_order[i]=order; owner_ids[i]=owner
	var shape := float(descriptor.profile[posmod(group*5+order,16)])
	var identity := Color(float(owner),float(role),shape,float(musical_role)+fposmod(float(group)*.47+float(order)*.09,1.)*.99)
	if kind==3: identity=surface_identity[parent]; identity.g=0.
	surface_identity[i]=identity
	batches[kind].set_instance_custom_data(slot,identity)
	var relation := 3 if kind==3 else (1 if kind==2 else (2 if role>=4 else 0))
	if int(descriptor.topology) in [2,8]: relation=4
	if int(descriptor.topology)==11: relation=5
	graph.add(owner,parent,relation)
	if parent<0: group_roots[group]=i
	part_count+=1; counts[kind]+=1

func configure(d: Dictionary, runtime_graph: RefCounted) -> void:
	var started := Time.get_ticks_usec()
	descriptor=d; graph=runtime_graph; current_id=int(d.id); part_count=0; counts.fill(0); last_view=-1
	batches[0].mesh=frame_mesh if int(d.topology)==11 else panel_mesh
	group_roots.fill(-1)
	for t in range(4):
		for b in range(16):
			shape_pixels[(t*16+b)*4]=float(d.trajectory[t*16+b])
	shape_image.set_data(16,4,false,Image.FORMAT_RGBAF,shape_pixels.to_byte_array()); shape_texture.update(shape_image)
	var groups := int(d.branches); var subdivisions := int(d.columns)
	match int(d.topology):
		0: # Shared panels, their surface linework, hinges and connecting contours.
			for g in range(groups):
				_part(0,[1,2,4,1,4][g%5],g,0)
				if g%2==0: _part(3,0,g,1)
				if g in [0,2]: _part(1,3 if g==0 else 2,g,2)
				for j in range(4): _part(2,0,g,3+j)
				if g==groups/2: _part(4,3,g,7)
		1: # Folded relief: common sheets, ribs following the same folded surface.
			for g in range(3):
				_part(0,3 if g!=1 else 2,g,0); _part(3,0,g,1)
				for j in range(subdivisions*2): _part(0,0 if j%4 else 1,g,j+2)
		2: # Extruded architecture around a real shared vanishing axis.
			for g in range(groups+2):
				for j in range(12): _part(2,[1,0,3,1][j%4],g,j)
			for g in range(3): _part(1,2 if g==0 else 0,g,20)
		3: # A continuous scaffold with articulated orbital levels.
			for g in range(groups):
				_part(1,2 if g%4==0 else 1,g,0); _part(3,1,g,1)
				_part(4,3,g,2)
				for j in range(5): _part(2,1,g,3+j)
		4: # Clipped panels share a construction, then separate into spatial slabs.
			for g in range(groups+2):
				_part(0,[4,2,1,4,1][g%5],g,0); _part(3,0,g,1)
				if g==groups/2: _part(4,3,g,2)
				for j in range(4): _part(2,0,g,j+3)
		5: # Persistent aperture, rapid internal view turnover, contour ribs.
			# The centre and each orbital level share an axis, not a parent pivot
			# several metres behind them (which swept the front ring off screen).
			_part(0,4,groups+3,0)
			for g in range(groups+3):
				_part(1,2 if g%3==0 else 3,g,1)
				_part(3,0,g,2)
				for j in range(3): _part(2,0,g,3+j)
		6: # One braided macro surface assembled from related strips.
			for g in range(groups):
				for j in range(subdivisions): _part(1,3 if j%4 else 2,g,j)
				_part(0,1,g,20); _part(3,0,g,21)
		7: # Previous world framed by a new articulated physical assembly.
			for g in range(4):
				_part(0,5 if g==0 else (4 if g==1 else 2),g,0); _part(3,1,g,1)
				for j in range(4): _part(2,1,g,j+2)
		8: # Panel tunnel: repeated slabs share a vanishing axis but keep local frames.
			for g in range(groups*4):
				_part(0,1 if g%3 else 2,g,0); _part(3,0,g,1)
		9: # Cutout collage: opaque cut panels and a few clipped apertures.
			for g in range(6):
				_part(0,1 if g%2 else 4,g,0); _part(3,0,g,1)
				_part(4,2,g,2)
				if g%2==0: _part(2,3,g,3)
		10: # Neural volume: a bounded field of shells, ribs and solids.
			for g in range(groups+4):
				# Only two sculptural anchors; the rest are slabs/cut panels so the
				# scene reads as an authored spatial collage, not repeated bubbles.
				if g in [0,4]: _part(4,3,g,0)
				else: _part(0,4 if g%2 else 2,g,0)
				if g%2==0: _part(1,3,g,1)
				if g%3==1: _part(0,4,g,20)
				# One local detail is enough to explain the active surface. A second
				# detail appears only on every third anchor, keeping the assembly
				# readable during sustained sections.
				_part(2,1,g,3)
				if g%3==0: _part(2,0,g,4)
		11: # Nested screens: framed planes recursively attached along depth.
			for g in range(mini(8,groups+3)):
				_part(0,5 if g==1 else (4 if g%2 else 1),g,0); _part(3,0,g,1)
	for k in range(5): batches[k].visible_instance_count=counts[k]
	var representatives := PackedInt32Array(); representatives.resize(256); representatives.fill(-1)
	var sources: Array[int]=[]
	for j in range(part_count):
		if representatives[owner_ids[j]]<0:
			representatives[owner_ids[j]]=j; sources.append(owner_ids[j])
	for i in range(256):
		var best := 1e9; var nearest := 0
		var point := Vector3(i%8,(i/8)%8,i/64)
		for owner in sources:
			var distance := point.distance_squared_to(Vector3(owner%8,(owner/8)%8,owner/64))
			if distance<best: best=distance; nearest=representatives[owner]
		anchor_owner[i]=nearest
	var cost_ms := float(Time.get_ticks_usec()-started)/1000.
	if cost_ms>8.: print("ASSEMBLY_CONFIG ms=",cost_ms," parts=",part_count," world=",d.name)

func _record_view(background: int, palette_id: int, inverted: bool) -> void:
	if memory_busy: return
	memory_busy=true; memory_world=current_id
	var write := 1-memory_read
	var paper := Color(.935,.94,.918); var ink := Color(.023,.028,.036)
	var accent: Color=[Color(.39,.27,.96),Color(.08,.27,.97),Color(.70,.96,.14),Color(.97,.18,.095)][palette_id%4]
	var light := background==1
	if inverted: light=not light
	memory_backgrounds[write].color=(paper if light else ink) if background!=2 else accent
	memories[write].render_target_update_mode=SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	# UPDATE_ONCE becomes disabled before this target is read by the stage.
	memories[write].render_target_update_mode=SubViewport.UPDATE_DISABLED
	memory_read=write; memory_valid=true
	for mat in materials:
		mat.set_shader_parameter("memory_view",memories[memory_read].get_texture())
		mat.set_shader_parameter("memory_valid",1.)
	memory_busy=false

func update_scene(pool, view_size: Vector2, populations: PackedFloat32Array, impulses: PackedFloat32Array, phases: PackedFloat32Array) -> void:
	if pool.scene_descriptor.is_empty(): return
	if current_id!=int(pool.scene_descriptor.id): configure(pool.scene_descriptor,pool.graph)
	var d := descriptor; var family := int(d.topology)
	var dt := clampf(pool.clock-last_clock,0.,.06); last_clock=pool.clock
	progress=pool.scene_progress
	var develop: float=graph.travel
	var unfold: float=clampf(graph.unfold+pool.structure_impulse*.20,0.,1.)
	var palette_id := int(d.palette) if pool.palette_override<0 else int(pool.palette_override)
	for i in range(256): drive[i]=lerpf(drive[i],pool.history.drives[i],1.-exp(-dt/.025))
	var roles: Dictionary=d.neural_roles
	var camera_response: float=drive[int(roles.camera)]*.3+impulses[int(roles.camera)]*1.6
	var depth_response: float=drive[int(roles.depth)]*.3+impulses[int(roles.depth)]*1.5
	var material_response: float=impulses[int(roles.material)]
	var deformation_response: float=impulses[int(roles.deformation)]
	var bass_voice: float=pool.voices.motion[1]
	var lead_voice: float=pool.voices.motion[4]
	for mat in materials:
		mat.set_shader_parameter("family",float(family)); mat.set_shader_parameter("palette",float(palette_id))
		mat.set_shader_parameter("contour_mode",float(d.primitive))
		mat.set_shader_parameter("silhouette",float(d.get("silhouette",.5)))
		mat.set_shader_parameter("section_count",float(d.get("section_count",5)))
		mat.set_shader_parameter("graphic_mode",float(d.get("graphic_mode",0)))
		mat.set_shader_parameter("development",develop); mat.set_shader_parameter("fold",float(d.fold)*unfold)
		mat.set_shader_parameter("articulation",pool.edit_impulse)
		mat.set_shader_parameter("mutation",pool.mutation if pool.enabled[6] else 0.)
		mat.set_shader_parameter("polarity",1. if pool.view_polarity else 0.)
		mat.set_shader_parameter("turnover",float(pool.view_serial)+pool.structure_impulse)
		mat.set_shader_parameter("material_shift",pool.material_shift)
		mat.set_shader_parameter("material_response",material_response)
		mat.set_shader_parameter("deformation_response",deformation_response)
		mat.set_shader_parameter("aperture_action",pool.structure_impulse if pool.edit_kind==3 else 0.)
		mat.set_shader_parameter("destruction",maxf(graph.breakdown*.5,pool.structure_impulse if pool.edit_kind==5 else 0.))
	if viewport.size!=Vector2i(view_size): viewport.size=Vector2i(view_size)
	var framing: int=pool.view_index%4
	# Do not switch projection halfway through a phrase: that used to snap the
	# size of every surface at once. Front-on poses provide the planar views.
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	var target := Vector3(float(d.offset_x),float(d.offset_y),-2.)
	var camera_goal := Vector3(0,0,13.)
	var roll := 0.
	match family:
		0:
			camera_goal=[Vector3(0,0,14),Vector3(-4,1.2,10),Vector3(3,-.8,7),Vector3(0,2,16)][framing]
			camera_goal.z-=develop*2.; roll=float(d.axis_x)*.12*develop
		1:
			camera_goal=[Vector3(0,0,11),Vector3(-5,1,7),Vector3(2,1,4.5),Vector3(0,-3,9)][framing]
			roll=.17*float(d.axis_y)
		2:
			camera_goal=Vector3(float(d.axis_x)*.5,float(d.axis_y)*.3,8.-develop*10.)
			target=Vector3(float(d.offset_x)*.4,0,camera_goal.z-24.)
			camera_goal.x+=sin(develop*TAU+float(d.axis_x))*1.4
			camera_goal.y+=cos(develop*TAU+float(d.axis_y))*0.65
			roll=develop*float(d.twist)*.42+float(framing)*.22
		3:
			camera_goal=Vector3(float(d.axis_x)*.5,0.,5.5-develop*9.)
			target=Vector3(0.,0.,camera_goal.z-20.)
			roll=float(d.axis_y)*.12
		4:
			camera_goal=[Vector3(0,0,13),Vector3(1,0,9),Vector3(-3,1,11),Vector3(0,0,16)][framing]
		5:
			camera_goal=[Vector3(0,0,12),Vector3(.7,0,9),Vector3(-1,1,7),Vector3(0,0,14)][framing]
		6:
			camera_goal=[Vector3(0,0,10),Vector3(2,1,6),Vector3(-3,0,5),Vector3(1,-2,12)][framing]
			roll=develop*.4*float(d.axis_x)
		7:
			camera_goal=[Vector3(0,0,15),Vector3(-2,1,10),Vector3(2,-1,7),Vector3(0,0,17)][framing]
		8:
			camera_goal=Vector3(float(d.axis_x)*.9,float(d.axis_y)*.5,7.-develop*12.)
			target=Vector3(0,0,camera_goal.z-20.)
			camera_goal.x+=sin(develop*PI*1.7)*1.1
			camera_goal.y+=cos(develop*PI*1.7)*.5
			roll=float(d.twist)*develop*.24
		9:
			camera_goal=[Vector3(0,0,13),Vector3(-4,2,9),Vector3(4,-1,8),Vector3(0,3,16)][framing]
			roll=.18*float(d.axis_x)
		10:
			camera_goal=[Vector3(0,1,13),Vector3(6.,2.2,10),Vector3(-8.,2.8,11),Vector3(3.8,-.5,8.)][framing]
			target=[Vector3(-.6,.3,-6),Vector3(-2.8,.6,-2),Vector3(-3.8,.9,-1),Vector3(2.,-.4,-12.)][framing]
			camera_goal.z-=develop*.8
			target.y+=develop*.8
			roll=(develop-.5)*.5*float(d.axis_y)
		11:
			camera_goal=Vector3(sin(develop*PI)*1.0,cos(develop*PI)*.55,7.-develop*6.)
			target=Vector3(sin(develop*PI)*.35,0,camera_goal.z-15.)
	# Zoom, plunge and cuts are camera operations on the same construction.
	# They no longer rescale/rotate every independent object into its neighbours.
	if family not in [2,3,8,11]:
		camera_goal=target+(camera_goal-target)*(.95/clampf(float(d.get("camera_crop",1.)),.85,1.20))
		camera_goal.x+=float(d.get("camera_sweep",.5))*(develop-.5)*2.6
		camera_goal.y+=float(d.axis_y)*sin(develop*PI)*.8
	if pool.edit_kind==4: camera_goal.z-=pool.structure_impulse*(1.4+depth_response)
	if pool.edit_kind==0: camera_goal=target+(camera_goal-target)*(1.-pool.structure_impulse*.16)
	roll+=camera_response*.035+(pool.voices.contour[4]-.5)*lead_voice*.10
	# Forward knowledge changes WHEN a preparation happens; neural bass sets HOW.
	camera_goal=target+(camera_goal-target)*(1.-pool.voices.prepare_amount*bass_voice*.13)
	var new_view: bool=last_view!=pool.view_serial
	var speed := 1.-exp(-dt/(.065 if new_view or pool.view_age<.14 else .15))
	if last_view<0:
		camera_position=camera_goal; camera_target=target
		camera_roll=roll
	camera_position=camera_position.lerp(camera_goal,speed)
	camera_target=camera_target.lerp(target,speed)
	last_view=pool.view_serial
	camera.position=camera_position; camera.look_at(camera_target)
	camera_roll=lerp_angle(camera_roll,roll,speed)
	camera.rotate_object_local(Vector3.FORWARD,camera_roll)
	camera.fov=clampf(float(d.fov)*.78+pool.edit_strength*pool.edit_impulse*5.,38.,72.)
	assembly.rotation=Vector3(.04*float(d.axis_y)*develop,.08*float(d.axis_x)*develop,0.)
	for i in range(part_count):
		var g := part_group[i]; var j := part_order[i]; var owner := owner_ids[i]
		var neural := drive[owner]
		var voice_id := clampi(int(floor(surface_identity[i].a)),0,5)
		var voice_motion: float=clampf(pool.voices.motion[voice_id],-.3,1.)
		var voice_phase: float=pool.voices.phase[voice_id]
		var displacement: float=clampf(neural*.24+impulses[owner]*2.5,0.,.55)
		var pose := Layout.pose(d,part_kind[i],g,j,unfold,pool.shot_age)
		# Geometry lives in reserved lanes. A bounded local action cannot scale
		# a solid through another sheet; the camera supplies dramatic motion.
		var choreo := Transform3D.IDENTITY
		# The phrase plan is a bounded choreography for each group. It evolves
		# the same objects through the cue windows instead of replacing them with
		# a timer-driven preset or moving the whole world in one direction.
		if graph.parents[i]<0:
			choreo=PhraseDesign.group_action(d,g,progress)
		var action := Transform3D.IDENTITY
		if part_kind[i]==2:
			# Percussive details contract inside their own footprint on contact,
			# then recover. Negative pre-roll provides a small anticipatory lift.
			var contact: float=maxf(0.,voice_motion)
			action.basis=Basis.IDENTITY.scaled(Vector3(1.-contact*.16,1.-contact*.28,.68+graph.build_amount*.20+displacement*.30))
		elif part_kind[i]==0:
			action.origin.z=displacement*.12
			# A sheet has a coherent hinged action, not an arbitrary translation.
			# It inherits a tonal voice for the phrase; children follow its frame.
			var sway := sin(voice_phase*1.6)*voice_motion
			var pitch := sin(voice_phase*1.1+.6)*voice_motion
			var clearance := .18 if family==8 else 1.
			var impact_contact: float=clampf(pool.voices.motion[0],0.,1.)
			action.origin.z=displacement*.20+impact_contact*.14
			action.basis=Basis.from_euler(Vector3(pitch*.16,sway*.22,0.)*clearance)
			action.basis=action.basis*Basis.from_scale(Vector3.ONE*(1.-absf(voice_motion)*.06-impact_contact*.045))
		elif part_kind[i]==1:
			action.basis=Basis.IDENTITY.rotated(Vector3.FORWARD,displacement*.36+voice_phase*.24+voice_motion*.18)
		elif part_kind[i]==4:
			# Smooth phase comes from the recorded downstream response. With a
			# silent voice it stops advancing; no raw-audio rotation fallback.
			action.basis=Basis.from_euler(Vector3(sin(voice_phase*.7)*voice_motion*.18,neural*.48+unfold*.65+deformation_response*.18+voice_phase*.65,voice_phase*.20))
		if part_kind[i]==3:
			pose=graph.base[graph.parents[i]]
			action=Transform3D(Basis.IDENTITY,Vector3(0,0,.012))
		if graph.parents[i]<0: action=choreo*action
		var transform: Transform3D=graph.resolve(i,pose,action)
		positions[i]=transform.origin
		directions_u[i]=transform.basis.x*.65; directions_v[i]=transform.basis.y*.65
		batches[part_kind[i]].set_instance_transform(part_slot[i],transform)
	for k in range(5): batches[k].visible_instance_count=counts[k] if (pool.enabled[2] or pool.enabled[3]) else 0
	anchor_clock+=dt
	if anchor_clock>=.025:
		anchor_clock=fmod(anchor_clock,.025)
		for i in range(256):
			var part := anchor_owner[i]
			var point := assembly.to_global(positions[part])
			var screen := camera.unproject_position(point)/view_size
			anchor_pixels[i*4]=screen.x; anchor_pixels[i*4+1]=screen.y
			anchor_pixels[i*4+2]=clampf(4./maxf(1.,camera.position.distance_to(point)),.05,1.)
			anchor_pixels[i*4+3]=0. if camera.is_position_behind(point) else 1.
			var u := camera.unproject_position(assembly.to_global(positions[part]+directions_u[part]))/view_size-screen
			var v := camera.unproject_position(assembly.to_global(positions[part]+directions_v[part]))/view_size-screen
			anchor_pixels[(i+256)*4]=u.x; anchor_pixels[(i+256)*4+1]=u.y
			anchor_pixels[(i+256)*4+2]=v.x; anchor_pixels[(i+256)*4+3]=v.y
		anchor_image.set_data(16,32,false,Image.FORMAT_RGBAF,anchor_pixels.to_byte_array()); anchor_texture.update(anchor_image)
	if progress>.64 and memory_world!=current_id and not memory_busy:
		_record_view(int(d.background),palette_id,pool.view_polarity)
