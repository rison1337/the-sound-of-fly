extends Node3D
## Fly sandbox world: arena, virtual fly driven by the brain sim, stimulus
## objects, live brain panel, top-view placement window, brain x-ray window.
##
## Controls: 1..5 - place light/odor/heat/sound/taste ahead of the fly
##           arrows - orbit the camera, R - reset fly, C - clear stimuli
##           B / T - re-show brain / top windows, Esc - quit
##           (top view: LMB place, RMB remove)

const SIM_HOST := "127.0.0.1"
const SIM_PORT := 9876
const ARENA_HALF := 36.0
const KIND_COLORS := {
	"light": Color(1.0, 0.95, 0.55),
	"odor": Color(0.35, 1.0, 0.45),
	"heat": Color(1.0, 0.25, 0.1),
	"sound": Color(0.35, 0.7, 1.0),
	"taste": Color(1.0, 0.5, 0.8),
}

var client: Node
var brain_view: Node
var top_view: Node
var fly: Node3D
var fly_marker: MeshInstance3D
var wings: Array[MeshInstance3D] = []
var cam: Camera3D
var yaw := 0.0
var cam_yaw_off := 0.0
var cam_pitch := 0.35

var speed := 0.0
var turn := 0.0
var turn_smooth := 0.0
var active_pct := 0.0
var kernel := ""
var sim_connected := false
var time_sec := 0.0
var pose_timer := 0.0

var stim_nodes := {}  # id -> {node: Node3D, kind: String}
var next_stim_id := 1
var drops := {}  # drop id -> Node3D
var drop_next_id := 9000
var pulse_next_id := 5000
var score := 0
var score_label: Label
const DROP_COUNT := 5

var status_label: Label
var stim_label: Label
var top_label: Label
var hud: CanvasLayer
var heat_box: VBoxContainer
var heat_rows := {}
var speed_fg: ColorRect
var turn_fg: ColorRect


class Sparkline extends Control:
	## Tiny scrolling line chart, autoscaled to its own window.
	var data: PackedFloat32Array = []
	var cap := 90
	var col: Color

	func _init(c: Color) -> void:
		col = c
		custom_minimum_size = Vector2(70, 14)
		size = Vector2(70, 14)

	func push(v: float) -> void:
		data.append(v)
		if data.size() > cap:
			data = data.slice(data.size() - cap)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.45))
		if data.size() < 2:
			return
		var mx := 1e-6
		for v in data:
			mx = maxf(mx, v)
		var pts := PackedVector2Array()
		for i in data.size():
			var x := size.x * float(i) / float(cap - 1)
			var y := size.y - 1.0 - (size.y - 2.0) * (data[i] / mx)
			pts.append(Vector2(x, y))
		draw_polyline(pts, col, 1.0)


func spawn_drop() -> void:
	var id := drop_next_id
	drop_next_id += 1
	var node := _make_drop_node()
	node.position = Vector3(randf_range(-34, 34), 1.0, randf_range(-34, 34))
	add_child(node)
	drops[id] = node


func _make_drop_node() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 1.0, 0.65)
	m.emission_enabled = true
	m.emission = Color(0.4, 1.0, 0.5)
	m.emission_energy_multiplier = 1.6
	mi.material_override = m
	root.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.5)
	l.omni_range = 5.0
	l.light_energy = 1.0
	root.add_child(l)
	return root


func _check_drops() -> void:
	var collected: Array[int] = []
	for id in drops:
		var n: Node3D = drops[id]
		var d := Vector2(n.position.x - fly.position.x, n.position.z - fly.position.z).length()
		if d < 1.6:
			collected.append(id)
	for id in collected:
		_collect_drop(id)


func _collect_drop(id: int) -> void:
	var n: Node3D = drops[id]
	drops.erase(id)
	score += 1
	score_label.text = "score: %d" % score
	# taste pulse to the brain: the fly "tastes" the sugar it found
	var pulse_id := pulse_next_id
	pulse_next_id += 1
	client.send({
		"cmd": "add_stim", "id": pulse_id, "kind": "taste",
		"x": n.position.x, "z": n.position.z,
	})
	get_tree().create_timer(1.5).timeout.connect(
		func() -> void: client.send({"cmd": "remove_stim", "id": pulse_id})
	)
	# pickup flash, then respawn a new drop elsewhere
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(3.0, 3.0, 3.0), 0.25)
	tw.parallel().tween_property(n, "position:y", n.position.y + 1.5, 0.25)
	tw.tween_callback(n.queue_free)
	spawn_drop()


func _ready() -> void:
	_build_world()
	_build_hud()
	client = preload("res://scripts/sim_client.gd").new()
	client.name = "SimClient"
	add_child(client)
	client.state_updated.connect(_on_state)
	client.connection_changed.connect(func(c: bool) -> void: sim_connected = c)
	client.start(SIM_HOST, SIM_PORT)

	brain_view = preload("res://scripts/brain_view.gd").new()
	brain_view.name = "BrainView"
	add_child(brain_view)
	top_view = preload("res://scripts/top_view.gd").new()
	top_view.name = "TopView"
	add_child(top_view)
	top_view.main = self
	# native OS windows (embed_subwindows=false in project.godot): brain goes to
	# the LEFT of the main window when there is room, else chains right of top view
	var scr := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()
	)
	var w := get_window()
	var y0 := scr.position.y + 40
	var left_space := w.position.x - scr.position.x
	if left_space >= brain_view.size.x + 28:
		brain_view.position = Vector2i(
			clampi(
				w.position.x - brain_view.size.x - 12,
				scr.position.x + 8,
				scr.end.x - brain_view.size.x - 8
			),
			y0
		)
		top_view.position = Vector2i(
			clampi(
				w.position.x + w.size.x + 10,
				scr.position.x + 8,
				scr.end.x - top_view.size.x - 8
			),
			y0
		)
	else:
		var bx := clampi(
			w.position.x + w.size.x + 10,
			scr.position.x + 8,
			scr.end.x - top_view.size.x - 8
		)
		top_view.position = Vector2i(bx, y0)
		brain_view.position = Vector2i(
			clampi(
				bx + top_view.size.x + 10,
				scr.position.x + 8,
				scr.end.x - brain_view.size.x - 8
			),
			y0
		)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.6)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_HALF * 2.0 + 4.0, ARENA_HALF * 2.0 + 4.0)
	floor_mi.mesh = plane
	floor_mi.material_override = _checker_material()
	add_child(floor_mi)

	fly = _build_fly()
	fly.position = Vector3(0, 1.2, 0)
	add_child(fly)

	for i in DROP_COUNT:
		spawn_drop()

	# glowing disc under the fly: makes it visible in the top view
	fly_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.02
	fly_marker.mesh = disc
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.9, 0.4, 0.5)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.85, 0.3)
	dm.emission_energy_multiplier = 1.2
	fly_marker.material_override = dm
	fly_marker.position.y = 0.02
	add_child(fly_marker)

	cam = Camera3D.new()
	cam.fov = 72
	add_child(cam)
	cam.current = true
	cam.position = Vector3(-7, 4, 0)


func _checker_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
uniform float tile = 2.0;
uniform vec3 col_a : source_color = vec3(0.22, 0.24, 0.27);
uniform vec3 col_b : source_color = vec3(0.11, 0.12, 0.14);
void fragment() {
	vec2 cell = floor(wpos.xz / tile);
	float c = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(col_a, col_b, c);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _build_fly() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.34
	body.mesh = sphere
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.28, 0.18, 0.1)
	bm.metallic = 0.2
	body.material_override = bm
	root.add_child(body)

	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.4, 0.15)
		wing.mesh = pm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.85, 0.92, 1.0, 0.5)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wing.material_override = wm
		wing.position = Vector3(0, 0.04, side * 0.24)
		root.add_child(wing)
		wings.append(wing)

	var eye := OmniLight3D.new()
	eye.light_color = Color(1.0, 0.75, 0.35)
	eye.omni_range = 2.0
	eye.light_energy = 0.8
	eye.position = Vector3(0.25, 0.05, 0)
	root.add_child(eye)
	return root


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	status_label = _label(16)
	status_label.position = Vector2(16, 12)
	hud.add_child(status_label)

	score_label = _label(16)
	score_label.position = Vector2(16, 40)
	score_label.modulate = Color(0.6, 1.0, 0.7)
	hud.add_child(score_label)

	stim_label = _label(14)
	stim_label.position = Vector2(140, 40)
	stim_label.modulate = Color(1, 1, 0.7)
	hud.add_child(stim_label)

	var help := _label(13)
	help.text = "1..5 - place light/odor/heat/sound/taste   arrows - camera   R - reset   C - clear   B/T - windows   Esc - quit"
	help.position = Vector2(16, 64)
	help.modulate = Color(0.8, 0.85, 0.95)
	hud.add_child(help)

	top_label = _label(13)
	top_label.position = Vector2(1440 - 360, 12)
	top_label.size = Vector2(344, 260)
	hud.add_child(top_label)

	heat_box = VBoxContainer.new()
	heat_box.position = Vector2(16, 96)
	heat_box.add_theme_constant_override("separation", 2)
	hud.add_child(heat_box)

	# turn / speed indicator bars (top right, under the neuron leaderboard)
	var bars_x := 1440.0 - 360.0
	for cfg in [
		{"y": 208.0, "name": "speed", "col": Color(0.3, 0.9, 0.4)},
		{"y": 232.0, "name": "turn", "col": Color(0.4, 0.8, 1.0)},
	]:
		var cap := _label(12)
		cap.text = cfg["name"]
		cap.position = Vector2(bars_x, cfg["y"])
		hud.add_child(cap)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.position = Vector2(bars_x + 48, cfg["y"] + 2)
		bg.size = Vector2(160, 12)
		hud.add_child(bg)
		var fg := ColorRect.new()
		fg.color = cfg["col"]
		fg.position = Vector2.ZERO
		fg.size = Vector2(0, 12)
		bg.add_child(fg)
		if cfg["name"] == "speed":
			speed_fg = fg
		else:
			turn_fg = fg


func _label(sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_place_ahead("light")
			KEY_2:
				_place_ahead("odor")
			KEY_3:
				_place_ahead("heat")
			KEY_4:
				_place_ahead("sound")
			KEY_5:
				_place_ahead("taste")
			KEY_C:
				for id in stim_nodes.keys().duplicate():
					remove_stim(id)
			KEY_R:
				fly.position = Vector3(0, 1.2, 0)
				yaw = 0.0
			KEY_B:
				brain_view.visible = true
			KEY_T:
				top_view.visible = true
			KEY_ESCAPE:
				get_tree().quit()


func _place_ahead(kind: String) -> void:
	var dir := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var p := fly.position + dir * 6.0
	place_stim(kind, Vector2(p.x, p.z))


func place_stim(kind: String, at: Vector2) -> void:
	var id := next_stim_id
	next_stim_id += 1
	var node := _make_stim_node(kind)
	var y := 0.03 if kind == "heat" else 1.2
	node.position = Vector3(at.x, y, at.y)
	add_child(node)
	stim_nodes[id] = {"node": node, "kind": kind}
	client.send({"cmd": "add_stim", "id": id, "kind": kind, "x": at.x, "z": at.y})


func remove_stim(id: int) -> void:
	if not stim_nodes.has(id):
		return
	var rec: Dictionary = stim_nodes[id]
	rec["node"].queue_free()
	stim_nodes.erase(id)
	client.send({"cmd": "remove_stim", "id": id})


func remove_stim_near(at: Vector2) -> void:
	var best_id := -1
	var best_d := 2.5
	for id in stim_nodes:
		var pos: Vector3 = stim_nodes[id]["node"].position
		var d := Vector2(pos.x, pos.z).distance_to(at)
		if d < best_d:
			best_d = d
			best_id = id
	if best_id >= 0:
		remove_stim(best_id)


func _make_stim_node(kind: String) -> Node3D:
	var color: Color = KIND_COLORS.get(kind, Color.WHITE)
	if kind == "heat":
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.2
		cm.bottom_radius = 2.2
		cm.height = 0.05
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color.r, color.g, color.b, 0.85)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.4
		mi.material_override = m
		var root := Node3D.new()
		mi.position.y = 0.03
		root.add_child(mi)
		return root
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5 if kind == "light" else 0.35
	sm.height = sm.radius * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	root.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = 12.0
	l.light_energy = 4.0 if kind == "light" else 1.5
	root.add_child(l)
	return root


func _on_state(s: Dictionary) -> void:
	speed = float(s.get("speed", 0.0))
	turn = float(s.get("turn", 0.0))
	active_pct = float(s.get("active", 0.0))
	kernel = str(s.get("kernel", ""))
	if brain_view:
		brain_view.update_cloud(s.get("cloud", []))
		brain_view.push_sample(float(s.get("hz_global", 0.0)))
	if top_view:
		top_view.update_stims(stim_nodes, fly.position, yaw)
	# indicator bars
	if speed_fg:
		speed_fg.size = Vector2(160.0 * clampf(speed, 0.0, 1.0), 12)
	if turn_fg:
		var tw := 80.0 * absf(turn)
		turn_fg.size = Vector2(tw, 12)
		turn_fg.position = Vector2(80.0 if turn >= 0.0 else 80.0 - tw, 0.0)
		turn_fg.color = Color(0.4, 0.8, 1.0) if turn >= 0.0 else Color(1.0, 0.6, 0.3)
	var rates: Dictionary = s.get("rates", {})
	_update_heatmap(rates)
	var top: Array = s.get("top", [])
	var lines := PackedStringArray()
	lines.append("-- most active neurons --")
	for t in top:
		var name: String = t.get("type", "")
		if name.is_empty():
			name = "id:%d" % int(t.get("id", 0))
		lines.append("%-14s %6.1f Hz" % [name, float(t.get("hz", 0.0))])
	top_label.text = "\n".join(lines)


func _update_heatmap(rates: Dictionary) -> void:
	for key in rates:
		if not heat_rows.has(key):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(16, 16)
			var lbl := _label(12)
			lbl.custom_minimum_size = Vector2(230, 16)
			row.add_child(rect)
			row.add_child(lbl)
			var spark := Sparkline.new(Color(0.5, 0.9, 0.6))
			row.add_child(spark)
			heat_rows[key] = [rect, lbl, spark]
			heat_box.add_child(row)
		var hz: float = float(rates[key])
		var row2: Array = heat_rows[key]
		var lbl: Label = row2[1]
		lbl.text = "%-22s %7.2f Hz" % [key, hz]
		var t: float = clamp(hz / 60.0, 0.0, 1.0)
		(row2[0] as ColorRect).color = Color(0.15 + 0.85 * t, 0.9 - 0.7 * t, 0.2 * (1.0 - t))
		(row2[2] as Sparkline).push(hz)


func _process(delta: float) -> void:
	time_sec += delta
	for i in wings.size():
		wings[i].position.y = 0.04 + sin(time_sec * 42.0 + i * PI) * 0.06
	if Input.is_physical_key_pressed(KEY_LEFT):
		cam_yaw_off += 1.8 * delta
	if Input.is_physical_key_pressed(KEY_RIGHT):
		cam_yaw_off -= 1.8 * delta
	if Input.is_physical_key_pressed(KEY_UP):
		cam_pitch = minf(cam_pitch + 1.2 * delta, 1.3)
	if Input.is_physical_key_pressed(KEY_DOWN):
		cam_pitch = maxf(cam_pitch - 1.2 * delta, -0.1)

	var dir := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var vel := (0.3 + 8.0 * speed) * dir
	fly.position += vel * delta
	fly.position.y = 1.2 + sin(time_sec * 2.5) * 0.05
	fly_marker.position.x = fly.position.x
	fly_marker.position.z = fly.position.z
	# smooth the brain+reflex turn so signal jitter does not shake the camera
	turn_smooth = lerpf(turn_smooth, turn, minf(1.0, 8.0 * delta))
	yaw = wrapf(yaw - turn_smooth * 2.2 * delta, -PI, PI)
	fly.rotation.y = yaw
	# soft wall avoidance: past the soft radius, steer smoothly toward the
	# center instead of bouncing between hard edges
	var to_c := Vector2(-fly.position.x, -fly.position.z)
	var dist_c := to_c.length()
	var soft_r := ARENA_HALF - 5.0
	if dist_c > soft_r:
		var strength: float = clampf((dist_c - soft_r) / 5.0, 0.0, 1.0)
		var yaw_d := atan2(-to_c.y, to_c.x)  # forward=(cos yaw,-sin yaw)
		yaw = lerp_angle(yaw, yaw_d, minf(1.0, 3.0 * strength * delta))
	if abs(fly.position.x) > ARENA_HALF + 0.5 or abs(fly.position.z) > ARENA_HALF + 0.5:
		fly.position.x = clampf(fly.position.x, -ARENA_HALF - 0.5, ARENA_HALF + 0.5)
		fly.position.z = clampf(fly.position.z, -ARENA_HALF - 0.5, ARENA_HALF + 0.5)

	_check_drops()

	var planar := 7.0 * cos(cam_pitch)
	var cam_off := Vector3(-planar, 1.2 + 7.0 * sin(cam_pitch), 0).rotated(
		Vector3.UP, yaw + cam_yaw_off
	)
	cam.position = cam.position.lerp(fly.position + cam_off, minf(1.0, 4.0 * delta))
	cam.look_at(fly.position + Vector3(1.5, 0, 0).rotated(Vector3.UP, yaw))

	pose_timer -= delta
	if pose_timer <= 0.0:
		pose_timer = 0.1
		client.send({"cmd": "pose", "x": fly.position.x, "z": fly.position.z, "yaw": yaw})

	var st := "sim: %s   active: %.2f%%   speed: %.2f   turn: %+.2f   kernel: %s" % [
		"CONNECTED" if sim_connected else "waiting for sim (python -m sim)...",
		active_pct, speed, turn, kernel,
	]
	status_label.text = st
	var s := PackedStringArray()
	for id in stim_nodes:
		s.append(stim_nodes[id]["kind"])
	stim_label.text = "stimuli: " + (", ".join(s) if s.size() > 0 else "none")
