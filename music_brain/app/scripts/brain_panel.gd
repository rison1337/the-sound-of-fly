extends PanelContainer

signal expansion_requested
var positions := PackedVector3Array()
var camera: Camera3D
var viewport: SubViewport
var view: SubViewportContainer
var detail: Label
var status: Label
var orbit := 0.0
var elevation := 0.12
var distance := 26.0
var dragging := false
var target := Vector3.ZERO
var expanded := false
var latest := {}
var ready_cloud := false
var neural_material: ShaderMaterial
var header: HBoxContainer
var column: VBoxContainer
var presentation := false
var cloud_radius := 1.

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("080b12")
	style.border_color = Color("59606e")
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel",style)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	add_child(column)
	header = HBoxContainer.new()
	column.add_child(header)
	status = Label.new()
	status.text = "01 / NEURAL RESPONSE"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_font_size_override("font_size",12)
	header.add_child(status)
	var expand := Button.new()
	expand.text = "[ + ]"
	expand.tooltip_text = "Expand / collapse brain (B)"
	expand.focus_mode = Control.FOCUS_NONE
	expand.pressed.connect(func(): expansion_requested.emit())
	header.add_child(expand)
	view = SubViewportContainer.new()
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(200,150)
	column.add_child(view)
	view.gui_input.connect(_view_input)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = 42
	camera.current = true
	world.add_child(camera)
	detail = Label.new()
	detail.add_theme_font_size_override("font_size",11)
	detail.add_theme_color_override("font_color",Color("9ba8c1"))
	detail.text = "Loading connectome..."
	column.add_child(detail)
	var root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--asset-root="): root=arg.trim_prefix("--asset-root=")
	if root.is_empty(): root=ProjectSettings.globalize_path("res://../../../terrarium/data")
	var path := root.path_join("soma_positions_f32.bin")
	if not FileAccess.file_exists(path):
		detail.text = "Brain coordinates unavailable"
		return
	var raw := FileAccess.get_file_as_bytes(path).to_float32_array()
	var vnc := FileAccess.get_file_as_bytes(root.path_join("soma_is_vnc.bin"))
	positions.resize(raw.size()/3)
	var points: Array[int] = []
	for i in range(positions.size()):
		positions[i]=Vector3(raw[i*3],raw[i*3+1],raw[i*3+2])
		if positions[i]!=Vector3.ZERO and (i>=vnc.size() or vnc[i]==0): points.append(i)
	var center := Vector3.ZERO
	for i in points: center+=positions[i]
	target=center/max(1,points.size())
	for i in points: cloud_radius=maxf(cloud_radius,positions[i].distance_to(target))
	var mesh := QuadMesh.new()
	mesh.size=Vector2(.22,.22)
	var material := ShaderMaterial.new()
	material.shader=preload("res://shaders/neuron.gdshader")
	neural_material=material
	mesh.material=material
	var base := MultiMesh.new()
	base.transform_format=MultiMesh.TRANSFORM_3D
	base.use_custom_data=true
	base.mesh=mesh
	base.instance_count=points.size()
	for j in range(points.size()):
		base.set_instance_transform(j,Transform3D(Basis(),positions[points[j]]))
		base.set_instance_custom_data(j,Color(float(points[j]%512),float(points[j]/512),0.,0.))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh=base
	world.add_child(instance)
	# Quiet anatomy is a separate, static layer; the activity shader above
	# keeps the full per-cell state and transient flashes legible on top.
	var anatomy_material := StandardMaterial3D.new()
	anatomy_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	anatomy_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	anatomy_material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	anatomy_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	anatomy_material.no_depth_test=true
	anatomy_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	anatomy_material.albedo_color=Color(.12,.33,.45,.20)
	var anatomy_quad := QuadMesh.new()
	anatomy_quad.size=Vector2(.08,.08)
	anatomy_quad.material=anatomy_material
	var anatomy := MultiMesh.new()
	anatomy.transform_format=MultiMesh.TRANSFORM_3D
	anatomy.mesh=anatomy_quad
	anatomy.instance_count=points.size()
	for j in range(points.size()): anatomy.set_instance_transform(j,base.get_instance_transform(j))
	var anatomy_instance := MultiMeshInstance3D.new()
	anatomy_instance.multimesh=anatomy
	world.add_child(anatomy_instance)
	ready_cloud=true
	_update_camera()
	update_state(latest)

func set_presentation(value: bool) -> void:
	presentation=value
	header.visible=not value; detail.visible=not value
	view.custom_minimum_size=Vector2.ZERO if value else Vector2(200,150)
	column.add_theme_constant_override("separation",0 if value else 8)
	if value:
		var style := StyleBoxFlat.new()
		style.bg_color=Color("080d18")
		style.set_corner_radius_all(20)
		style.set_content_margin_all(8)
		add_theme_stylebox_override("panel",style)
		view.mouse_filter=Control.MOUSE_FILTER_IGNORE
		viewport.msaa_3d=Viewport.MSAA_4X
		viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		camera.fov=38.
		animate_presentation(0.)

func animate_presentation(clock: float) -> void:
	if not presentation or not ready_cloud: return
	# Absolute soundtrack time makes this motion identical at 30/60 fps and seek.
	# The full recorded per-cell state supplies the light; the camera reveals depth.
	orbit=.34*sin(clock*.19)+clock*.035
	elevation=.16+.10*sin(clock*.13)
	# The compact export card has less room than the interactive panel. Keep the
	# card small, but bring the neural cloud forward so its silhouette reads.
	distance=cloud_radius/sin(deg_to_rad(camera.fov*.5))*.56
	_update_camera()

func update_state(state: Dictionary) -> void:
	latest=state
	if not ready_cloud: return
	detail.text="%d active cells  /  %.1f Hz\nDrag to orbit · Scroll to zoom" % [int(state.get("responding",0)),float(state.get("mean_hz",0.))]
	status.text="01 / BRAIN PAUSED" if state.get("paused",false) else "01 / NEURAL RESPONSE"

func set_neural_texture(texture: Texture2D) -> void:
	if neural_material!=null:
		neural_material.set_shader_parameter("neural_frame",texture)
		neural_material.set_shader_parameter("has_frame",true)

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(14.,distance*.90)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(90.,distance*1.10)
		_update_camera()
	if event is InputEventMouseMotion and dragging:
		orbit-=event.relative.x*.008
		elevation=clampf(elevation+event.relative.y*.006,-1.2,1.2)
		_update_camera()

func _update_camera() -> void:
	if camera==null: return
	camera.position=target+Vector3(sin(orbit)*cos(elevation),sin(elevation),cos(orbit)*cos(elevation))*distance
	camera.look_at(target)
