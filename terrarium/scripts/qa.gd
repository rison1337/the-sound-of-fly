extends SceneTree
## Integration check against a separate, real MaleCNS service.
var scene: Node
var evidence: Dictionary = {}
var output: String

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func check(value: bool, description: String) -> void:
	evidence[description] = value
	if not value: push_error("QA: " + description)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../logs/qa")
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	var deadline = Time.get_ticks_msec()+15000
	while not scene._connected() and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene._connected(),"connected_to_real_model")
	if not scene._connected():
		quit(1)
		return
	await create_timer(3).timeout
	await capture("01_overview")
	var start_y = scene.pos.y
	await create_timer(3).timeout
	check(absf(scene.pos.y-start_y)>0.2,"changes_altitude")
	await key(KEY_F)
	check(scene.following,"follow_key")
	await create_timer(1.0).timeout
	await capture("02_follow")
	await key(KEY_B)
	check(scene.brain_view!=null and scene.brain_view.visible,"brain_window_key")
	deadline = Time.get_ticks_msec()+10000
	while not scene.brain_view.loaded and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene.brain_view.loaded,"real_soma_cloud_loaded")
	check(scene.brain_view.positions.size()==165122,"row_alignment_matches_graph")
	check(scene.brain_view.base_mesh.instance_count==140024,"only_measured_somas_drawn")
	check(scene.brain_view.arbor_instances.size()==20,"real_arbors_loaded")
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	scene.brain_view.get_texture().get_image().save_png(output.path_join("06_brain_baseline.png"))
	await key(KEY_P)
	var pause_pos = scene.pos
	await create_timer(0.3).timeout
	var pause_sim = float(scene.brain.get("sim_time",0))
	await create_timer(0.5).timeout
	check(scene.pos.distance_to(pause_pos)<0.001,"pause_stops_body")
	check(absf(float(scene.brain.get("sim_time",0))-pause_sim)<0.01,"pause_stops_brain")
	await capture("03_neural_panel")
	await key(KEY_P)
	deadline = Time.get_ticks_msec()+45000
	while not scene.resting and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene.resting,"lands_and_rests")
	await capture("04_landed")
	var escape_before = scene.escape_count
	var gf_before = int(scene.brain.get("gf_spikes",0))
	await key(KEY_SPACE)
	check(scene.threat.visible,"space_starts_visible_object")
	deadline = Time.get_ticks_msec()+4000
	while scene.escape_count == escape_before and Time.get_ticks_msec()<deadline:
		await create_timer(0.025).timeout
	check(scene.escape_count>escape_before,"neural_escape_after_loom")
	check(int(scene.brain.get("gf_spikes",0))>gf_before,"gf_spikes_after_loom")
	check(not scene.resting,"scare_triggers_takeoff")
	await create_timer(0.20).timeout
	await capture("05_escape")
	evidence["state_after_scare"] = scene.brain
	for action in ["food","light"]:
		scene.buttons[action].pressed.emit()
		check(not scene.get(action+"_on"),action+"_button_off")
		scene.buttons[action].pressed.emit()
		check(scene.get(action+"_on"),action+"_button_on")
	# New sensory probes must reach the real neural service and its 3D view.
	var sensory_checks = {}
	for action in ["odor_a","odor_b","touch","vibration","heat"]:
		scene._action("stop_stimuli")
		scene.brain_view.find_child("Probe_"+action,true,false).pressed.emit()
		check(scene.experiments.timers[action]>0,action+"_brain_button_works")
		await create_timer(0.9).timeout
		var rate = float(scene.brain.get("rates",{}).get(action,0))
		sensory_checks[action] = rate
		check(rate>10,action+"_evokes_neurons")
		check(scene.brain_view.shown_active>0,action+"_has_live_3d_activity")
		await RenderingServer.frame_post_draw
		scene.brain_view.get_texture().get_image().save_png(output.path_join("brain_"+action+".png"))
	evidence["sensory_rates_hz"] = sensory_checks
	scene._action("firefly")
	await create_timer(0.6).timeout
	check(scene.experiments.glow.visible,"moving_light_visible")
	check(maxf(float(scene.brain.sensory.get("light_L",0)),float(scene.brain.sensory.get("light_R",0)))>0,"moving_light_reaches_retinal_groups")
	var angle = scene.brain_view.orbit
	scene.brain_view.orbit += 0.5
	scene.brain_view._update_camera()
	check(scene.brain_view.orbit!=angle,"brain_camera_rotates")
	scene.brain_view._filter(3)
	await RenderingServer.frame_post_draw
	scene.brain_view.get_texture().get_image().save_png(output.path_join("brain_filtered.png"))
	scene.brain_view._filter(0)
	scene._action("experiments")
	check(scene.experiments.panel.visible,"experiment_panel_opens")
	await capture("07_experiments")
	scene._action("stop_stimuli")
	await create_timer(0.7).timeout
	check(not scene.experiments.moving_light and not scene.experiments.cycling,"stimuli_stop")
	check(float(scene.brain.sensory.get("heat",0))==0.0,"stimulus_input_clears")
	check(scene.brain_view.samples>3,"live_chart_updates")
	# Switching to the current-based model must preserve the working application.
	scene.brain_view.profile_choice.item_selected.emit(1)
	deadline = Time.get_ticks_msec()+15000
	while scene.brain.get("profile","")!="research" and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene.brain.get("profile","")=="research","research_profile_switch")
	check(float(scene.brain.get("dt_ms",0))==0.2,"research_time_step")
	await create_timer(2.0).timeout
	scene._scare()
	deadline = Time.get_ticks_msec()+14000
	while scene.escape_count==0 and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene.escape_count>0,"research_profile_escape")
	evidence["research_speed_ratio"] = scene.brain.get("speed_ratio",0)
	scene.brain_view._focus("brain")
	await RenderingServer.frame_post_draw
	scene.brain_view.get_texture().get_image().save_png(output.path_join("08_research_arbors.png"))
	scene.brain_view.profile_choice.item_selected.emit(0)
	deadline = Time.get_ticks_msec()+15000
	while scene.brain.get("profile","")!="interactive" and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	check(scene.brain.get("profile","")=="interactive","return_to_interactive_profile")
	evidence["fps"] = Engine.get_frames_per_second()
	var f = FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(evidence,"  "))
	f.close()
	var passed = true
	for value in evidence.values():
		if value is bool and not value: passed = false
	print("TERRARIUM QA ", "PASS" if passed else "FAIL")
	scene.client.send({"cmd":"quit"})
	quit(0 if passed else 1)
