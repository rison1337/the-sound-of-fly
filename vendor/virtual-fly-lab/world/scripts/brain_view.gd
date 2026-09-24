extends Window
## Separate window: whole-CNS point cloud (165k neurons), active ones light up,
## plus a scrolling oscilloscope of the global firing rate.

const CLOUD_CENTER := Vector3(0, -60, -250)
const DIM := Color(0.33, 0.37, 0.44)

var _mm: MultiMesh
var _info: Label
var _cam: Camera3D
var _lit: Array[int] = []
var _samples: Array[float] = []
var _chart: Control


func _ready() -> void:
	title = "Brain — 165,122 neurons"
	size = Vector2i(470, 780)

	var c := SubViewportContainer.new()
	c.size = Vector2(470, 780)
	c.stretch = true
	add_child(c)
	var vp := SubViewport.new()
	c.add_child(vp)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.position = CLOUD_CENTER + Vector3(0, -3, 54)
	vp.add_child(_cam)
	_cam.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	_cam.environment = env
	_cam.look_at_from_position(_cam.position, CLOUD_CENTER + Vector3(0, 1, 0), Vector3.UP)

	_info = Label.new()
	_info.position = Vector2(12, 84)
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_info)
	_info.text = "loading positions..."

	_chart = Control.new()
	_chart.position = Vector2(0, 26)
	_chart.size = Vector2(470, 54)
	_chart.draw.connect(_draw_chart)
	add_child(_chart)

	build_cloud()


func build_cloud() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://data/soma_positions_f32.bin")
	var f := bytes.to_float32_array()
	var count := f.size() / 3

	var mesh := SphereMesh.new()
	mesh.radius = 0.085
	mesh.height = 0.17
	mesh.radial_segments = 6
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = count

	const CHUNK := 20000
	var hidden_xf := Transform3D(Basis().scaled(Vector3.ZERO), CLOUD_CENTER)
	for i0 in range(0, count, CHUNK):
		var i1 := mini(i0 + CHUNK, count)
		for i in range(i0, i1):
			var p := Vector3(f[i * 3], f[i * 3 + 1], f[i * 3 + 2])
			if p == Vector3.ZERO:
				_mm.set_instance_transform(i, hidden_xf)
				_mm.set_instance_color(i, Color(0, 0, 0, 0))
			else:
				_mm.set_instance_transform(i, Transform3D(Basis(), p + CLOUD_CENTER))
				_mm.set_instance_color(i, DIM)
		await get_tree().process_frame

	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	get_parent().add_child(mi)
	_info.text = "%s neurons" % _comma(count)


func update_cloud(cloud: Array) -> void:
	if _mm == null:
		return
	# reset the previous frame's lit neurons to dim first, so activity reads as
	# instantaneous instead of accumulating
	for i in _lit:
		_mm.set_instance_color(i, DIM)
	_lit.clear()
	for e in cloud:
		var idx := int(e[0])
		var t := clampf(float(e[1]) / 100.0, 0.0, 1.0)
		_mm.set_instance_color(idx, Color(1.0, 1.0 - 0.45 * t, 0.7 - 0.45 * t))
		_lit.append(idx)
	_info.text = "active shown: %d   (dim = silent)" % cloud.size()


func push_sample(hz_global: float) -> void:
	_samples.append(hz_global)
	while _samples.size() > 160:
		_samples.pop_front()
	_chart.queue_redraw()


func _draw_chart() -> void:
	var w := _chart.size.x
	var h := _chart.size.y
	_chart.draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.6))
	_chart.draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.4, 0.5), false, 1.0)
	if _samples.size() < 2:
		return
	var maxv: float = maxf(_samples.max(), 1.0)
	var pts := PackedVector2Array()
	for i in _samples.size():
		var x := w * i / (_samples.size() - 1.0)
		var y := h - 3.0 - (h - 8.0) * clampf(_samples[i] / maxv, 0.0, 1.0)
		pts.append(Vector2(x, y))
	_chart.draw_polyline(pts, Color(1.0, 0.8, 0.3), 1.5)
	_chart.draw_string(
		ThemeDB.fallback_font, Vector2(6, 12),
		"global firing rate  %d Hz  (12 s)" % int(_samples[-1]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.95)
	)


func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
