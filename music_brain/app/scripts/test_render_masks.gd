extends SceneTree
## GPU check: run without --headless. Tests the actual shared shader include,
## All editorial phases must preserve a complete frame, including transitions.
var failures := 0

func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(128,80); viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := ColorRect.new(); rect.size=Vector2(128,80)
	var shader := Shader.new()
	shader.code='shader_type canvas_item;\n#include "res://shaders/editorial_mask.gdshaderinc"\nvoid fragment(){float m=editorial_paper(UV);COLOR=vec4(vec3(m),1.);}'
	var material := ShaderMaterial.new(); material.shader=shader
	rect.material=material; viewport.add_child(rect)
	for old in range(5):
		for next in range(5):
			material.set_shader_parameter("previous_presentation",float(old))
			material.set_shader_parameter("presentation",float(next))
			for progress in [0.,.25,.5,.75,1.]:
				material.set_shader_parameter("mask_progress",progress)
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var partial := 0; var mean := 0.
				for y in range(80):
					for x in range(128):
						var value := image.get_pixel(x,y).r
						mean+=value
						if value>.03 and value<.97: partial+=1
				check(partial==0,"Editorial view contains a translucent mask")
				if next in [0,2,4]: check(mean<.1,"Spatial construction was clipped by a screen mask")
				else: check(mean>128*80-.1,"Print view leaks pieces of spatial geometry")
	viewport.queue_free()
	print("RENDER_MASKS failures=",failures)
	quit(0 if failures==0 else 1)
