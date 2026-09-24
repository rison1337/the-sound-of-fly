extends Control

const BrainPanel = preload("res://scripts/brain_panel.gd")
const EventRenderer = preload("res://scripts/event_renderer.gd")
const Recording = preload("res://scripts/recording.gd")
const SpikeField = preload("res://scripts/spike_field.gd")
const VisualEvents = preload("res://scripts/visual_events.gd")
const SpatialStage = preload("res://scripts/spatial_stage.gd")
const QAExport = preload("res://scripts/qa_export.gd")
var events := VisualEvents.new()
const GRAMMARS = ["TYPE", "RASTER", "SPACE", "CHROME", "DATA", "TRACE", "GLITCH"]
var recording := Recording.new()
var project_path := ""
var player := AudioStreamPlayer.new()
var playback_time := 0.
var simulation_time := 0.
var timeline_ready := false
var playback_started := false
var playback_paused := false
var startup_frames := 0
var export_port := 0
var export_fps := 60.
var export_index := 0
var export_busy := false
var export_width := 1920
var export_height := 1080
var export_tcp := StreamPeerTCP.new()
var export_brain := false
var export_frames := 0
var export_ack_pending := false
var neural_texture: ImageTexture
var ensemble_texture: ImageTexture
var ensembles := PackedFloat32Array()
var ensemble_bursts := PackedFloat32Array()
var ensemble_phases := PackedFloat32Array()
var ensemble_pixels := PackedFloat32Array()
var ensemble_image: Image
var target_ensembles := PackedFloat32Array()
var target_bursts := PackedFloat32Array()
var target_phases := PackedFloat32Array()
var event_baselines := PackedFloat32Array()
var display_hz := 60.0
var display_check := 0.0
var stream_age_ms := 0.0
var first_frame := true
var ready_started := 0
var metric_clock := 0.0
var packet_ages: Array[float]=[]
var last_sim := 0.0
var spike_field: MultiMeshInstance2D
var last_packet := -100.0
var last_seq := -1
var state := {}
var neural_phase := 0.0
var palette := 0
var palette_auto := true
var intensity := 1.0
var floating_spikes := false
var expanded := false
var ui_visible := true
var shader_material: ShaderMaterial
var editorial_materials: Array[ShaderMaterial]=[]
var artwork: ColorRect
var event_renderer: MultiMeshInstance2D
var spatial_stage: TextureRect
var previous_frame_us := 0
var frame_gap_max_ms := 0.
var brain: PanelContainer
var top: PanelContainer
var bottom: PanelContainer
var settings: PanelContainer
var status: Label
var scene_label: Label
var stats: Label
var pause_button: Button
var density_label: Label
var connection_notice: Label
var menu_open := false
var grammar_buttons: Array[Button] = []
var qa_elapsed := 0.0
var qa_capture := ""
var qa_expanded := false
var qa_art_only := false
var qa_sequence := ""
var qa_sequence_clock := 0.0
var qa_sequence_index := 0
var qa_sequence_busy := false
var qa_images: Array[Image]=[]
var qa_records: Array[Dictionary]=[]
var qa_export: RefCounted
var sync_panel: Control
var diagnostics_requested := false
var sync_offset_ms := 0.
var stem_selector: OptionButton

func _ready() -> void:
	ready_started=Time.get_ticks_msec()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_sync_refresh_rate()
	DisplayServer.window_set_min_size(Vector2i(1024,640))
	var font := SystemFont.new()
	font.font_names=PackedStringArray(["Bahnschrift","Arial"])
	theme=Theme.new()
	theme.default_font=font
	theme.default_font_size=14
	for state_name in ["normal","hover","pressed","focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color=Color("202838") if state_name!="normal" else Color("0f141e")
		button_style.set_content_margin_all(10)
		button_style.set_corner_radius_all(3)
		button_style.border_color=Color("6075a6") if state_name=="pressed" else Color("2a3243")
		button_style.set_border_width_all(1)
		theme.set_stylebox(state_name,"Button",button_style)
		theme.set_stylebox(state_name,"OptionButton",button_style)
	artwork=ColorRect.new()
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shader_material=ShaderMaterial.new()
	shader_material.shader=preload("res://shaders/visual.gdshader")
	artwork.material=shader_material
	add_child(artwork)
	spatial_stage=SpatialStage.new()
	spatial_stage.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(spatial_stage)
	ensembles.resize(256)
	ensemble_bursts.resize(256)
	ensemble_phases.resize(256)
	ensemble_pixels.resize(1024)
	target_ensembles.resize(256)
	target_bursts.resize(256)
	target_phases.resize(256)
	event_baselines.resize(256)
	ensemble_image=Image.create_from_data(16,16,false,Image.FORMAT_RGBAF,ensemble_pixels.to_byte_array())
	ensemble_texture=ImageTexture.create_from_image(ensemble_image)
	spatial_stage.configure_neural(ensemble_texture)
	shader_material.set_shader_parameter("ensemble_frame",ensemble_texture)
	shader_material.set_shader_parameter("populations",ensemble_texture)
	shader_material.set_shader_parameter("trajectory",spatial_stage.shape_texture)
	shader_material.set_shader_parameter("voices",events.voices.texture)
	spatial_stage.configure_voices(events.voices.texture)
	spike_field=SpikeField.new()
	add_child(spike_field)
	event_renderer=EventRenderer.new()
	add_child(event_renderer)
	editorial_materials=[shader_material,event_renderer.shader_material,spike_field.shader_material,spatial_stage.transition_material]
	event_renderer.configure(events.texture,ensemble_texture)
	event_renderer.shader_material.set_shader_parameter("scene_anchors",spatial_stage.anchor_texture)
	spike_field.shader_material.set_shader_parameter("scene_anchors",spatial_stage.anchor_texture)
	_build_header()
	_build_footer()
	brain=BrainPanel.new()
	brain.expansion_requested.connect(_toggle_brain)
	add_child(brain)
	_build_settings()
	sync_panel=preload("res://scripts/sync_panel.gd").new()
	sync_panel.visible=false; add_child(sync_panel)
	connection_notice=_label("Loading neural response…",18,Color("bacbfb"))
	connection_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(connection_notice)
	resized.connect(_layout)
	_layout()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--project="): project_path=arg.trim_prefix("--project=")
		if arg.begins_with("--export-port="): export_port=arg.trim_prefix("--export-port=").to_int()
		if arg.begins_with("--export-fps="): export_fps=arg.trim_prefix("--export-fps=").to_float()
		if arg.begins_with("--export-width="): export_width=arg.trim_prefix("--export-width=").to_int()
		if arg.begins_with("--export-height="): export_height=arg.trim_prefix("--export-height=").to_int()
		if arg=="--export-brain": export_brain=true
		if arg=="--diagnostic": diagnostics_requested=true
		if arg.begins_with("--qa-capture="): qa_capture=arg.trim_prefix("--qa-capture=")
		if arg=="--qa-expanded": qa_expanded=true
		if arg=="--qa-art-only": qa_art_only=true
		if arg.begins_with("--qa-sequence="):
			qa_sequence=arg.trim_prefix("--qa-sequence=")
			qa_images.resize(101)
			qa_records.resize(101)
		if arg.begins_with("--ensemble-map="):
			var map_bytes := FileAccess.get_file_as_bytes(arg.trim_prefix("--ensemble-map="))
			if map_bytes.size()>0 and map_bytes.size()%512==0:
				var map_texture := ImageTexture.create_from_image(Image.create_from_data(512,map_bytes.size()/512,false,Image.FORMAT_R8,map_bytes))
				spike_field.shader_material.set_shader_parameter("ensemble_map",map_texture)
				spatial_stage.configure_ensemble_map(map_texture)
	add_child(player)
	if qa_art_only:
		ui_visible=false; top.visible=false; bottom.visible=false; brain.visible=false
	if recording.open(project_path):
		events.voices.configure_timing(recording.voice_release)
		for stem in ["drums","bass","vocals","other"]:
			if FileAccess.file_exists(recording.directory.path_join("stems/"+stem+".wav")): stem_selector.add_item(stem.capitalize())
		if diagnostics_requested: _toggle_diagnostics()
		player.stream=AudioStreamWAV.load_from_file(recording.directory.path_join("audio.wav"))
		if player.stream==null:
			connection_notice.text="Cannot load project audio"; return
		_prime_design()
		timeline_ready=true
		status.text=recording.manifest.source_name
		if export_port>0:
			export_frames=int(ceil(float(recording.manifest.duration)*export_fps))
			# Render at the requested size independently of the desktop resolution.
			get_tree().root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
			get_tree().root.content_scale_size=Vector2i(export_width,export_height)
			DisplayServer.window_set_min_size(Vector2i(64,64))
			DisplayServer.window_set_size(Vector2i(960,540))
			brain.set_presentation(true)
			call_deferred("_layout")
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps=0
			export_tcp.connect_to_host("127.0.0.1",export_port)
			ui_visible=false; top.visible=false; bottom.visible=false; brain.visible=export_brain
	else:
		connection_notice.text=recording.error
		push_error(recording.error)

func _label(text: String,font_size:=14,color:=Color("dce3f4")) -> Label:
	var result := Label.new()
	result.text=text
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	return result

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color=Color("090d15ed")
	style.set_content_margin_all(12)
	style.border_color=Color("2a3243")
	style.set_border_width_all(1)
	p.add_theme_stylebox_override("panel",style)
	return p

func _button(text: String, callback: Callable, hint: String="") -> Button:
	var b := Button.new()
	b.text=text
	b.focus_mode=Control.FOCUS_NONE
	b.tooltip_text=hint
	b.pressed.connect(callback)
	return b

func _build_header() -> void:
	top=_panel()
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	top.add_child(row)
	var title := VBoxContainer.new()
	row.add_child(title)
	title.add_child(_label("DROFFEL / MUSIC BRAIN",18))
	title.add_child(_label("SOUND → NEURONS → IMAGE",10,Color("8392b1")))
	var spacer := Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	status=_label("CONNECTING",12,Color("96adff"))
	row.add_child(status)
	row.add_child(_button("Settings",_toggle_settings))
	row.add_child(_button("Fullscreen",_fullscreen,"F11"))

func _build_footer() -> void:
	bottom=_panel()
	add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	bottom.add_child(row)
	for i in range(GRAMMARS.size()):
		var b := _button(GRAMMARS[i],func(): _toggle_grammar(i),"Toggle grammar / %d"%(i+1))
		grammar_buttons.append(b)
		row.add_child(b)
	scene_label=_label("VISUAL EVENTS",11,Color("a1b6f2"))
	scene_label.visible=false
	scene_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(scene_label)
	stats=_label("",11,Color("7d8ca8"))
	row.add_child(stats)
	pause_button=_button("Pause",_toggle_pause,"Space")
	row.add_child(pause_button)
	row.add_child(_button("Restart",func(): get_tree().reload_current_scene()))
	row.add_child(_button("Hide UI",_toggle_ui,"Tab brings controls back"))

func _build_settings() -> void:
	settings=_panel()
	settings.visible=false
	add_child(settings)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	settings.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var heading := _label("SIGNAL / SETTINGS",16)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	row.add_child(_button("Close",_toggle_settings))
	column.add_child(_label("PRECOMPUTED MUSIC / FIXED BRAIN",11,Color("8798bd")))
	column.add_child(_button("Show / hide sync traces",_toggle_diagnostics,"D"))
	stem_selector=OptionButton.new(); stem_selector.add_item("Full mix")
	stem_selector.item_selected.connect(_audition_stem)
	column.add_child(stem_selector)
	var prefs := ConfigFile.new(); prefs.load("user://preview.cfg")
	sync_offset_ms=float(prefs.get_value("preview","offset_ms",0.))
	var offset_label := _label("Preview visual offset: %.0f ms (+ = earlier)"%sync_offset_ms,12)
	column.add_child(offset_label)
	var offset_slider := HSlider.new()
	offset_slider.min_value=-200.; offset_slider.max_value=200.; offset_slider.step=5.; offset_slider.value=sync_offset_ms
	offset_slider.value_changed.connect(func(value):
		sync_offset_ms=value; offset_label.text="Preview visual offset: %.0f ms (+ = earlier)"%value
		prefs.set_value("preview","offset_ms",value); prefs.save("user://preview.cfg"))
	column.add_child(offset_slider)
	column.add_child(_label("Use Music Studio to choose audio, process it,\npreview and export an MP4.",13))
	density_label=_label("Visual density   1.00×",13)
	column.add_child(density_label)
	var density := HSlider.new()
	density.min_value=.2; density.max_value=3.; density.step=.05; density.value=intensity
	density.value_changed.connect(func(value): intensity=value; density_label.text="Visual density   %.2f×"%value)
	column.add_child(density)
	var spike_toggle := CheckButton.new()
	spike_toggle.text="Floating spike traces"
	spike_toggle.tooltip_text="Optional overlay. Cell-driven surface deformation stays active."
	spike_toggle.button_pressed=floating_spikes
	spike_toggle.toggled.connect(func(value): floating_spikes=value)
	column.add_child(spike_toggle)
	column.add_child(_label("PALETTE",11,Color("8798bd")))
	var colors := OptionButton.new()
	for name in ["Neural / per composition","Violet / ink / paper","Cobalt / ink / paper","Lime / ink / paper","Signal red / ink / paper"]: colors.add_item(name)
	colors.item_selected.connect(func(index): palette_auto=index==0; palette=maxi(0,index-1))
	column.add_child(colors)
	var description := _label("An artificial sensory interface to the fly model.\nThe art follows simulated neural activity.\nAudio stays on this computer.",12,Color("98a4bd"))
	column.add_child(description)
	column.add_child(_label("B  expand brain     Tab  hide controls\n1–7  grammar     Space  pause     F11  fullscreen",12,Color("7988a5")))

func _layout() -> void:
	if top==null: return
	top.position=Vector2(20,14)
	top.size=Vector2(size.x-40,62)
	bottom.position=Vector2(20,size.y-62)
	bottom.size=Vector2(size.x-40,48)
	if brain!=null:
		if export_port>0:
			var inset := size.x*.022
			brain.size=Vector2(size.x*.165,size.x*.113)
			brain.position=Vector2(size.x-brain.size.x-inset,inset)
		else:
			brain.position=Vector2(40,96) if expanded else Vector2(size.x-364,98)
			brain.size=Vector2(size.x-80,size.y-182) if expanded else Vector2(344,290)
	if settings!=null:
		settings.position=Vector2(size.x-430,86)
		settings.size=Vector2(410,620)
	if sync_panel!=null:
		sync_panel.position=Vector2(24,maxf(100.,size.y-435.)); sync_panel.size=Vector2(size.x-48.,355.)
	if connection_notice!=null: connection_notice.position=Vector2(48,size.y-122)
	shader_material.set_shader_parameter("aspect",size.x/maxf(1.,size.y))

func _process(delta: float) -> void:
	var frame_us := Time.get_ticks_usec()
	if previous_frame_us>0: frame_gap_max_ms=maxf(frame_gap_max_ms,(frame_us-previous_frame_us)/1000.)
	previous_frame_us=frame_us
	metric_clock+=delta
	if metric_clock>=5. and not packet_ages.is_empty():
		packet_ages.sort()
		print("RENDER fps=",Engine.get_frames_per_second()," display_hz=",display_hz," state_age_median_ms=",snappedf(packet_ages[packet_ages.size()/2],.1)," state_age_p95_ms=",snappedf(packet_ages[int(packet_ages.size()*.95)],.1)," events=",events.live_count," births=",events.births_total," triggers=",events.trigger_count," trigger_births=",events.trigger_births)
		packet_ages.clear()
		metric_clock=0.
		print("FRAME_GAP max_ms=",snappedf(frame_gap_max_ms,.1)," shot=",events.scene_descriptor.get("name","loading")," phase=",events.scene_stage)
		frame_gap_max_ms=0.
	display_check+=delta
	if display_check>2. and export_port==0:
		_sync_refresh_rate()
		display_check=0.
	if not timeline_ready: return
	startup_frames+=1
	if export_port>0:
		export_tcp.poll()
		if export_tcp.get_status()!=StreamPeerTCP.STATUS_CONNECTED: return
		if export_ack_pending:
			if export_tcp.get_available_bytes()<1: return
			export_tcp.get_data(1); export_ack_pending=false
		if export_busy: return
		if export_index>=export_frames: get_tree().quit(); return
		playback_time=float(export_index)/export_fps
	elif not playback_started:
		# Compile/create the scene before audible playback begins.
		_step_recording(0.)
		if startup_frames>45:
			player.play(); playback_started=true
	elif not playback_paused:
		var clock_time := player.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
		playback_time=maxf(playback_time,clampf(clock_time+sync_offset_ms/1000.,0.,float(recording.manifest.duration)))
		if not player.playing: playback_time=float(recording.manifest.duration); playback_paused=true
	_step_recording(playback_time)
	if export_port>0 and export_brain: brain.animate_presentation(playback_time)
	var now := Time.get_ticks_msec()/1000.
	var paused := playback_paused
	connection_notice.visible=false
	status.text="%s  /  %.1f / %.1f s"%[recording.manifest.source_name,playback_time,recording.manifest.duration]
	pause_button.text="Resume" if playback_paused else "Pause"
	events.density=intensity
	events.palette_override=-1 if palette_auto else palette
	events.upload()
	var descriptor: Dictionary=events.scene_descriptor
	var scene_palette := int(descriptor.get("palette",0)) if palette_auto else palette
	shader_material.set_shader_parameter("background",float(descriptor.get("background",0)))
	shader_material.set_shader_parameter("topology",float(descriptor.get("topology",0)))
	shader_material.set_shader_parameter("palette",float(scene_palette))
	shader_material.set_shader_parameter("polarity",1. if events.view_polarity else 0.)
	shader_material.set_shader_parameter("progress",events.scene_progress)
	shader_material.set_shader_parameter("graphic_mode",float(descriptor.get("graphic_mode",0))+events.material_shift)
	shader_material.set_shader_parameter("layout_mode",float(descriptor.get("layout_mode",0)))
	shader_material.set_shader_parameter("view_index",float(events.view_index))
	shader_material.set_shader_parameter("history_view",spatial_stage.memories[spatial_stage.memory_read].get_texture())
	shader_material.set_shader_parameter("history_valid",1. if spatial_stage.memory_valid else 0.)
	shader_material.set_shader_parameter("morph",float(descriptor.get("short_memory",.5)))
	shader_material.set_shader_parameter("edit_kind",float(events.edit_kind))
	shader_material.set_shader_parameter("edit_age",events.view_age)
	shader_material.set_shader_parameter("edit_strength",events.edit_strength)
	shader_material.set_shader_parameter("anticipation",events.voices.prepare_amount)
	event_renderer.render_events(events.clock,size,descriptor,events.scene_transition)
	event_renderer.shader_material.set_shader_parameter("palette_seed",float(scene_palette))
	spatial_stage.update_scene(events,size,ensembles,ensemble_bursts,ensemble_phases)
	for mat in editorial_materials:
		mat.set_shader_parameter("presentation",float(events.editorial.presentation))
		mat.set_shader_parameter("framing_shape",events.editorial.crop)
		mat.set_shader_parameter("previous_presentation",float(events.editorial.mask_from))
		mat.set_shader_parameter("previous_framing",events.editorial.mask_crop)
		mat.set_shader_parameter("mask_progress",events.editorial.mask_progress())
		mat.set_shader_parameter("editorial_aspect",size.x/maxf(size.y,1.))
	spatial_stage.set_cell_age(maxf(0.,playback_time-last_sim))
	spike_field.update_art(size,float(state.get("sim_time",0.)),events.world_seed,0,scene_palette,intensity)
	spike_field.shader_material.set_shader_parameter("world_light",1. if int(descriptor.get("background",0))==1 else 0.)
	# Local cell-driven bumps remain depth-tested on the surfaces. The optional
	# canvas scatter cannot share the 3D depth buffer, so keep it off by default.
	spike_field.visible=floating_spikes and events.enabled[5]==1
	spike_field.shader_material.set_shader_parameter("between_frames",maxf(0.,playback_time-last_sim))
	spike_field.shader_material.set_shader_parameter("ensemble_frame",ensemble_texture)
	# Individual spikes remain visible as neural traces, but never become a
	# full-screen dust layer competing with the shot's spatial composition.
	spike_field.shader_material.set_shader_parameter("trace_fraction",clampf(.004+events.tension*.008+events.surge*.015,.004,.028))
	scene_label.text=str(descriptor.get("name",""))
	# Scene names are metadata, not part of the visual artwork.
	scene_label.visible=false
	stats.tooltip_text="Recorded full neural state / sample-clock playback\n"+str(recording.manifest.get("separation",""))
	stats.text="%d FPS / %.0f Hz"%[Engine.get_frames_per_second(),display_hz]
	if export_port>0: _export_frame()
	if not qa_sequence.is_empty():
		# Sample the soundtrack clock. Screenshot readback must not pause the
		# sampling clock and stretch a requested 10 seconds into a longer clip.
		qa_sequence_clock=playback_time
		if not qa_sequence_busy and qa_sequence_clock>=6.+qa_sequence_index*.1: _capture_sequence_frame()
	if qa_export!=null and not qa_export.worker.is_alive():
		qa_export.finish()
		print("QA_SEQUENCE ",qa_export.destination," frames=101 interval_target_ms=100 export_error=",qa_export.export_error)
		qa_export=null
	if not qa_capture.is_empty():
		qa_elapsed+=delta
		if qa_elapsed>6.:
			var destination := qa_capture
			qa_capture=""
			if qa_expanded:
				expanded=true
				_layout()
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(destination)
			print("QA_CAPTURE "+destination)
			print("QA_BRAIN viewport=",brain.viewport.size," camera=",brain.camera.position," target=",brain.target)

func _accept_state(value: Dictionary, frame: PackedByteArray) -> void:
	var width := int(value.get("frame_width",0))
	var height := int(value.get("frame_height",0))
	if width!=512 or height<1 or height>2048: return
	if value.get("frame_encoding","raw")=="deflate":
		if int(value.get("frame_raw_bytes",0))!=width*height*4: return
		frame=frame.decompress(width*height*4,FileAccess.COMPRESSION_DEFLATE)
	if frame.size()!=width*height*4: return
	state=value
	events.voices.observe(state.get("neural_voices",[]),state.get("voice_owners",[]))
	stream_age_ms=maxf(0.,(Time.get_unix_time_from_system()-float(state.get("published_unix",Time.get_unix_time_from_system())))*1000.)
	packet_ages.append(stream_age_ms)
	if first_frame:
		first_frame=false
		print("FIRST_NEURAL_FRAME startup_ms=",Time.get_ticks_msec()-ready_started," display_hz=",display_hz)
	last_seq=int(state.seq)
	last_packet=Time.get_ticks_msec()/1000.
	var neural_image := Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,frame)
	if neural_texture==null:
		neural_texture=ImageTexture.create_from_image(neural_image)
		spike_field.configure(int(state.get("neurons",165122)),neural_texture)
		brain.set_neural_texture(neural_texture)
		spatial_stage.configure_cells(neural_texture)
	else:
		neural_texture.update(neural_image)
	_update_ensembles()
	brain.update_state(state)

func _update_ensembles() -> void:
	var rates: Array=state.get("ensembles",[])
	var spikes: Array=state.get("ensemble_spikes",[])
	var populations: Array=state.get("ensemble_sizes",[])
	if rates.size()!=256 or spikes.size()!=256: return
	var sim := float(state.get("sim_time",0.))
	var elapsed := clampf(sim-last_sim,0.,.1) if last_seq>0 else .02
	last_sim=sim
	for i in range(256):
		var population := float(populations[i]) if populations.size()==256 else 500.
		var confidence := sqrt(minf(1.,population/32.))
		var a := (1.-exp(-maxf(float(rates[i])-.03,0.)/5.))*confidence
		var current := float(spikes[i])/maxf(1.,population)/maxf(.02,elapsed)
		var burst := clampf((current-event_baselines[i])/maxf(3.,event_baselines[i])*.35,0.,1.)*confidence
		if elapsed>0.:
			event_baselines[i]=lerpf(event_baselines[i],current,1.-exp(-elapsed/.4))
			target_bursts[i]=maxf(burst,target_bursts[i]*exp(-elapsed/.08))
		target_ensembles[i]=a
		target_phases[i]+=elapsed*(a*1.8+target_bursts[i]*2.)
	events.ingest(target_ensembles,target_bursts,target_phases,state.get("neural_bands",[]),[],elapsed)

func _animate_populations(delta: float) -> void:
	# The model publishes at its own cadence; motion is resampled every display
	# frame. This short exponential interpolation adds no frame queue.
	var blend := 1.-exp(-delta*55.)
	for i in range(256):
		ensembles[i]=lerpf(ensembles[i],target_ensembles[i],blend)
		ensemble_bursts[i]=lerpf(ensemble_bursts[i],target_bursts[i],blend)
		ensemble_phases[i]=lerpf(ensemble_phases[i],target_phases[i],blend)
		ensemble_pixels[i*4]=ensembles[i]
		ensemble_pixels[i*4+1]=ensemble_bursts[i]
		ensemble_pixels[i*4+2]=ensemble_phases[i]
		ensemble_pixels[i*4+3]=1.
	ensemble_image.set_data(16,16,false,Image.FORMAT_RGBAF,ensemble_pixels.to_byte_array())
	ensemble_texture.update(ensemble_image)

func _sync_refresh_rate() -> void:
	display_hz=DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	if display_hz<30.: display_hz=60.
	Engine.max_fps=int(ceil(display_hz))

func _toggle_grammar(index: int) -> void:
	events.toggle_grammar(index)
	grammar_buttons[index].modulate=Color.WHITE if events.enabled[index] else Color("555b68")

func _capture_sequence_frame() -> void:
	qa_sequence_busy=true
	await RenderingServer.frame_post_draw
	qa_images[qa_sequence_index]=get_viewport().get_texture().get_image()
	# Snapshot the visual identity along with the actual sampling time.
	qa_records[qa_sequence_index]={"frame":qa_sequence_index,"wall_ms":Time.get_ticks_msec(),"event_time":events.clock,"events":events.live_count,"births":events.births_total,"deaths":events.deaths_total,"by_kind":Array(events.count_by_kind),"triggers":events.trigger_count,"trigger_births":events.trigger_births,"fps":Engine.get_frames_per_second(),"state_age_ms":stream_age_ms,"input_db":state.get("input_db",-120.),"world_id":events.scene_serial,"view_id":events.view_serial,"family":events.scene_descriptor.get("name",""),"progress":events.scene_progress,"phase":events.scene_stage,"operation":events.operation,"graph_nodes":events.graph.count,"graph_phase":events.graph.phase,"parts":spatial_stage.part_count,"camera":str(spatial_stage.camera.position),"descriptor":events.scene_descriptor}
	qa_records[qa_sequence_index].merge({"audio_time":playback_time,"target_time":6.+qa_sequence_index*.1,"presentation":events.editorial.presentation,"editorial_serial":events.editorial.serial})
	qa_sequence_index+=1
	if qa_sequence_index>=101:
		qa_export=QAExport.new()
		qa_export.start(qa_sequence,qa_images,qa_records)
		qa_sequence=""
		# Replace the arrays instead of mutating storage owned by the worker.
		qa_images=[]; qa_records=[]
	qa_sequence_busy=false

func _toggle_settings() -> void:
	menu_open=not menu_open
	settings.visible=menu_open
	if menu_open: settings.move_to_front()

func _toggle_brain() -> void:
	expanded=not expanded
	brain.visible=true
	_layout()

func _toggle_pause() -> void:
	if playback_time>=float(recording.manifest.get("duration",0.)):
		get_tree().reload_current_scene(); return
	playback_paused=not playback_paused
	player.stream_paused=playback_paused

func _toggle_ui() -> void:
	ui_visible=not ui_visible
	top.visible=ui_visible
	bottom.visible=ui_visible
	if not ui_visible: settings.visible=false; menu_open=false

func _fullscreen() -> void:
	var full := DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode==KEY_F11: _fullscreen()
	elif event.keycode==KEY_TAB: _toggle_ui()
	elif event.keycode==KEY_B: _toggle_brain()
	elif event.keycode==KEY_D: _toggle_diagnostics()
	elif event.keycode==KEY_SPACE: _toggle_pause()
	elif event.keycode==KEY_ESCAPE:
		if menu_open: _toggle_settings()
		elif expanded: _toggle_brain()
	elif event.keycode>=KEY_1 and event.keycode<=KEY_7:
		_toggle_grammar(event.keycode-KEY_1)

func _prime_design() -> void:
	# A known recording can establish its opening composition from a real
	# neural trajectory, rather than starting every song from empty history.
	var values := PackedFloat32Array(); values.resize(256)
	var bursts := PackedFloat32Array(); bursts.resize(256)
	while recording.next_time()<minf(.8,float(recording.manifest.duration)):
		var packet := recording.read_next()
		if packet.is_empty(): break
		var data: Dictionary=packet[0]
		var rates: Array=data.get("ensembles",[])
		if rates.size()!=256: break
		for i in range(256): values[i]=1.-exp(-maxf(float(rates[i])-.03,0.)/5.)
		events.history.observe(values,bursts,data.get("neural_bands",[]),[],.02)
	recording.reset()

func _step_recording(target: float) -> void:
	# Fixed 120Hz composition integration: preview and export see the same score.
	while simulation_time<=target+.000001:
		var phrase := recording.phrase_at(simulation_time)
		events.set_phrase(phrase)
		while recording.next_time()<=simulation_time+.000001:
			var packet := recording.read_next()
			if packet.is_empty(): timeline_ready=false; return
			_accept_state(packet[0],packet[1])
		var timing := recording.timing_at(simulation_time)
		events.history.observe_timing(timing)
		events.articulate_events(timing)
		recording.prepare_voices(simulation_time,events.voices)
		var boundary := float(phrase.get("end",INF))
		events.voices.upcoming=boundary-simulation_time if is_finite(boundary) else -1.
		# Avoid adding one extra simulation tick at audio zero.
		if simulation_time>0.: events.advance(1./120.)
		if sync_panel.visible: sync_panel.sample(simulation_time,events.voices.motion)
		_animate_populations(1./120.)
		simulation_time+=1./120.

func _toggle_diagnostics() -> void:
	if sync_panel==null or recording.manifest.is_empty(): return
	if sync_panel.report.is_empty(): sync_panel.load_project(recording.directory,recording.voice_timing.get("calibration",[]))
	sync_panel.visible=not sync_panel.visible
	if sync_panel.visible: sync_panel.move_to_front()

func _audition_stem(index: int) -> void:
	if not timeline_ready: return
	var name := "audio.wav" if index==0 else "stems/"+stem_selector.get_item_text(index).to_lower()+".wav"
	var stream := AudioStreamWAV.load_from_file(recording.directory.path_join(name))
	if stream==null: return
	var position_s := player.get_playback_position()
	player.stream=stream; player.play(position_s); player.stream_paused=playback_paused

func _export_frame() -> void:
	export_busy=true
	if export_index%int(export_fps*2.)==0:
		print("RENDER_VIEW ",JSON.stringify({"time":playback_time,"world":events.scene_descriptor.get("topology",-1),"presentation":events.editorial.presentation,"view":events.view_index,"camera":str(spatial_stage.camera.position),"phrase":events.phrase_index,"stage":events.scene_stage,"choreography":events.scene_descriptor.get("choreography",{})}))
	if export_index==0:
		# The initial viewport resize and pooled mesh uploads need a rendered
		# frame before readback. Keep score time at zero during this warm-up;
		# never write an empty first video frame or advance the soundtrack.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	if image.get_width()!=export_width or image.get_height()!=export_height:
		push_error("Export viewport does not match requested native resolution")
		get_tree().quit(1); return
	if export_index==0:
		print("NATIVE_EXPORT ",image.get_width(),"x",image.get_height()," stage=",spatial_stage.viewport.size)
	var body := image.get_data()
	var header := PackedByteArray(); header.resize(4); header.encode_u32(0,body.size())
	if export_tcp.put_data(header)!=OK or export_tcp.put_data(body)!=OK:
		push_error("Export encoder disconnected"); get_tree().quit(1); return
	export_index+=1; export_busy=false; export_ack_pending=true


func _exit_tree() -> void:
	if qa_export!=null: qa_export.finish()
