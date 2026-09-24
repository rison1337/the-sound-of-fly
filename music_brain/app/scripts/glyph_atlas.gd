extends Control
const WORDS = ["AFTERIMAGE","RE:FORM","SYNAPSE","OVER/LOAD","SIGNAL","PHASE","MATTER","FLUX","RECURSIVE","UNFOLD","TRANSDUCE","ECHO","SENSE","PLASTIC","PULSE","FEEDBACK","EXCITE","CHROMA","NO/INPUT","FRACTURE","RESONANCE","BODY//DATA","SPLIT","ON:OFF","REWIRE","MORPH","EXCESS","[SYSTEM]","HYPER","VOLT","(RE)ACT","CORTEX","01:101:01","///////","+++++++","[] [] []","< > < >","000.000","SYNC/ERR","0xA7FF","MALE/CNS","165122","1/0/1/0","|| || ||","! ! ! !",">>>>>>" ,"S/N:039","LIVE.EXE"]
var face := SystemFont.new()
var mono := SystemFont.new()

func _ready() -> void:
	face.font_names=PackedStringArray(["Bahnschrift","Arial"])
	face.font_weight=900
	mono.font_names=PackedStringArray(["Consolas"])
	queue_redraw()

func _draw() -> void:
	for i in range(48):
		var font: Font=face if i<32 else mono
		var fs := 106
		var width := font.get_string_size(WORDS[i],HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		if width>748.: fs=int(float(fs)*748./width)
		var origin := Vector2((i%4)*768+8,(i/4)*128+104)
		draw_string(font,origin,WORDS[i],HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color.WHITE)
