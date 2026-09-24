extends Node3D
## Timed sensory probes. These evoke the neural model, not learned behavior.
var host: Node3D
var panel: PanelContainer
var intensity = 0.65
var timers = {"odor_a":0.0,"odor_b":0.0,"touch":0.0,"vibration":0.0,"heat":0.0}
var moving_light = false
var cycling = false
var cycle_time = 0.0
var cycle_index = 0
var elapsed = 0.0
var glow: Node3D
var glow_light: OmniLight3D
var particles: Array[Node3D] = []
var effect_material: StandardMaterial3D
var description: Label
var strength_label: Label

func _ready() -> void:
	host = get_parent()
	glow = Node3D.new()
	add_child(glow)
	var mat = host.material(Color("e9e6a0"))
	mat.emission_enabled = true
	mat.emission = Color("c1e2ac")
	mat.emission_energy_multiplier = 0.6
	host.ellipsoid(glow,Vector3.ZERO,Vector3(0.16,0.16,0.16),mat)
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color("d9e8ad")
	glow_light.light_energy = 0.45
	glow_light.omni_range = 5
	glow.add_child(glow_light)
	glow.visible = false
	effect_material = host.material(Color(0.7,0.5,0.85,0.45))
	for i in range(18):
		var p = host.ellipsoid(self,Vector3.ZERO,Vector3.ONE*0.1,effect_material)
		p.visible = false
		particles.append(p)

func build_ui(root: Control) -> void:
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -358
	panel.offset_right = -38
	panel.offset_top = 153
	panel.add_theme_stylebox_override("panel",host._style(Color(0.06,0.13,0.11,0.96),Color("405e51")))
	root.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation",10)
	panel.add_child(content)
	content.add_child(host._label("ОПЫТЫ  ·  E",19,Color("96d5be")))
	content.add_child(host._label("Открой мозг [B] и сравни ответ",13))
	strength_label = host._label("Сила воздействия: 65%",14)
	content.add_child(strength_label)
	var slider = HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = intensity
	slider.value_changed.connect(func(value):
		intensity = value
		strength_label.text = "Сила воздействия: %d%%" % int(value*100))
	content.add_child(slider)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	content.add_child(grid)
	for entry in [["firefly","Подвижный свет"],["touch","Прикосновение"],["odor_a","Запах A"],["odor_b","Запах B"],["vibration","Вибрация"],["heat","Тепло"],["sequence","Цикл опытов"],["stop_stimuli","Убрать всё"]]:
		var b = Button.new()
		b.text = entry[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size",14)
		b.pressed.connect(action.bind(entry[0]))
		grid.add_child(b)
	description = host._label("Воздействия выключены",13,Color("a9c0b2"))
	content.add_child(description)
	content.add_child(host._label("1/2 — запахи  ·  T — касание\nV — вибрация  ·  H — тепло\nL — движущийся свет",12,Color("88a293")))
	panel.visible = false

func action(name: String) -> void:
	if name=="experiments":
		panel.visible = not panel.visible
		return
	if host.paused or not host._connected(): return
	if timers.has(name):
		timers[name] = 6.0 if name.begins_with("odor") else 2.0
	elif name=="firefly": moving_light = not moving_light
	elif name=="sequence":
		cycling = not cycling
		cycle_time = 0
	elif name=="stop_stimuli":
		for key in timers: timers[key] = 0
		moving_light = false
		cycling = false
	_update_description()

func _update_description() -> void:
	if not description: return
	var active = []
	var names = {"odor_a":"запах A","odor_b":"запах B","touch":"касание","vibration":"вибрация","heat":"тепло"}
	for key in timers:
		if timers[key]>0: active.append(names[key])
	if moving_light: active.append("свет")
	if cycling: active.append("цикл")
	description.text = "Сейчас: "+", ".join(active) if active.size() else "Воздействия выключены"

func tick(dt: float) -> void:
	elapsed += dt
	for key in timers: timers[key] = maxf(0,timers[key]-dt)
	if cycling:
		cycle_time -= dt
		if cycle_time<=0:
			var actions = ["odor_a","odor_b","touch","vibration","heat","scare"]
			var current = actions[cycle_index%actions.size()]
			if current=="scare": host._scare()
			else: action(current)
			cycle_index += 1
			cycle_time = 8
	glow.visible = moving_light
	glow.position = Vector3(cos(elapsed*0.65)*6,4+sin(elapsed*0.8)*2,sin(elapsed*0.65)*5)
	var type = ""
	for key in timers:
		if timers[key]>0: type = key
	var colors = {"odor_a":Color(0.68,0.46,0.92,0.55),"odor_b":Color(0.36,0.82,0.68,0.55),
		"touch":Color(0.91,0.79,0.50,0.65),"vibration":Color(0.5,0.75,0.86,0.60),"heat":Color(0.95,0.49,0.28,0.50)}
	if colors.has(type): effect_material.albedo_color = colors[type]
	for i in range(particles.size()):
		particles[i].visible = type!=""
		if type=="": continue
		var phase = fmod(elapsed*0.8+i*0.08,1.0)
		var center = host.pos if not type.begins_with("odor") else host.food.position+Vector3(0,0.3,0)
		var radius = 0.5+phase*1.8
		particles[i].position = center+Vector3(cos(i*2.4)*radius,phase*2.4,sin(i*2.4)*radius)
		particles[i].scale = Vector3.ONE*0.10*(0.4+intensity)*(1-phase*0.7)
	_update_description()

func sensory(position: Vector3, heading: float) -> Dictionary:
	var result: Dictionary = {}
	for key in timers:
		result[key] = intensity*minf(1.0,timers[key]*3.0)
	if moving_light:
		var relative = glow.position-position
		var side = relative.normalized().dot(Vector3(cos(heading),0,-sin(heading)))
		var gain = intensity*clampf(1.3-relative.length()/16,0.1,1.0)
		result.light_L = gain*clampf(0.5-side*0.5,0,1)
		result.light_R = gain*clampf(0.5+side*0.5,0,1)
	return result
