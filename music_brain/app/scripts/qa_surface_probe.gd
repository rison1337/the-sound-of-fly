extends SceneTree
## Deterministic, offline diagnosis at a soundtrack time. Run with the same
## project / asset-root / ensemble-map arguments as the normal preview.
var destination := ""
var target := 99.4
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-out="): destination=arg.trim_prefix("--probe-out=")
		if arg.begins_with("--probe-at="): target=arg.trim_prefix("--probe-at=").to_float()
	call_deferred("run")
func capture(app: Control,name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(destination.path_join(name+".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.content_scale_size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var app=load("res://main.tscn").instantiate()
	root.add_child(app); app.set_process(false)
	app.top.visible=false; app.bottom.visible=false; app.brain.visible=false
	app.ui_visible=false; app.playback_started=true; app.playback_paused=true
	for frame in range(int(ceil(target*30.))+1):
		app.playback_time=minf(float(frame)/30.,target)
		app._process(1./30.)
		await process_frame
		await RenderingServer.frame_post_draw
	await capture(app,"all")
	var stage=app.spatial_stage
	stage.viewport.get_texture().get_image().save_png(destination.path_join("stage.png"))
	print("PROBE ",target," ",stage.descriptor," parts=",stage.part_count)
	for i in range(stage.part_count):
		print("PART ",i," kind=",stage.part_kind[i]," identity=",stage.surface_identity[i]," pose=",stage.graph.resolved[i])
	for kind in range(5):
		for j in range(5): stage.batches[j].visible_instance_count=stage.counts[j] if j==kind else 0
		await capture(app,"kind-"+str(kind))
	for j in range(5): stage.batches[j].visible_instance_count=0
	stage.batches[0].visible_instance_count=stage.counts[0]
	for material in stage.materials: material.set_shader_parameter("memory_valid",0.)
	await capture(app,"no-memory")
	for material in stage.materials: material.set_shader_parameter("cells_ready",0.)
	await capture(app,"no-cells")
	for material in stage.materials: material.set_shader_parameter("fold",0.)
	await capture(app,"flat")
	print("PROBE_DONE ",destination)
	quit()
