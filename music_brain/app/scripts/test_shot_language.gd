extends SceneTree
const Language=preload("res://scripts/shot_language.gd")
const Voices=preload("res://scripts/neural_voices.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)

func _initialize() -> void:
	var d := {"flat_mode":2,"profile":[.5],"mid":.3,"depth":.5}
	var edit=Language.new(); var v=Voices.new()
	edit.establish(d)
	var serial: int=edit.serial
	edit.advance(10.)
	check(edit.serial==serial,"Time alone changed the presentation")
	check(not edit.articulate(0,v,d,.2),"Silent cells caused an editorial cut")
	v.level.fill(.2); v.attack.fill(.2); v.contour.fill(.4)
	v.accent[0]=.8; v.attack[0]=1.
	check(edit.articulate(0,v,d,.2),"Responsive onset did not create an edit")
	check(edit.presentation==1,"Impact-led population did not select its graphic presentation")
	check(edit.mask_from==0 and is_zero_approx(edit.mask_progress()),"Mask lost its starting view")
	serial=edit.serial
	edit.advance(.02)
	check(not edit.articulate(0,v,d,.2) and edit.serial==serial,"Repeated onsets ignored minimum hold")
	var progress_before: float=edit.mask_progress()
	edit.advance(.10)
	check(edit.mask_progress()>progress_before and edit.mask_progress()<1.,"Mask did not advance continuously")
	edit.advance(.16)
	check(is_equal_approx(edit.mask_progress(),1.),"Mask did not settle after its duration")
	check(edit.hold>edit.mask_duration,"An edit can interrupt an unfinished mask")
	# Equal onset timing, different downstream structure -> different framing.
	var melodic=Language.new(); melodic.establish(d); melodic.advance(10.)
	v.level.fill(.05); v.attack.fill(.05); v.contour.fill(.1)
	v.level[4]=1.; v.level[3]=.9; v.accent[0]=.8
	check(melodic.articulate(0,v,d,.2),"Melodic readout did not create an edit")
	check(melodic.presentation!=edit.presentation,"Onset ID alone selected the framing")
	check(v.owners[4]==164,"Editorial selection changed neural ownership")
	print("SHOT_LANGUAGE failures=",failures)
	quit(0 if failures==0 else 1)
