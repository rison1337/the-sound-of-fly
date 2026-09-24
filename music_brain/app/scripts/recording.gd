extends RefCounted
const PhraseDesign=preload("res://scripts/phrase_design.gd")
## Full population frames live on disk, with bounded per-record decompression.
var directory := ""
var manifest: Dictionary={}
var score: Dictionary={}
var voice_timing: Dictionary={}
var voice_release := PackedFloat32Array([.065,.110,.050,.026,.100,.350])
var voice_advances := PackedFloat32Array()
var role_events: Array=[]
var role_cursors := PackedInt32Array([0,0,0,0,0,0])
var index: Array=[]
var file: FileAccess
var cursor := 0
var event_cursor := 0
var boundary_cursor := 0
var phrase_cursor := 0
var error := ""

func open(path: String) -> bool:
	directory=path.get_base_dir()
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or not value.get("complete",false):
		error="Incomplete music project"; return false
	manifest=value
	if manifest.get("voice_readout","")!="connectome_downstream_calibrated_2_3_hop" or not manifest.get("voice_timing_calibrated",false):
		error="Reprocess this project: calibrated downstream timing is missing"; return false
	var table: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("index.json")))
	var timing: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("score.json")))
	var calibration: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("voice_timing.json")))
	if not table is Array or not timing is Dictionary or not calibration is Dictionary:
		error="Missing score or neural index"; return false
	index=table; score=timing; voice_timing=calibration
	# Cache each phrase's future musical cues once, outside the render loop.
	var attack_cursor := 0
	var attacks: Array=score.get("events",[])
	var phrases: Array=score.get("phrases",[])
	for i in range(phrases.size()):
		var local: Array=[]
		while attack_cursor<attacks.size() and float(attacks[attack_cursor].time)<float(phrases[i].end):
			if float(attacks[attack_cursor].time)>=float(phrases[i].start): local.append(attacks[attack_cursor])
			attack_cursor+=1
		phrases[i]["index"]=i
		phrases[i]["design_score"]=PhraseDesign.score(phrases[i],local)
	role_events=[[],[],[],[],[],[]]
	for event in score.get("events",[]): role_events[int(event.voice)].append(event)
	var rows: Array=voice_timing.get("calibration",[])
	voice_advances=PackedFloat32Array(voice_timing.get("advances_s",[]))
	if rows.size()==6:
		voice_release.resize(6)
		for i in range(6): voice_release[i]=clampf(float(rows[i].get("release_ms",voice_release[i]*1000.))/1000.,.018,1.2)
	file=FileAccess.open(directory.path_join("neural.bin"),FileAccess.READ)
	if file==null or index.is_empty(): error="Missing neural recording"; return false
	return true

func reset() -> void:
	cursor=0; event_cursor=0; boundary_cursor=0; phrase_cursor=0
	role_cursors.fill(0)

func next_time() -> float:
	return float(index[cursor].time) if cursor<index.size() else INF

func read_next() -> Array:
	if cursor>=index.size(): return []
	file.seek(int(index[cursor].offset)); cursor+=1
	var header_size := file.get_32(); var body_size := file.get_32()
	if header_size<1 or header_size>65536 or body_size>4194304:
		error="Invalid neural record"; return []
	var value: Variant=JSON.parse_string(file.get_buffer(header_size).get_string_from_utf8())
	var body := file.get_buffer(body_size)
	if not value is Dictionary or body.size()!=body_size:
		error="Truncated neural record"; return []
	return [value,body]

func timing_at(t: float) -> Array:
	var result: Array=[]
	var events: Array=score.get("events",[])
	while event_cursor<events.size() and float(events[event_cursor].time)<=t:
		var e: Dictionary=events[event_cursor]
		result.append({"id":e.id,"voice":e.voice,"age_ms":maxf(0.,t-float(e.time))*1000.,"neural_sample":e.get("neural_sample",[])})
		event_cursor+=1
	return result

func prepare_voices(t: float, voices: RefCounted) -> void:
	for voice in range(6):
		var events: Array=role_events[voice]
		while role_cursors[voice]<events.size() and float(events[role_cursors[voice]].time)<=t:
			role_cursors[voice]+=1
		voices.until_attack[voice]=100.; voices.next_strength[voice]=0.
		if role_cursors[voice]>=events.size(): continue
		var event: Dictionary=events[role_cursors[voice]]
		voices.until_attack[voice]=float(event.time)-t
		voices.prepare_s[voice]=float(event.get("prepare_s",.07))
		var sample: Array=event.get("neural_sample",[])
		if sample.size()==4: voices.next_strength[voice]=voices.response_strength(float(sample[0]),float(sample[1]))

func next_boundary() -> float:
	var boundaries: Array=score.get("boundaries",[])
	return float(boundaries[boundary_cursor]) if boundary_cursor<boundaries.size() else INF

func phrase_at(t: float) -> Dictionary:
	var phrases: Array=score.get("phrases",[])
	if phrases.is_empty(): return {"index":0,"start":0.,"end":float(manifest.duration),"kind":"phrase"}
	while phrase_cursor+1<phrases.size() and float(phrases[phrase_cursor+1].start)<=t:
		phrase_cursor+=1
	return phrases[phrase_cursor]
