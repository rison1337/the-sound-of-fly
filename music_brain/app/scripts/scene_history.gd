extends RefCounted
## Bounded four-second neural trajectory. These bands are FIRING RATES of
## sensory neurons, never the raw FFT. Coactivation and centroid displacement
## are population proxies, not a claim of synaptic causal propagation.
const NAMES := ["UNFOLD / EDITORIAL","FOLDED RELIEF","ARCHITECTURE","ORBITAL SCAFFOLD","PARTITION / SPACE","APERTURE","MACRO / RIBBONS","WORLD WITHIN","PANEL TUNNEL","CUTOUT COLLAGE","NEURAL VOLUME","NESTED SCREENS"]
const SAMPLES := 160
var bands := PackedFloat32Array()
var loads := PackedFloat32Array()
var rises := PackedFloat32Array()
var centroids := PackedVector3Array()
var previous := PackedFloat32Array()
var baseline := PackedFloat32Array()
var variation := PackedFloat32Array()
var drives := PackedFloat32Array()
var timestamps := PackedFloat32Array()
var intervals := PackedFloat32Array()
var interval_count := 0
var interval_cursor := 0
var cursor := 0
var count := 0
var sample_elapsed := 0.
var elapsed := 0.
var last_onset := -1.
var last_id := -1
var short_memory := 0.
var medium_memory := 0.
var track_memory := 0.
var latest_rise := 0.
var latest_load := 0.
var latest_synchrony := 0.
var novelty: Array[Dictionary] = []
var shot_serial := 0

func _init() -> void:
	bands.resize(SAMPLES*16); loads.resize(SAMPLES); rises.resize(SAMPLES)
	centroids.resize(SAMPLES); previous.resize(256); intervals.resize(48)
	baseline.resize(256); variation.resize(256); variation.fill(.025); drives.resize(256); timestamps.resize(SAMPLES)

func observe(values: PackedFloat32Array, bursts: PackedFloat32Array, neural_bands: Array, timing: Array, dt: float) -> void:
	elapsed+=dt; sample_elapsed+=dt
	var mass := 0.; var rise := 0.; var centroid := Vector3.ZERO
	for i in range(256):
		mass+=values[i]
		rise+=maxf(0.,values[i]-previous[i])+bursts[i]*.05
		# Normalize visual excursions to this population's own recent range.
		# This changes visual gain only; model state/weights are untouched.
		var residual := values[i]-baseline[i]
		baseline[i]=lerpf(baseline[i],values[i],1.-exp(-dt/1.5))
		variation[i]=lerpf(variation[i],absf(residual),1.-exp(-dt/2.))
		var transient := maxf(0.,residual)/maxf(.018,variation[i]*2.8)
		var rising_rate := maxf(0.,values[i]-previous[i])/maxf(.012,variation[i]*.6)
		var target := clampf(transient*.9+rising_rate*.7+bursts[i]*2.4,0.,1.)
		drives[i]=maxf(target,drives[i]*exp(-dt/.18))
		centroid+=Vector3(float(i%8)/7.,float((i/8)%8)/7.,float(i/64)/3.)*values[i]
		previous[i]=values[i]
	latest_load=mass/256.
	latest_rise=clampf(rise/256.*12.,0.,1.)
	var active_mass := 0.; var coactive_mass := 0.; var active_variance := 0.
	for i in range(256):
		if values[i]>.18: active_mass+=1.
		if values[i]>.18 and (drives[i]>.32 or bursts[i]>.08): coactive_mass+=1.
		active_variance+=pow(values[i]-latest_load,2.)/256.
	# Synchrony is a temporal co-activity measure, not a reward for a flat
	# tonic population. A quiet/uniform frame therefore stays near zero.
	var active_fraction := active_mass/256.
	var coactivity_fraction := coactive_mass/maxf(1.,active_mass)
	latest_synchrony=clampf(coactivity_fraction*active_fraction*.78+clampf(latest_rise*1.8,0.,1.)*.22,0.,1.)
	centroid/=maxf(.001,mass)
	short_memory=lerpf(short_memory,latest_load,1.-exp(-dt/2.))
	medium_memory=lerpf(medium_memory,latest_load,1.-exp(-dt/20.))
	track_memory=lerpf(track_memory,latest_load,dt/maxf(dt,elapsed))
	if sample_elapsed>=.025:
		sample_elapsed=fmod(sample_elapsed,.025)
		for b in range(16): bands[cursor*16+b]=float(neural_bands[b]) if neural_bands.size()==16 else 0.
		loads[cursor]=latest_load; rises[cursor]=latest_rise; centroids[cursor]=centroid
		timestamps[cursor]=elapsed
		cursor=(cursor+1)%SAMPLES; count=mini(count+1,SAMPLES)
		while count>1 and elapsed-timestamps[posmod(cursor-count,SAMPLES)]>4.: count-=1
	observe_timing(timing)

func observe_timing(timing: Array) -> void:
	for event in timing:
		var id := int(event.get("id",-1))
		if id<=last_id: continue
		last_id=id
		var t := elapsed-float(event.get("age_ms",0.))/1000.
		# Coincident low/mid/high detectors form one interval, not a fake 1ms beat.
		if last_onset>=0. and t-last_onset>.045:
			intervals[interval_cursor]=clampf(t-last_onset,.045,3.)
			interval_cursor=(interval_cursor+1)%48
			interval_count=mini(interval_count+1,48)
		if last_onset<0. or t-last_onset>.045: last_onset=t

func describe(values: PackedFloat32Array, bursts: PackedFloat32Array) -> Dictionary:
	var mean := PackedFloat32Array(); mean.resize(16)
	var slope := PackedFloat32Array(); slope.resize(16)
	var variability := 0.; var coactivity := 0.; var total := 0.
	var active := 0.; var mean_burst := 0.
	for i in range(256):
		total+=values[i]; active+=1. if values[i]>.18 else 0.
		mean_burst+=bursts[i]/256.
	for t in range(count):
		var row := posmod(cursor-count+t,SAMPLES)
		coactivity+=rises[row]/maxi(1,count)
		for b in range(16):
			var value := bands[row*16+b]
			mean[b]+=value/maxi(1,count)
			slope[b]+=value*(1. if t>=count/2 else -1.)/maxi(1,count/2)
	for t in range(count):
		var row := posmod(cursor-count+t,SAMPLES)
		for b in range(16): variability+=absf(bands[row*16+b]-mean[b])/maxi(1,count*16)
	var low := 0.; var mid := 0.; var high := 0.; var rising := 0.
	for b in range(16):
		if b<5: low+=mean[b]/5.
		elif b<11: mid+=mean[b]/6.
		else: high+=mean[b]/5.
		rising+=slope[b]/16.
	var interval_mean := 0.; var interval_variance := 0.
	for i in range(interval_count): interval_mean+=intervals[i]/maxi(1,interval_count)
	for i in range(interval_count): interval_variance+=pow(intervals[i]-interval_mean,2.)/maxi(1,interval_count)
	var rhythm_density := clampf(1./maxf(.12,interval_mean)/7.,0.,1.) if interval_count>0 else 0.
	var irregularity := clampf(sqrt(interval_variance)/maxf(.1,interval_mean),0.,1.)
	var sustained := clampf(1.-variability*6.-coactivity*.7,0.,1.)
	var spread := active/256.
	var propagation := Vector3.ZERO
	if count>2: propagation=(centroids[posmod(cursor-1,SAMPLES)]-centroids[posmod(cursor-count,SAMPLES)])*8.
	var direction := Vector2(propagation.x,propagation.y)
	if direction.length()<.015: direction=Vector2(mid-low,high-mid)
	if direction.length()<.015: direction=Vector2.RIGHT
	direction=direction.normalized()
	# Structural scores: band response, trends, spatial spread and memory each
	# have their own effect. No aggregate signature gets hashed into a preset.
	var scores: Array[float]=[
		.5+mid+variability*2., .25+mid+sustained*.55,
		.2+low+maxf(0.,rising)*4.+coactivity*.5,
		.2+high+spread*.5, .3+mid+variability*3.,
		.25+mean_burst+high*.5+coactivity,
		.2+low+sustained*.6, .15+medium_memory+track_memory*.3,
		.25+low+high*.4+maxf(0.,rising)*2., .3+mid+variability*2.5,
		.2+high+latest_synchrony*.8, .25+medium_memory+high*.5]
	# Novelty is measured on structural axes. Recently used spaces pay a
	# recency cost; a close descriptor causes a camera/primitive/depth change.
	for j in range(novelty.size()):
		var old := novelty[j]
		var recency := float(j+1)/maxi(1,novelty.size())
		# A motif may return in another framing. Avoid the old forced tour of
		# every preset: old visits exert only a small, decaying structural cost.
		scores[int(old.topology)]-=pow(recency,4.)*1.5
		# Panel, partition and nested views share a broad silhouette. Avoid
		# selecting them back-to-back as if their different names were novelty.
		if int(old.topology) in [0,4,7] and j>=novelty.size()-2:
			for related in [0,4,7]:
				if related!=int(old.topology): scores[related]-=.8*recency
	var topology := 0
	for i in range(1,scores.size()):
		if scores[i]>scores[topology]: topology=i
	if not novelty.is_empty() and int(novelty[-1].topology)==topology:
		scores[topology]-=.65
		for i in range(scores.size()):
			if scores[i]>scores[topology]: topology=i
	var camera := 0 if topology==0 else (3 if topology in [2,8] else (2 if topology in [3,5,7,10,11] else 1))
	var primitive := 0 if mid>low*1.2 else (1 if low>high*1.2 else 2)
	if variability>.075: primitive=3
	if sustained>.88 and mid>.12: primitive=4
	var palette := 0 if mid>=high*.8 else 1
	if rising>.08 and mean_burst>.1: palette=2
	if variability>.16 and low>mid: palette=3
	var depth := clampf(.25+low*.65+spread*.3,.2,1.)
	for old in novelty:
		var distance := (0. if int(old.topology)==topology else .5)+(0. if int(old.camera)==camera else .18)+(0. if int(old.primitive)==primitive else .15)+absf(float(old.depth)-depth)*.17
		if distance<.20:
			camera=(camera+1)%4; primitive=(primitive+2)%5
			depth=clampf(1.2-depth,.2,1.)
	# At most two typography-heavy shots in each rolling 16, and at most
	# seven shots with any words. Text is never a generic filler family.
	var with_text := 0; var heavy := 0
	for old in novelty:
		with_text+=1 if int(old.text)>0 else 0
		heavy+=1 if int(old.text)==2 else 0
	var text_class := 0
	var owners: Array[int]=[]
	# Distributed neural ownership: one source per spatial sector, then
	# additional globally salient sources. Saturated top bins cannot own all
	# the geometry. Ownership is stable until the next cut.
	for k in range(24):
		var best := -1; var best_score := -1.
		for i in range(256):
			if owners.has(i): continue
			if k<16 and i%16!=k: continue
			var score := values[i]*.25+bursts[i]*.6+drives[i]*.7+variation[i]*2.
			if score>best_score: best_score=score; best=i
		owners.append(best)
	var peak_band := 0; var bands_mass := 0.; var spectral_centroid := 0.
	for b in range(16):
		if mean[b]>mean[peak_band]: peak_band=b
		bands_mass+=mean[b]; spectral_centroid+=mean[b]*float(b)/15.
	spectral_centroid/=maxf(.01,bands_mass)
	var floor_band := mean[0]
	for b in range(16): floor_band=minf(floor_band,mean[b])
	var profile_range := maxf(.08,mean[peak_band]-floor_band)
	var profile := PackedFloat32Array(); profile.resize(16)
	var trend_profile := PackedFloat32Array(); trend_profile.resize(16)
	for b in range(16):
		profile[b]=clampf(.12+.76*(mean[b]-floor_band)/profile_range+slope[b]*.25,.05,.95)
		trend_profile[b]=clampf(slope[b]*3.,-.6,.6)
	# Four distinct epochs of the real neural trajectory shape the surface.
	# This retains temporal morphology rather than hashing it into a seed.
	var trajectory: Array=[]; trajectory.resize(64); trajectory.fill(0.)
	var epoch_counts := PackedInt32Array(); epoch_counts.resize(4)
	for t in range(count):
		var epoch := mini(3,int(float(t)*4./maxi(1,count)))
		var row := posmod(cursor-count+t,SAMPLES)
		epoch_counts[epoch]+=1
		for b in range(16): trajectory[epoch*16+b]+=bands[row*16+b]
	for epoch in range(4):
		for b in range(16):
			trajectory[epoch*16+b]=clampf(.12+.76*(float(trajectory[epoch*16+b])/maxi(1,epoch_counts[epoch])-floor_band)/profile_range,.05,.95)
	var color_scores: Array[float]=[profile[5]*.6+profile[9]*.4,profile[12]*.6+profile[2]*.4,profile[1]*.45+variability*2.,profile[7]*.4+mean_burst*2.]
	for old in novelty.slice(maxi(0,novelty.size()-2)):
		color_scores[int(old.get("palette",0))]-=.45
	palette=0
	for i in range(1,4):
		if color_scores[i]>color_scores[palette]: palette=i
	var descriptor := {
		"silhouette":clampf(variability*4.+(mid-high)*.8+profile[6]*.6,0.,1.),
		"section_count":3+int(profile[3]*5.),
		"camera_sweep":direction.x*(.5+low)*(.7+variability*2.),
		"id":shot_serial, "fingerprint":low*.31+mid*.47+high*.73+irregularity*.29+rhythm_density*.41, "topology":topology, "name":NAMES[topology],
		"camera":camera, "fov":lerpf(46.,72.,low), "depth":depth,
		"objects":int(clampf(6.+spread*18.+mid*10.,6.,34.)),
		"primitive":primitive, "symmetry":clampf(sustained-coactivity*.3,0.,1.),
		"asymmetry":clampf(variability*5.+coactivity*.4,0.,1.),
		"text":text_class, "text_angle":0. if sustained>.6 else PI*.5,
		"blocks":clampf(.12+mid*.6,.12,.8), "traces":clampf(.05+high*.7,.05,.7),
		"trace_topology":0 if spread<.5 else 1,
		"material":0 if topology in [0,4,7] else 1,
		"palette":palette, "contrast":clampf(.75+variability,0.,1.),
		# Light paper is the normal editorial canvas. Dark worlds are rare,
		# earned by a high-synchrony/deep-space section instead of being tied to
		# one topology; this prevents every neural volume from becoming a black
		# screen with isolated rings.
		"background":0 if ((topology in [2,8,11] and high>mid*.82) or (latest_synchrony>.70 and low<mid*.72)) else 1,
		"axis_x":direction.x, "axis_y":direction.y,
		"deformation":0 if sustained>.8 else (1 if mean_burst<.15 else 2),
		"deform_amount":clampf(.06+mid*.25+variability,.06,.42),
		"transition":2 if coactivity>.25 else (1 if rising>.015 else 0),
		"duration":clampf(2.7+sustained*1.2-coactivity*.8-variability*1.5,2.2,4.2),
		"view_duration":clampf(.48-coactivity*.2-variability*.5,.18,.58),
		"fold":clampf(.3+mid*.65+variability*2.,.3,1.4),
		"trajectory":trajectory,
		"life_scale":clampf(.5+sustained*.5,.5,1.),
		"branches":clampi(3+int(spectral_centroid*3.+spread*2.),3,6),
		"columns":clampi(4+int(mid*5.+spectral_centroid*4.),4,10),
		"spacing":.7+low*.8+sustained*.6,
		"twist":(mid-high)*2.5+direction.x*.4,
		"aperture":2.2+low*2.1,
		"offset_x":(mid-high)*2., "offset_y":(high-low)*1.1,
		"profile":Array(profile),"profile_slope":Array(trend_profile),
		"speed":.55+low*1.35+maxf(0.,rising)*4.,
		"birth_rate":.3+rhythm_density*.6+coactivity*.35,
		"irregularity":irregularity, "rhythm_density":rhythm_density,
		"low":low,"mid":mid,"high":high,"trend":rising,"burst":mean_burst,
		"synchrony":latest_synchrony,
		"camera_drive":clampf(low*.65+maxf(0.,rising)*2.+latest_synchrony*.25,0.,1.),
		"depth_drive":clampf(low*.6+spread*.35+latest_synchrony*.2,0.,1.),
		"material_drive":clampf(mid*.65+high*.35+variability*2.,0.,1.),
		"deform_drive":clampf(maxf(0.,rising)*3.+mean_burst*2.+variability*2.,0.,1.),
		"short_memory":short_memory,"medium_memory":medium_memory,"track_memory":track_memory,
		"composition_topology":topology, "camera_mode":camera, "depth_distribution":depth,
		"primitive_family":primitive, "symmetry_axis":direction.angle(),
		"material_family":0 if sustained>.65 else (1 if high>mid else 2),
		"layout_density":clampf(.24+spread*.45+rhythm_density*.3,.18,.95),
		"neural_roles":{"camera":owners[0],"depth":owners[1],"material":owners[2],"deformation":owners[3],"cut":owners[4],"micro":owners[5]},
		"band_shape":Array(mean), "band_trend":Array(slope), "owners":owners,
		"graphic_mode":peak_band%6,
		"layout_mode":clampi(int(irregularity*3.),0,2),
		"flat_mode":(0 if sustained>.35 else 1) if topology in [0,4,7,9] else 2,
		"camera_crop":.8+profile[4]*.28,
	}
	# Compare the actual design axes, not a scalar seed. A recent motif can
	# recur only with another framing, material role or dimensional treatment.
	for previous_shot in novelty.slice(maxi(0,novelty.size()-4)):
		var likeness := 0.
		for b in range(16): likeness+=absf(profile[b]-float(previous_shot.get("profile",profile)[b]))/16.
		if likeness<.12 and int(previous_shot.get("graphic_mode",-1))==int(descriptor.graphic_mode):
			descriptor.graphic_mode=(int(descriptor.graphic_mode)+2)%6
			descriptor.layout_mode=(int(descriptor.layout_mode)+1)%3
			if topology in [0,4,7,9]: descriptor.flat_mode=1-int(previous_shot.get("flat_mode",0)) if int(previous_shot.get("flat_mode",0))<2 else 0
		if int(previous_shot.topology)==topology and likeness<.16:
			descriptor.camera=(int(descriptor.camera)+1)%4
			descriptor.camera_crop=1.25 if float(previous_shot.get("camera_crop",1.))<1.1 else .75
			descriptor.palette=(int(descriptor.palette)+1)%4
	novelty.append({"topology":topology,"camera":descriptor.camera,"primitive":primitive,"depth":depth,"text":text_class,"graphic_mode":descriptor.graphic_mode,"layout_mode":descriptor.layout_mode,"profile":Array(profile),"flat_mode":descriptor.flat_mode,"camera_crop":descriptor.camera_crop,"palette":descriptor.palette})
	if novelty.size()>16: novelty.pop_front()
	shot_serial+=1
	return descriptor
