extends Node3D
## The neural service supplies escape events and steering. This body is a
## procedural flight/landing controller, not an aerodynamic Drosophila model.

const SimClient = preload("res://scripts/sim_client.gd")
const BrainView = preload("res://scripts/brain_view.gd")
const Experiments = preload("res://scripts/experiments.gd")
const TEAL = Color("96d5be")
const INK = Color("dce5d9")
var client: Node
var brain: Dictionary = {}
var camera: Camera3D
var fly: Node3D
var wings: Array[Node3D] = []
var legs: Array[Node3D] = []
var threat: Node3D
var food: Node3D
var lamp: OmniLight3D
var status_label: Label
var info_label: Label
var hint_label: Label
var neural_panel: PanelContainer
var neural_label: Label
var buttons: Dictionary = {}
var pos = Vector3(0, 4, 0)
var vel = Vector3(1, 0, 0)
var destination = Vector3(4, 5, -2)
var heading = 0.0
var clock = 0.0
var since_target = 0.0
var since_flight = 0.0
var resting = false
var landing = false
var rest_time = 0.0
var escape_time = 0.0
var escape_count = 0
var scare_count = 0
var looming = 0.0
var threat_time = -1.0
var threat_from = Vector3.ZERO
var threat_to = Vector3.ZERO
var threat_side = 1.0
var paused = false
var following = false
var food_on = true
var light_on = true
var orbit = 0.65
var elevation = 0.43
var distance = 35.0
var camera_target = Vector3(0, 3, 0)
var send_timer = 0.0
var rng = RandomNumberGenerator.new()
var last_packet = -100.0
var brain_view: Window
var experiments: Node3D

func _ready() -> void:
	rng.seed = 41
	get_tree().auto_accept_quit = false
	_build_world()
	_build_fly()
	experiments = Experiments.new()
	add_child(experiments)
	_build_ui()
	client = SimClient.new()
	add_child(client)
	client.state_updated.connect(_on_state)
	client.start("127.0.0.1", 9876)
	_update_camera(1.0)
	if "--brain" in OS.get_cmdline_user_args():
		call_deferred("_action","brain")

func material(color: Color, roughness: float = 0.7) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = at
	parent.add_child(n)
	return n

func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m = BoxMesh.new()
	m.size = size
	return mesh_node(parent, m, at, mat)

func ellipsoid(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m = SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 24
	m.rings = 12
	var n = mesh_node(parent, m, at, mat)
	n.scale = size
	return n

func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var m = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = a.distance_to(b)
	m.radial_segments = 8
	var n = mesh_node(parent, m, (a + b) * 0.5, mat)
	var dir = (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		n.quaternion = Quaternion(Vector3.UP, dir)
	elif dir.y < 0:
		n.rotation.x = PI
	return n

func _build_world() -> void:
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101e20")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("bacbd5")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("ffe7c4")
	sun.light_energy = 0.70
	sun.shadow_enabled = true
	add_child(sun)
	var fill = OmniLight3D.new()
	fill.position = Vector3(-6, 8, 8)
	fill.light_color = Color("a1d9cb")
	fill.light_energy = 0.22
	fill.omni_range = 25
	add_child(fill)
	var base = material(Color("283c39"))
	var soil = material(Color("9e9b75"))
	var trim = material(Color("587069"), 0.35)
	box(self, Vector3(0,-0.6,0), Vector3(25,1.0,19), base)
	box(self, Vector3(0,-0.12,0), Vector3(24,0.25,18), soil)
	for x in [-12.0, 12.0]:
		for z in [-9.0, 9.0]:
			box(self, Vector3(x,5.7,z), Vector3(0.08,11.6,0.08), trim)
	for y in [0.02, 11.4]:
		for z in [-9.0,9.0]:
			box(self, Vector3(0,y,z), Vector3(24,0.08,0.08), trim)
		for x in [-12.0,12.0]:
			box(self, Vector3(x,y,0), Vector3(0.08,0.08,18), trim)
	var glass = material(Color(0.5,0.8,0.76,0.035),0.1)
	box(self,Vector3(0,5.7,-9),Vector3(24,11.4,0.015),glass)
	box(self,Vector3(-12,5.7,0),Vector3(0.015,11.4,18),glass)
	var moss_mats = [material(Color("587451")),material(Color("7b8d58")),material(Color("425e49"))]
	for i in range(110):
		var at = Vector3(rng.randf_range(-11.5,11.5),0.02,rng.randf_range(-8.5,8.5))
		var sz = rng.randf_range(0.08,0.45)
		ellipsoid(self,at,Vector3(sz,sz*0.18,sz*0.8),moss_mats[i%3])
	var stone = material(Color("afbaaa"))
	for spec in [Vector3(-7,0.35,3),Vector3(-5,0.22,4),Vector3(7,0.5,-5)]:
		ellipsoid(self,spec,Vector3(1.1,spec.y+0.1,0.8),stone)
	for spec in [Vector3(-8,0,-5),Vector3(-6,0,-6),Vector3(8,0,-6),Vector3(9,0,3)]:
		_plant(spec, rng.randf_range(2.4,4.0))
	var wood = material(Color("71634a"))
	rod(self,Vector3(-8,0.2,-2),Vector3(-4,1.0,-3),0.35,wood)
	rod(self,Vector3(-6,0.7,-2.5),Vector3(-5,2.5,-4),0.1,wood)
	food = Node3D.new()
	add_child(food)
	food.position = Vector3(4,0,3)
	ellipsoid(food,Vector3(0,0.05,0),Vector3(1.4,0.16,1.4),material(Color("d6c8a7")))
	for i in range(3):
		var slice = ellipsoid(food,Vector3((i-1)*0.55,0.27,0),Vector3(0.55,0.14,0.6),material(Color("f7d279")))
		slice.rotation.z = (i-1)*0.08
	lamp = OmniLight3D.new()
	lamp.position = Vector3(6,8,-4)
	lamp.light_color = Color("ffdf9b")
	lamp.light_energy = 0.55
	lamp.omni_range = 14
	add_child(lamp)
	threat = Node3D.new()
	add_child(threat)
	ellipsoid(threat,Vector3.ZERO,Vector3(1,1,1),material(Color("e0907f"),0.3))
	threat.visible = false
	camera = Camera3D.new()
	camera.fov = 48
	camera.near = 0.1
	camera.far = 150
	add_child(camera)
	camera.make_current()

func _plant(at: Vector3, height: float) -> void:
	var stem = material(Color("466047"))
	var leaf = material(Color("729162"))
	rod(self, at, at+Vector3(0,height,0),0.045,stem)
	for i in range(5):
		var angle = i*2.4
		var h = height*(0.25+i*0.14)
		var dir = Vector3(cos(angle),0.35,sin(angle))
		rod(self,at+Vector3(0,h,0),at+Vector3(0,h,0)+dir*0.9,0.025,stem)
		var n = ellipsoid(self,at+Vector3(0,h,0)+dir*1.05,Vector3(0.75,0.055,0.3),leaf)
		n.rotation = Vector3(0,-angle,0.3)

func _build_fly() -> void:
	fly = Node3D.new()
	add_child(fly)
	var brown = material(Color("665042"),0.5)
	var dark = material(Color("302d2b"),0.45)
	var gold = material(Color("b59059"),0.5)
	var red = material(Color("ac392d"),0.25)
	ellipsoid(fly,Vector3(0,0,0),Vector3(0.26,0.25,0.35),brown)
	ellipsoid(fly,Vector3(0,-0.04,0.49),Vector3(0.28,0.22,0.48),gold)
	for z in [0.31,0.48,0.65,0.80]:
		var section = sqrt(1.0-pow((z-0.49)/0.48,2))
		ellipsoid(fly,Vector3(0,-0.04,z),Vector3(0.291*section,0.231*section,0.048),dark)
	ellipsoid(fly,Vector3(0,0.035,-0.39),Vector3(0.27,0.22,0.20),brown)
	for side in [-1.0,1.0]:
		ellipsoid(fly,Vector3(side*0.21,0.065,-0.43),Vector3(0.125,0.18,0.15),red)
		rod(fly,Vector3(side*0.10,0.11,-0.54),Vector3(side*0.16,0.18,-0.70),0.012,dark)
		var wing = Node3D.new()
		fly.add_child(wing)
		wing.position = Vector3(side*0.16,0.16,0.05)
		wings.append(wing)
		var wm = material(Color(0.83,0.90,0.88,0.43),0.25)
		ellipsoid(wing,Vector3(side*0.57,0,0.14),Vector3(0.75,0.014,0.30),wm)
		var vein = material(Color(0.65,0.74,0.69,0.55))
		for branch in [-0.13,0.02,0.19]:
			rod(wing,Vector3.ZERO,Vector3(side*1.17,0.015,branch),0.007,vein)
		for i in range(3):
			var leg = Node3D.new()
			fly.add_child(leg)
			leg.position = Vector3(side*0.18,-0.08,-0.18+i*0.22)
			var knee = Vector3(side*0.27,-0.21,(i-1)*0.19)
			var foot = Vector3(side*0.40,-0.50,(i-1)*0.31)
			rod(leg,Vector3.ZERO,knee,0.018,dark)
			rod(leg,knee,foot,0.012,dark)
			legs.append(leg)
	# A soft ground marker helps judge height without a giant fly or an arrow.
	var shadow = ellipsoid(self,Vector3(0,0.015,0),Vector3(0.65,0.008,0.48),material(Color(0.15,0.20,0.16,0.16)))
	shadow.name = "FlyShadow"

func _style(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 13
	s.content_margin_bottom = 13
	return s

func _label(text_value: String, size: int, color: Color = INK) -> Label:
	var l = Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var title = VBoxContainer.new()
	title.position = Vector2(38,28)
	title.add_theme_constant_override("separation",6)
	root.add_child(title)
	title.add_child(_label("D R O F F E L",30,TEAL))
	title.add_child(_label("Личный террариум",17))
	var badge = _label("DROSOPHILA  /  MALE CNS 1.0",12,Color("90a99b"))
	title.add_child(badge)
	var status = VBoxContainer.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.position = Vector2(-365,30)
	status.size = Vector2(325,100)
	root.add_child(status)
	status_label = _label("●  Подключение к модели…",19,TEAL)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(status_label)
	info_label = _label("",14,Color("aec0b4"))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(info_label)
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.035,0.075,0.069,0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	backdrop.offset_top = -158
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	var bottom = VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 38
	bottom.offset_right = -38
	bottom.offset_top = -136
	bottom.offset_bottom = -24
	bottom.add_theme_constant_override("separation",12)
	root.add_child(bottom)
	hint_label = _label("Наблюдай. Приблизься. Посмотри, как она отреагирует.",17,INK)
	bottom.add_child(hint_label)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",9)
	bottom.add_child(row)
	for entry in [["scare","Напугать  ·  SPACE"],["food","Корм  ●"],["light","Свет  ●"],["follow","Следить  ·  F"],["pause","Пауза  ·  P"],["brain","Мозг 3D  ·  B"],["experiments","Опыты  ·  E"]]:
		var b = Button.new()
		b.text = entry[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size",16)
		b.add_theme_color_override("font_color",INK)
		b.add_theme_stylebox_override("normal",_style(Color("203833"),Color("3c5750")))
		b.add_theme_stylebox_override("hover",_style(Color("34534a"),TEAL))
		b.add_theme_stylebox_override("pressed",_style(Color("456958"),TEAL))
		b.pressed.connect(_action.bind(entry[0]))
		row.add_child(b)
		buttons[entry[0]] = b
	bottom.add_child(_label("ПКМ + движение — камера     Колесо — масштаб     ЛКМ / SPACE — приблизить объект     R — вернуть муху",12,Color("92a89b")))
	neural_panel = PanelContainer.new()
	neural_panel.position = Vector2(38,155)
	neural_panel.custom_minimum_size = Vector2(320,0)
	neural_panel.add_theme_stylebox_override("panel",_style(Color(0.07,0.14,0.12,0.94),Color("405e51")))
	root.add_child(neural_panel)
	neural_label = _label("",15)
	neural_panel.add_child(neural_label)
	neural_panel.visible = false
	experiments.build_ui(root)

func _action(action: String) -> void:
	match action:
		"profile_interactive": client.send({"cmd":"profile","value":"interactive"})
		"profile_research": client.send({"cmd":"profile","value":"research"})
		"scare": _scare()
		"food":
			food_on = not food_on
			food.visible = food_on
			buttons.food.text = "Корм  ●" if food_on else "Корм  ○"
		"light":
			light_on = not light_on
			lamp.visible = light_on
			buttons.light.text = "Свет  ●" if light_on else "Свет  ○"
		"follow":
			following = not following
			buttons.follow.text = "Общий вид  ·  F" if following else "Следить  ·  F"
		"pause":
			paused = not paused
			client.send({"cmd":"pause","value":paused})
			buttons.pause.text = "Продолжить  ·  P" if paused else "Пауза  ·  P"
		"brain":
			if not brain_view:
				brain_view = BrainView.new()
				brain_view.experiment_requested.connect(_action)
				add_child(brain_view)
				brain_view.show()
			else:
				brain_view.visible = not brain_view.visible
			brain_view.update_state(brain)
		_: experiments.action(action)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _action("scare")
			KEY_F: _action("follow")
			KEY_P: _action("pause")
			KEY_B: _action("brain")
			KEY_E: _action("experiments")
			KEY_1: _action("odor_a")
			KEY_2: _action("odor_b")
			KEY_T: _action("touch")
			KEY_V: _action("vibration")
			KEY_H: _action("heat")
			KEY_L: _action("firefly")
			KEY_R:
				pos = Vector3(0,4,0)
				vel = Vector3(1,0,0)
				resting = false
				landing = false
				since_flight = 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(8,distance-1.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(52,distance+1.5)
		if event.button_index == MOUSE_BUTTON_LEFT: _scare()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit -= event.relative.x*0.005
		elevation = clampf(elevation+event.relative.y*0.004,0.10,1.3)

func _scare() -> void:
	if paused or not _connected(): return
	threat_time = 0.0
	scare_count += 1
	threat_side = -1.0 if scare_count%2 == 0 else 1.0
	var side = Vector3(cos(heading),0,-sin(heading))*threat_side
	var forward = Vector3(-sin(heading),0,-cos(heading))
	threat_from = pos + forward*8 + side*4 + Vector3(0,1,0)
	threat_to = pos + forward*0.6 + side*0.3
	threat.visible = true
	hint_label.text = "Объект приближается — зрительный стимул передан модели."

func _on_state(state: Dictionary) -> void:
	if state.get("profile","") != brain.get("profile",""):
		escape_time = 0
	brain = state
	if brain_view: brain_view.update_state(state)
	last_packet = Time.get_ticks_msec()/1000.0
	var count = int(state.get("escape_count",0))
	if count > escape_count:
		escape_time = 1.5
		resting = false
		landing = false
		since_flight = 0
		var away = (pos-threat.position).normalized()
		if away.length() < 0.2: away = Vector3(0,0,-1)
		vel = (away + Vector3(0,0.65,0)).normalized()*12
		destination = pos+vel*0.7
		hint_label.text = "Реакция побега!  Муха меняет направление и набирает высоту."
	escape_count = count

func _connected() -> bool:
	return not brain.is_empty() and Time.get_ticks_msec()/1000.0-last_packet < 2.0

func _process(delta: float) -> void:
	var dt = minf(delta,0.05)
	var body_dt = dt*clampf(float(brain.get("speed_ratio",1)),0,1)
	if _connected() and not paused and not brain.get("loading",false):
		clock += body_dt
		experiments.tick(body_dt)
		_move_fly(body_dt)
		_move_threat(body_dt)
		_animate(body_dt)
	_update_camera(dt)
	send_timer += delta
	if send_timer > 0.05 and client:
		send_timer = 0
		var smell = clampf(1.0-pos.distance_to(food.position)/13,0,1) if food_on else 0.0
		var inputs = {"cmd":"sense", "loom_L":looming if threat_side<0 else looming*0.35,
			"loom_R":looming if threat_side>0 else looming*0.35,
			"odor":smell*0.4,"taste":1.0 if resting and food_on and pos.distance_to(food.position)<2 else 0.0,
			"light":0.12 if light_on else 0.0}
		inputs.merge(experiments.sensory(pos,heading))
		client.send(inputs)
		client.send({"cmd":"pose","position":[pos.x,pos.y,pos.z],"mode":_mode(),"threat":looming,"fps":Engine.get_frames_per_second()})
	_update_hud()

func _move_fly(dt: float) -> void:
	escape_time = maxf(0,escape_time-dt)
	if resting:
		rest_time -= dt
		if rest_time <= 0:
			resting = false
			landing = false
			since_flight = 0
			destination = Vector3(rng.randf_range(-7,7),rng.randf_range(3,8),rng.randf_range(-5,5))
			vel = Vector3(0,3,0)
	else:
		since_flight += dt
		since_target += dt
		if since_flight > 22 and not landing and escape_time <= 0:
			landing = true
			destination = food.position+Vector3(0,0.80,0) if food_on else Vector3(pos.x,0.56,pos.z)
		if not landing and escape_time <= 0 and (since_target > 4.5 or pos.distance_to(destination)<1.4):
			since_target = 0
			destination = Vector3(rng.randf_range(-9,9),rng.randf_range(2,9),rng.randf_range(-6,6))
		var dir = (destination-pos).normalized()
		var speed = 2.8 + float(brain.get("flight",0))*2.0
		if landing: speed = minf(3.0,maxf(0.5,pos.distance_to(destination)*1.3))
		if escape_time > 0:
			speed = 10.5
		else:
			dir = dir.rotated(Vector3.UP,float(brain.get("turn",0))*0.30)
		var desired = dir*speed
		if escape_time > 0: desired = vel.normalized()*speed
		# Boundary forces are body constraints; they are not neural responses.
		for axis in [0,2]:
			var bound = 10.7 if axis==0 else 7.7
			if absf(pos[axis]) > bound-1.3:
				desired[axis] -= signf(pos[axis])*maxf(0,absf(pos[axis])-(bound-1.3))*7.0
		if pos.y > 9.6: desired.y -= (pos.y-9.6)*12
		if pos.y < 1.2 and not landing: desired.y += (1.2-pos.y)*8
		vel = vel.lerp(desired,1-exp(-dt*3.0))
		pos += vel*dt
		pos.x = clampf(pos.x,-10.9,10.9)
		pos.z = clampf(pos.z,-7.9,7.9)
		pos.y = clampf(pos.y,0.55,10.5)
		if landing and pos.distance_to(destination)<0.20:
			resting = true
			pos = destination
			vel = Vector3.ZERO
			rest_time = rng.randf_range(6,11)
		if Vector2(vel.x,vel.z).length()>0.1:
			heading = lerp_angle(heading,atan2(-vel.x,-vel.z),1-exp(-dt*9))
	fly.position = pos
	fly.rotation = Vector3(clampf(-vel.y*0.045,-0.45,0.45),heading,sin(clock*2.0)*0.04 if not resting else 0)
	get_node("FlyShadow").position = Vector3(pos.x,0.018,pos.z)

func _move_threat(dt: float) -> void:
	looming = 0.0
	if threat_time < 0: return
	threat_time += dt
	if threat_time < 1.7:
		var t = threat_time/1.7
		threat.position = threat_from.lerp(threat_to,t)
		threat.scale = Vector3.ONE*lerpf(0.45,1.1,t)
		# Loom signal approximates angular expansion of an approaching object.
		looming = clampf(0.12+t*t*0.95,0,1)
	elif threat_time < 2.3:
		threat.scale = Vector3.ONE*maxf(0.01,1.1*(2.3-threat_time)/0.6)
	else:
		threat.visible = false
		threat_time = -1

func _animate(_dt: float) -> void:
	for i in range(wings.size()):
		var side = -1.0 if i==0 else 1.0
		wings[i].rotation.z = side*(0.18 if resting else sin(clock*170)*0.60)
		wings[i].rotation.y = side*(-0.80 if resting else 0.06)
	for i in range(legs.size()):
		legs[i].rotation.x = sin(clock*5+i)*0.08 if resting else 0.38

func _update_camera(dt: float) -> void:
	var target = pos if following else Vector3(0,3.6,0)
	camera_target = camera_target.lerp(target,1-exp(-dt*4))
	var dist = minf(distance,11.0) if following else distance
	camera.position = camera_target + Vector3(sin(orbit)*cos(elevation),sin(elevation),cos(orbit)*cos(elevation))*dist
	camera.look_at(camera_target)

func _mode() -> String:
	if not _connected(): return "connecting"
	if brain.get("loading",false): return "loading"
	if paused: return "paused"
	if escape_time > 0: return "escape"
	if resting: return "resting"
	if landing: return "landing"
	return "flying"

func _update_hud() -> void:
	var names = {"loading":"Загрузка режима…","connecting":"Подключение к модели…","paused":"Пауза","escape":"Испуг · побег","resting":"Отдыхает","landing":"Заходит на посадку","flying":"В полёте"}
	status_label.text = "●  " + names[_mode()]
	status_label.modulate = Color("f1b397") if escape_time > 0 else Color.WHITE
	info_label.text = "Высота %.1f  ·  Побегов %d" % [pos.y,escape_count]
	if neural_panel.visible:
		var rates = brain.get("rates",{})
		neural_label.text = "НЕЙРОННАЯ МОДЕЛЬ\n\n%s нейронов\n%s связей между парами\n\nLC4 / LPLC2:  %.1f / %.1f Гц\nGF (DNp01):  %.1f Гц\nИмпульсы GF:  %d\nПобеги:  %d\n\nСкорость: %.0f / 500 шагов/с\n%s\n\nСвязи: MaleCNS v1.0\nДинамика: приближение LIF\nПолёт: процедурная механика" % [str(int(brain.get("neurons",0))),str(int(brain.get("edges",0))),float(rates.get("loom_L",0)),float(rates.get("loom_R",0)),float(rates.get("GF",0)),int(brain.get("gf_spikes",0)),escape_count,float(brain.get("sps",0)),str(brain.get("kernel","…"))]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if client: client.send({"cmd":"quit"})
		get_tree().quit()
