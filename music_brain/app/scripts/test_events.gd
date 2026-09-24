extends SceneTree

func _initialize() -> void:
	var Pool=load("res://scripts/visual_events.gd")
	var pool=Pool.new()
	var values := PackedFloat32Array(); values.resize(256)
	var bursts := PackedFloat32Array(); bursts.resize(256)
	var phases := PackedFloat32Array(); phases.resize(256)
	var bands: Array=[]
	for i in range(16): bands.append(.12 if i<5 else (.28 if i<11 else .06))
	values[39]=.9; values[182]=.7; bursts[39]=.8
	# Event history bridges a skipped transport packet; repeated IDs cannot
	# retrigger. Every detected clock event produces a nonempty birth cluster.
	pool.ingest(values,bursts,phases,bands,[{"id":1,"age_ms":90},{"id":2,"age_ms":0}],.025)
	assert(pool.trigger_count==2 and pool.trigger_births>=2)
	assert(not pool.scene_descriptor.is_empty() and pool.scene_descriptor.has("topology"))
	var before: int=pool.trigger_count
	pool.ingest(values,bursts,phases,bands,[{"id":1},{"id":2}],.025)
	assert(pool.trigger_count==before)
	# Simultaneous births from all grammars, all with explicit neural sources.
	for grammar in range(8):
		var slot: int=pool.spawn(39,grammar,.8)
		assert(pool.source[slot]==39 and pool.kind[slot]==grammar)
		assert(pool.lifetime[slot]>=Pool.LIFE_MIN[grammar] and pool.lifetime[slot]<=Pool.LIFE_MAX[grammar])
	var storage_bytes: int=pool.bytes.size()
	for i in range(4000): pool.spawn(i%256,i%8,.5)
	assert(pool.bytes.size()==storage_bytes and pool.live_count<=Pool.CAPACITY)
	assert(pool.count_by_kind.count(0)==0)
	var born: int=pool.births_total
	pool.advance(4.1)
	assert(pool.live_count==0 and pool.deaths_total==born)
	pool.upload()
	# Saturated graph progress or a burst cannot prematurely end a scored phrase.
	pool.set_phrase({"index":0,"start":0.,"end":20.,"kind":"phrase"})
	pool.ingest(values,bursts,phases,bands,[],.025)
	var scene: int=pool.scene_serial
	pool.advance(25.)
	pool.ingest(values,bursts,phases,bands,[],.025)
	assert(pool.scene_serial==scene)
	pool.set_phrase({"index":1,"start":20.,"end":24.,"kind":"fill"})
	pool.ingest(values,bursts,phases,bands,[],.025)
	assert(pool.scene_serial==scene+1)
	# Source permutation changes parameters despite exactly the same mean.
	var first=Pool.new(); var second=Pool.new()
	first.activity[39]=.9; second.activity[182]=.9
	first.spawn(39,Pool.TYPE,.9); second.spawn(182,Pool.TYPE,.9)
	assert(first.bytes!=second.bytes)
	print("VISUAL_EVENTS_OK lifetimes / overlapping grammars / bounded reuse / transient delivery / neural identity")
	quit()
