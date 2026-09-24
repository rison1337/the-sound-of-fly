extends MultiMeshInstance2D
const GlyphAtlas=preload("res://scripts/glyph_atlas.gd")
var shader_material := ShaderMaterial.new()
var atlas_view: SubViewport

func _ready() -> void:
	shader_material.shader=preload("res://shaders/events.gdshader")
	material=shader_material
	var quad := QuadMesh.new()
	quad.size=Vector2.ONE
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data=true
	multimesh.mesh=quad
	multimesh.instance_count=512
	var transforms := PackedFloat32Array()
	transforms.resize(512*12)
	for i in range(512):
		transforms[i*12]=1.; transforms[i*12+5]=1.
		transforms[i*12+8]=float(i)
	multimesh.buffer=transforms
	multimesh.custom_aabb=AABB(Vector3(-10000,-10000,-1),Vector3(20000,20000,2))
	atlas_view=SubViewport.new()
	atlas_view.size=Vector2i(3072,1536)
	atlas_view.transparent_bg=true
	atlas_view.disable_3d=true
	atlas_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(atlas_view)
	var atlas := GlyphAtlas.new()
	atlas.size=Vector2(3072,1536)
	atlas_view.add_child(atlas)
	shader_material.set_shader_parameter("glyph_atlas",atlas_view.get_texture())

func configure(event_texture: Texture2D, neural_texture: Texture2D) -> void:
	shader_material.set_shader_parameter("event_frame",event_texture)
	shader_material.set_shader_parameter("ensemble_frame",neural_texture)

func render_events(clock: float, screen_size: Vector2, descriptor: Dictionary, transition: float=1.0) -> void:
	shader_material.set_shader_parameter("event_clock",clock)
	shader_material.set_shader_parameter("view_size",screen_size)
	shader_material.set_shader_parameter("world_light",1. if int(descriptor.get("background",0))==1 else 0.)
	shader_material.set_shader_parameter("palette_seed",float(descriptor.get("palette",0)))
	shader_material.set_shader_parameter("scene_transition",transition)
