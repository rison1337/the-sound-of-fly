extends RefCounted
## Diagnostic export only. No PNG compression or contact-sheet construction
## runs on the display thread. Input Images are handed over exclusively.
var worker := Thread.new()
var destination := ""
var export_error := ""
const DIGITS := ["111101101101111","010110010010111","111001111100111","111001111001111","101101111001001","111100111001111","111100111101111","111001001001001","111101111101111","111101111001111"]

func start(path: String, frames: Array[Image], records: Array[Dictionary]) -> void:
	destination=path
	var result := worker.start(_write.bind(path,frames,records))
	if result!=OK: export_error="Cannot start QA writer: %s"%result

func _number(canvas: Image, value: int, at: Vector2i) -> void:
	var x := at.x
	for c in str(value):
		var glyph: String=DIGITS[int(c)]
		for y in range(5):
			for col in range(3):
				if glyph[y*3+col]=="1": canvas.fill_rect(Rect2i(x+col*2,at.y+y*2,2,2),Color(.85,.89,.95))
		x+=8

func _write(path: String, frames: Array[Image], records: Array[Dictionary]) -> void:
	var result := DirAccess.make_dir_recursive_absolute(path)
	if result!=OK: export_error="Cannot create QA directory: %s"%result; return
	var overview := Image.create(1920,1400,false,Image.FORMAT_RGB8)
	overview.fill(Color(.035,.04,.05))
	var detail: Image
	for i in range(frames.size()):
		if frames[i]==null: continue
		if frames[i].save_png(path.path_join("frame_%03d.png"%i))!=OK:
			export_error="Frame export failed: %d"%i; return
		if i%25==0:
			detail=Image.create(1600,1100,false,Image.FORMAT_RGB8); detail.fill(Color(.035,.04,.05))
		var image := frames[i]
		image.convert(Image.FORMAT_RGB8)
		image.resize(320,200,Image.INTERPOLATE_BILINEAR)
		var origin := Vector2i((i%5)*320,((i%25)/5)*220)
		detail.blit_rect(image,Rect2i(0,0,320,200),origin)
		_number(detail,i,origin+Vector2i(5,204))
		_number(detail,int(records[i].world_id),origin+Vector2i(68,204))
		_number(detail,int(records[i].view_id),origin+Vector2i(124,204))
		if i%25==24 or i==frames.size()-1:
			detail.save_png(path.path_join("contact_%02d.png"%(i/25)))
		if i<100:
			image.resize(192,120,Image.INTERPOLATE_BILINEAR)
			origin=Vector2i((i%10)*192,(i/10)*140)
			overview.blit_rect(image,Rect2i(0,0,192,120),origin)
			_number(overview,i,origin+Vector2i(4,124))
			_number(overview,int(records[i].world_id),origin+Vector2i(68,124))
			_number(overview,int(records[i].view_id),origin+Vector2i(124,124))
	overview.save_png(path.path_join("contact_overview.png"))
	var output := FileAccess.open(path.path_join("sequence.json"),FileAccess.WRITE)
	if output==null: export_error="Cannot write QA metadata"; return
	output.store_string(JSON.stringify({"frames":records,"interval_target_ms":100,"duration_target_s":10,"sheet_labels":["frame_index","world_id","view_id"],"export_thread":true},"\t"))

func finish() -> void:
	if worker.is_started(): worker.wait_to_finish()
