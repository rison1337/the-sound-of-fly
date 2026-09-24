extends MultiMeshInstance2D
## One independently addressed GPU quad per model neuron.
var shader_material := ShaderMaterial.new()
var cell_count := 0

func _ready() -> void:
	shader_material.shader=preload("res://shaders/spikes.gdshader")
	material=shader_material

func configure(count: int, texture: Texture2D) -> void:
	shader_material.set_shader_parameter("neural_frame",texture)
	if cell_count==count: return
	cell_count=count
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data=true
	multimesh.mesh=mesh
	multimesh.instance_count=count
	var data := PackedFloat32Array()
	data.resize(count*12)
	for i in range(count):
		var offset := i*12
		data[offset]=1.
		data[offset+5]=1.
		# Compatibility stores custom channels as half floats. Two small exact
		# integer coordinates preserve all 165122 identities without overflow.
		data[offset+8]=float(i%512)
		data[offset+9]=float(i/512)
	multimesh.buffer=data
	multimesh.custom_aabb=AABB(Vector3(-10000,-10000,-1),Vector3(20000,20000,2))

func update_art(view_size: Vector2, phase: float, shot: int, lens: int, palette: int, density: float) -> void:
	shader_material.set_shader_parameter("view_size",view_size)
	shader_material.set_shader_parameter("phase",phase)
	shader_material.set_shader_parameter("shot",float(shot))
	shader_material.set_shader_parameter("lens",lens)
	shader_material.set_shader_parameter("palette",palette)
	shader_material.set_shader_parameter("density",density)
