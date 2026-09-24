extends RefCounted
## Reusable parametric domains. Profiles and relationships come from the brain;
## these are mesh domains, not finished scenes. Allocated once at startup.
static func surface(columns: int=64, rows: int=24) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in range(rows+1):
		for x in range(columns+1):
			var p := Vector2(float(x)/columns,float(y)/rows)
			vertices.append(Vector3(p.x*2.-1.,p.y*2.-1.,0.))
			normals.append(Vector3(0,0,1)); uv.append(p)
	for y in range(rows):
		for x in range(columns):
			var a := y*(columns+1)+x
			indices.append_array(PackedInt32Array([a,a+columns+1,a+1,a+1,a+columns+1,a+columns+2]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func scaffold() -> ArrayMesh:
	var vertices := PackedVector3Array(); var uv := PackedVector2Array()
	# Fine lines remain attached to the same parametric surface as the panels.
	for row in [0,8]:
		for x in range(48):
			for edge in range(2):
				var p := Vector2(float(x+edge)/48.,float(row)/8.)
				vertices.append(Vector3(p.x*2.-1.,p.y*2.-1.,0.)); uv.append(p)
	for column in [0,48]:
		for y in range(8):
			for edge in range(2):
				var p := Vector2(float(column)/48.,float(y+edge)/8.)
				vertices.append(Vector3(p.x*2.-1.,p.y*2.-1.,0.)); uv.append(p)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uv
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	return mesh

static func panel(wrapped: bool=false) -> ArrayMesh:
	# Closed thin shells. Openings and the silhouette are geometry, not discard.
	var columns := 96 if wrapped else 64
	var rows := 16 if wrapped else 32
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	var uv := PackedVector2Array(); var faces := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in range(2):
		var offset := vertices.size()
		for y in range(rows+1):
			for x in range(columns+1):
				var p := Vector2(float(x)/columns,float(y)/rows)
				vertices.append(Vector3(p.x*2.-1.,p.y*2.-1.,0.))
				normals.append(Vector3(0,0,1)); uv.append(p)
				faces.append(Vector2(1. if face==0 else -1.,float(face)*2.))
		for y in range(rows):
			for x in range(columns):
				var a := offset+y*(columns+1)+x
				var triangle := PackedInt32Array([a,a+columns+1,a+1,a+1,a+columns+1,a+columns+2])
				if face==1: triangle.reverse()
				indices.append_array(triangle)
	for edge in range(4):
		if wrapped and edge<2: continue
		var count := rows if edge<2 else columns
		var offset := vertices.size()
		for i in range(count+1):
			var t := float(i)/count
			var p := Vector2(float(edge),t) if edge<2 else Vector2(t,float(edge-2))
			var normal := Vector3(-1 if edge==0 else 1,0,0) if edge<2 else Vector3(0,-1 if edge==2 else 1,0)
			for side in range(2):
				vertices.append(Vector3(p.x*2.-1.,p.y*2.-1.,0.))
				normals.append(normal); uv.append(p)
				faces.append(Vector2(1. if side==0 else -1.,1.))
		for i in range(count):
			var a := offset+i*2
			indices.append_array(PackedInt32Array([a,a+1,a+2,a+2,a+1,a+3]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_TEX_UV2]=faces
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func create() -> Array[Mesh]:
	var box := BoxMesh.new(); box.size=Vector3.ONE
	# Rings use one toroidal skin, not the front/back/rim shell of a panel.
	# This density matches the old panel budget while keeping the curve smooth.
	return [panel(),surface(96,32),box,scaffold(),surface(128,64)]
