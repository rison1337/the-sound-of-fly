extends SceneTree
## Real GPU regressions for surface contrast, depth, deformation and normals.
const Meshes=preload("res://scripts/assembly_meshes.gd")
var failures := 0

func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)

func field(width: int,height: int,value: Color) -> ImageTexture:
	var image := Image.create(width,height,false,Image.FORMAT_RGBAF)
	image.fill(value)
	return ImageTexture.create_from_image(image)

func difference(a: Image,b: Image) -> float:
	var total := 0.
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var p := a.get_pixel(x,y); var q := b.get_pixel(x,y)
			total+=absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)
	return total/float(a.get_width()*a.get_height()*3)

func frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func baked_mesh(source: Mesh, pose: Transform3D) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var normal_basis := pose.basis.inverse().transposed()
	for i in range(vertices.size()):
		vertices[i]=pose*vertices[i]
		normals[i]=(normal_basis*normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var viewport := SubViewport.new(); viewport.size=Vector2i(256,192)
	viewport.own_world_3d=true; viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera)
	camera.position=Vector3(0,0,5); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=3.
	var mat := ShaderMaterial.new(); mat.shader=load("res://shaders/assembly.gdshader")
	mat.set_shader_parameter("shape_kind",0.)
	mat.set_shader_parameter("trajectory",field(16,4,Color(.4,0,0,0)))
	mat.set_shader_parameter("populations",field(16,16,Color(.2,.3,0,0)))
	mat.set_shader_parameter("voices",field(6,2,Color(0,0,0,0)))
	var mesh := MultiMesh.new(); mesh.transform_format=MultiMesh.TRANSFORM_3D
	mesh.use_custom_data=true; mesh.mesh=Meshes.panel(); mesh.instance_count=1
	mesh.set_instance_custom_data(0,Color(39,1,.4,1.))
	mesh.set_instance_transform(0,Transform3D.IDENTITY)
	var node := MultiMeshInstance3D.new(); node.multimesh=mesh; node.material_override=mat
	viewport.add_child(node)
	var front := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=Vector3(3,3,.12)
	front.mesh=box; front.position.z=.8
	var cover := StandardMaterial3D.new(); cover.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	cover.albedo_color=Color(.12,.3,.7); front.material_override=cover; viewport.add_child(front)
	var covered_quiet := await frame(viewport)
	mat.set_shader_parameter("voices",field(6,2,Color(1,.7,.3,0)))
	var covered_active := await frame(viewport)
	check(difference(covered_quiet,covered_active)<.00001,"Neural deformation bleeds through a foreground object")
	front.visible=false
	var exposed_active := await frame(viewport)
	mat.set_shader_parameter("voices",field(6,2,Color(0,0,0,0)))
	var exposed_quiet := await frame(viewport)
	check(difference(exposed_quiet,exposed_active)>.00005,"Removing surface marks also removed neural deformation")
	# Render against the actual canvas palette, as in the player. Test both
	# sheets and rings: neither may vanish into the paper backdrop or its inverse.
	var backdrop_layer := CanvasLayer.new(); backdrop_layer.layer=-1
	viewport.add_child(backdrop_layer)
	var backdrop := ColorRect.new(); backdrop.size=Vector2(viewport.size)
	backdrop_layer.add_child(backdrop)
	var world := WorldEnvironment.new(); world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_CANVAS
	world.environment.background_canvas_max_layer=-1
	viewport.add_child(world)
	var papers := [Color(.935,.94,.918),Color(.945,.926,.865),Color(.89,.925,.885),Color(.94,.92,.91)]
	var min_contrast := 1.
	for kind in [0,1]:
		mesh.mesh=Meshes.panel() if kind==0 else Meshes.create()[1]
		mat.set_shader_parameter("shape_kind",float(kind))
		for palette_id in range(4):
			mat.set_shader_parameter("palette",float(palette_id))
			for inverse in [0.,1.]:
				mat.set_shader_parameter("polarity",inverse)
				backdrop.color=papers[palette_id] if inverse<.5 else Color(.023,.028,.036)
				var contrasted := await frame(viewport)
				var at := camera.unproject_position(Vector3.ZERO if kind==0 else Vector3(.57,0.,0.))
				var body := contrasted.get_pixel(int(at.x),int(at.y))
				var bg := contrasted.get_pixel(4,4)
				var contrast := absf(body.get_luminance()-bg.get_luminance())
				min_contrast=minf(min_contrast,contrast)
				check(contrast>.05,"Quiet surface merges into background: kind=%s palette=%s inverse=%s contrast=%s"%[kind,palette_id,inverse,contrast])
	print("SURFACE_CONTRAST minimum_luminance_difference=",min_contrast)
	backdrop_layer.queue_free()
	world.queue_free()
	mesh.mesh=Meshes.panel(); mat.set_shader_parameter("shape_kind",0.)
	mat.set_shader_parameter("palette",0.); mat.set_shader_parameter("polarity",0.)
	# Strong musical response must keep a filled panel continuous. A snare may
	# deform a surface, but may not discard a horizontal hole through it.
	mat.set_shader_parameter("destruction",1.)
	mat.set_shader_parameter("voices",field(6,2,Color(1,.7,.3,0)))
	var stressed := await frame(viewport)
	check(stressed.get_pixel(128,96).r>.15,"Strong transient tears a hole through the panel")
	# A nested frame has a real hole and a watertight closed azimuth seam.
	viewport.transparent_bg=true
	mesh.mesh=Meshes.panel(true)
	mat.set_shader_parameter("family",11.)
	mat.set_shader_parameter("voices",field(6,2,Color(0,0,0,0)))
	var nested := await frame(viewport)
	check(nested.get_pixel(128,96).a<.01,"Nested frame opening is filled")
	for x in [.73,.80,.87]:
		for y in [-.018,-.006,.006,.018]:
			var pixel := camera.unproject_position(Vector3(x,y,.035))
			check(nested.get_pixel(int(pixel.x),int(pixel.y)).a>.98,"Crack at closed frame seam")
	# A musical role is categorical. Perspective interpolation of an integer
	# role (1.0) must not flip floor(role) between 0 and 1 across neighbouring
	# fragments. That produced stippled black patches on the first printed panel.
	mesh.mesh=Meshes.panel()
	mat.set_shader_parameter("family",5.)
	mat.set_shader_parameter("graphic_mode",3.)
	mat.set_shader_parameter("voices",field(6,2,Color(.8,.2,1.6,0)))
	mat.set_shader_parameter("destruction",0.)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=Vector3(.7,.3,3.); camera.look_at(Vector3.ZERO)
	mesh.set_instance_custom_data(0,Color(39,4,.29565,1.))
	var integer_role := await frame(viewport)
	mesh.set_instance_custom_data(0,Color(39,4,.29565,1.001))
	var nudged_role := await frame(viewport)
	var role_change := difference(integer_role,nudged_role)
	print("ROLE_STABILITY mean_rgb_change=",role_change)
	check(role_change<.002,"Integer voice identity produces grain under perspective")
	# Use the production torus domain, including its tube seam, not a test-only
	# flat annulus. A changing neural profile may not open either angular seam.
	mesh.mesh=Meshes.create()[1]
	mat.set_shader_parameter("shape_kind",1.)
	mat.set_shader_parameter("family",0.)
	mat.set_shader_parameter("fold",0.)
	mat.set_shader_parameter("articulation",0.)
	mat.set_shader_parameter("voices",field(6,2,Color(0,0,0,0)))
	var ramp := Image.create(16,4,false,Image.FORMAT_RGBAF)
	for y in range(4):
		for x in range(16): ramp.set_pixel(x,y,Color(float(x)/15.,0,0,0))
	mat.set_shader_parameter("trajectory",ImageTexture.create_from_image(ramp))
	mesh.set_instance_custom_data(0,Color(39,2,.3,0.))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.position=Vector3(0,0,5); camera.look_at(Vector3.ZERO); camera.size=2.
	var ring := await frame(viewport)
	check(ring.get_pixel(128,96).a<.01,"Ring centre is filled")
	for angle in [-.025,-.01,0.,.01,.025]:
		var at := camera.unproject_position(Vector3(cos(angle)*.59,sin(angle)*.59,0.))
		check(ring.get_pixel(int(at.x),int(at.y)).a>.98,"Crack in closed ring join")
	# Edge-on has visible thickness, rather than a disappearing single sheet.
	mesh.set_instance_transform(0,Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3.ZERO))
	var edge := await frame(viewport)
	var coverage := 0
	for y in range(edge.get_height()):
		for x in range(edge.get_width()):
			if edge.get_pixel(x,y).a>.98: coverage+=1
	check(coverage>200,"Ring disappears when viewed edge-on")
	mesh.set_instance_transform(0,Transform3D.IDENTITY)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=Vector3(.7,.3,3.); camera.look_at(Vector3.ZERO)
	# In this solid-accent material lighting has a positive lower bound.
	# Black interior pixels therefore indicate invalid normals, not artwork.
	mesh.mesh=Meshes.surface(96,48)
	mat.set_shader_parameter("shape_kind",4.)
	mat.set_shader_parameter("family",0.)
	mesh.set_instance_custom_data(0,Color(39,2,0.,1.))
	for morphology in range(4):
		mat.set_shader_parameter("contour_mode",float(morphology))
		var solid := await frame(viewport)
		var interior := 0; var invalid := 0
		for y in range(solid.get_height()):
			for x in range(solid.get_width()):
				var sample := solid.get_pixel(x,y)
				if sample.a>.99:
					interior+=1
					if sample.b<.12: invalid+=1
		check(interior>100,"Closed surface was not rendered")
		check(invalid==0,"Invalid dark normal pixels on closed morphology %s: %s"%[morphology,invalid])
	# Equivalent geometry must shade identically whether anisotropic scale is
	# baked into mesh vertices or supplied by a MultiMesh instance. This catches
	# the normal-transform bug that made almost-flat panels look crumpled.
	mat.set_shader_parameter("shape_kind",2.)
	mat.set_shader_parameter("voices",field(6,2,Color(0,0,0,0)))
	var sphere := SphereMesh.new(); sphere.radius=.7; sphere.height=1.4
	sphere.radial_segments=64; sphere.rings=32
	var scale_pose := Transform3D(Basis.from_euler(Vector3(.2,.35,.1))*Basis.from_scale(Vector3(1.2,.85,.06)),Vector3.ZERO)
	mesh.mesh=sphere; mesh.set_instance_transform(0,scale_pose)
	var instanced := await frame(viewport)
	mesh.mesh=baked_mesh(sphere,scale_pose); mesh.set_instance_transform(0,Transform3D.IDENTITY)
	var baked := await frame(viewport)
	var scale_error := difference(instanced,baked)
	print("NORMAL_SCALE_EQUIVALENCE mean_rgb_change=",scale_error)
	check(scale_error<.0002,"Instance scale corrupts surface lighting")
	# A spatial print owns its ink silhouette. Its aperture, rectangular
	# corners, rim and reverse side must never leave an opaque paper card.
	mesh.mesh=Meshes.panel(); mat.set_shader_parameter("shape_kind",0.)
	mat.set_shader_parameter("family",0.); mat.set_shader_parameter("graphic_mode",1.)
	mesh.set_instance_custom_data(0,Color(39,4,0.,0.))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=3.
	for side in [1.,-1.]:
		camera.position=Vector3(0,0,5.*side); camera.look_at(Vector3.ZERO)
		var cut := await frame(viewport)
		for point in [Vector3.ZERO,Vector3(.84,.84,.035)]:
			var at := camera.unproject_position(point)
			check(cut.get_pixel(int(at.x),int(at.y)).a<.01,"Cutout aperture or corner has an opaque substrate")
		var filled := camera.unproject_position(Vector3(.376,0,.035))
		check(cut.get_pixel(int(filled.x),int(filled.y)).a>.98,"Cutout ink disappears from one side")
	camera.position=Vector3(0,0,5); camera.look_at(Vector3.ZERO)
	front.position.z=-.8; front.visible=true
	var through_hole := await frame(viewport)
	node.visible=false
	var background_only := await frame(viewport)
	check(through_hole.get_pixel(128,96).is_equal_approx(background_only.get_pixel(128,96)),"Cutout aperture blocks geometry behind it")
	node.visible=true; front.position.z=.8
	var occluded_cut := await frame(viewport)
	node.visible=false
	var foreground_only := await frame(viewport)
	check(difference(occluded_cut,foreground_only)<.00001,"Cutout ignores foreground depth")
	viewport.queue_free()
	print("SURFACE_RENDER failures=",failures)
	quit(0 if failures==0 else 1)
