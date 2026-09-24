extends Control
## Diagnostic-only traces. The green curve samples the actual articulation
## sent to shaders; it is not an assumed copy of the attack schedule.
const ROLES := ["IMPACT","BASS","SNARE","DETAIL","LEAD","BED"]
const CAPACITY := 640
var report: Dictionary={}
var calibration: Array=[]
var clock := 0.
var samples := PackedFloat32Array()
var sample_times := PackedFloat32Array()
var cursor := 0
var font: Font=ThemeDB.fallback_font

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	samples.resize(CAPACITY*6); sample_times.resize(CAPACITY); sample_times.fill(-100.)

func load_project(directory: String, timing: Array) -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("sync_report.json")))
	if data is Dictionary: report=data
	calibration=timing

func sample(t: float, motion: PackedFloat32Array) -> void:
	clock=t
	for role in range(6): samples[cursor*6+role]=motion[role]
	sample_times[cursor]=t; cursor=(cursor+1)%CAPACITY
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.035,.055,.96))
	draw_string(font,Vector2(16,22),"SYNC / orange: attack   cyan: downstream response   green: actual object articulation",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(.82,.88,1.))
	var x0 := 120.; var width := size.x-x0-20.
	var start := clock-2.; var span := 3.
	var row_height := (size.y-45.)/6.
	var levels: Array=report.get("levels",[])
	var step_s := float(report.get("step_s",.02))
	for role in range(6):
		var y := 43.+role*row_height
		var floor_y := y+row_height*.76
		draw_string(font,Vector2(16,y+12),ROLES[role],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(.8,.85,.95))
		if calibration.size()==6:
			draw_string(font,Vector2(16,y+28),"peak %d ms"%int(calibration[role].peak_ms),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(.5,.6,.75))
		draw_line(Vector2(x0,floor_y),Vector2(x0+width,floor_y),Color(.17,.21,.28))
		var points := PackedVector2Array()
		for frame in range(maxi(0,int(start/step_s)),mini(levels.size(),int((start+span)/step_s)+1)):
			var row: Array=levels[frame][role]
			points.append(Vector2(x0+(frame*step_s-start)/span*width,floor_y-(float(row[0])*.35+float(row[1])*.65)*row_height*.62))
		if points.size()>1: draw_polyline(points,Color(.3,.8,1.),1.4,true)
		points.clear()
		for k in range(CAPACITY):
			var i := (cursor+k)%CAPACITY
			var t := sample_times[i]
			if t<start or t>clock: continue
			points.append(Vector2(x0+(t-start)/span*width,floor_y-samples[i*6+role]*row_height*.62))
		if points.size()>1: draw_polyline(points,Color(.65,1.,.32),1.8,true)
		for event in report.get("events",[]):
			var t := float(event.source_time)
			if int(event.voice)!=role or t<start or t>start+span: continue
			var x := x0+(t-start)/span*width
			draw_line(Vector2(x,y),Vector2(x,floor_y),Color(1.,.5,.2,.65))
	var now_x := x0+2./span*width
	draw_line(Vector2(now_x,32),Vector2(now_x,size.y-10),Color(1.,1.,1.,.8),1.)
