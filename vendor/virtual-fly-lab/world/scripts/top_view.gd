extends Window
## Top-down orthographic view. LMB places the selected stimulus, RMB removes
## the nearest one. Toolbar selects the stimulus kind.

const ARENA_HALF := 36.0
const KIND_RANGE := {"light": 20.0, "odor": 16.0, "heat": 10.0, "sound": 16.0, "taste": 12.0}

var main: Node3D
var kind := "light"
var _vp: SubViewport
var _buttons := {}
var _stim_list: Label


func _ready() -> void:
	title = "Top view — LMB: place, RMB: remove"
	size = Vector2i(560, 600)

	var c := SubViewportContainer.new()
	c.name = "C"
	c.size = Vector2(560, 600)
	c.stretch = true
	add_child(c)
	_vp = SubViewport.new()
	c.add_child(_vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 84.0
	cam.position = Vector3(0, 50, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.far = 140.0
	_vp.add_child(cam)
	cam.current = true

	c.gui_input.connect(_on_vp_input)
	_build_toolbar()

	_stim_list = Label.new()
	_stim_list.position = Vector2(8, size.y - 110)
	_stim_list.add_theme_font_size_override("font_size", 12)
	_stim_list.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_child(_stim_list)
	_stim_list.text = "no stimuli placed"


func update_stims(stims: Dictionary, fly_pos: Vector3, yaw: float) -> void:
	# client-side estimate of each placed stimulus' live intensity and side
	var lines := PackedStringArray()
	var rx := sin(yaw)
	var rz := cos(yaw)
	for id in stims:
		var rec: Dictionary = stims[id]
		var kind: String = rec["kind"]
		var pos: Vector3 = (rec["node"] as Node3D).position
		var vx := pos.x - fly_pos.x
		var vz := pos.z - fly_pos.z
		var d := Vector2(vx, vz).length()
		var rng: float = KIND_RANGE.get(kind, 12.0)
		var inten: float = maxf(0.0, 0.9 * (1.0 - d / rng))
		if inten <= 0.0:
			lines.append("%s #%d   %.0f m   out of range" % [kind, id, d])
		else:
			var lat := (vx * rx + vz * rz) / maxf(d, 0.001)
			var side := "R" if lat > 0.2 else ("L" if lat < -0.2 else "C")
			lines.append("%s #%d   %.0f m   drive %.2f   %s" % [kind, id, d, inten, side])
	_stim_list.text = "\n".join(lines) if lines.size() > 0 else "no stimuli placed"


func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 8)
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for k in ["light", "odor", "heat", "sound", "taste"]:
		var b := Button.new()
		b.text = k
		b.toggle_mode = true
		b.button_pressed = k == kind
		b.pressed.connect(_select.bind(k))
		_buttons[k] = b
		bar.add_child(b)


func _select(k: String) -> void:
	kind = k
	for key in _buttons:
		(_buttons[key] as Button).button_pressed = key == k


func _on_vp_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var cam := _vp.get_camera_3d()
		var origin := cam.project_ray_origin(ev.position)
		var dir := cam.project_ray_normal(ev.position)
		if absf(dir.y) < 1e-5:
			return
		var t := (1.2 - origin.y) / dir.y
		if t < 0.0:
			return
		var p := origin + dir * t
		p.x = clampf(p.x, -ARENA_HALF, ARENA_HALF)
		p.z = clampf(p.z, -ARENA_HALF, ARENA_HALF)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			main.place_stim(kind, Vector2(p.x, p.z))
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			main.remove_stim_near(Vector2(p.x, p.z))
