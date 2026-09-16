extends MeshInstance3D
## Builds a geodesic icosphere procedurally (no imported mesh asset, no
## external DCC tool) and assigns core.gdshader to it.
##
## Subdivision level 4 (2562 vertices / 5120 triangles) was chosen
## experimentally during this prototype: level 3 (642 vertices) visibly
## faceted under the vertex-displacement amplitudes this shader uses, and
## level 5 (10242 vertices) made no perceptible visual difference over
## level 4 while costing noticeably more per-vertex shader work. This is a
## starting point for further tuning, not treated as final.

@export var subdivisions: int = 4
@export var radius: float = 1.0

var _vertices: PackedVector3Array = PackedVector3Array()
var _edge_cache: Dictionary = {}


func _ready() -> void:
	var indices := _build_icosphere(subdivisions)

	var normals := PackedVector3Array()
	normals.resize(_vertices.size())
	for i in range(_vertices.size()):
		normals[i] = _vertices[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://core.gdshader")
	shader_mat.set_shader_parameter("base_radius", radius)
	set_surface_override_material(0, shader_mat)

	var perf := get_node_or_null("/root/PerfMonitor")
	if perf:
		perf.report_core_stats(_vertices.size(), int(indices.size() / 3))


# Standard recursive icosahedron subdivision: start from the 12-vertex/
# 20-face icosahedron, repeatedly split each triangle into 4 by inserting
# cached (deduplicated) edge midpoints, normalizing every new vertex onto
# the sphere as it's created. Shared vertices only — no UV seams to manage
# because core.gdshader samples noise from object-space position, not UV.
func _build_icosphere(levels: int) -> PackedInt32Array:
	_vertices = PackedVector3Array()
	_edge_cache.clear()

	var phi := (1.0 + sqrt(5.0)) / 2.0
	var base_verts := [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1),
	]
	for v in base_verts:
		_vertices.append(v.normalized() * radius)

	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	for _level in range(levels):
		var new_faces: Array = []
		for f in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			var ab := _midpoint_index(a, b)
			var bc := _midpoint_index(b, c)
			var ca := _midpoint_index(c, a)
			new_faces.append([a, ab, ca])
			new_faces.append([b, bc, ab])
			new_faces.append([c, ca, bc])
			new_faces.append([ab, bc, ca])
		faces = new_faces

	var indices := PackedInt32Array()
	indices.resize(faces.size() * 3)
	for i in range(faces.size()):
		indices[i * 3] = faces[i][0]
		indices[i * 3 + 1] = faces[i][1]
		indices[i * 3 + 2] = faces[i][2]
	return indices


func _midpoint_index(a: int, b: int) -> int:
	var key := Vector2i(min(a, b), max(a, b))
	if _edge_cache.has(key):
		return _edge_cache[key]
	var mid: Vector3 = ((_vertices[a] + _vertices[b]) * 0.5).normalized() * radius
	_vertices.append(mid)
	var idx := _vertices.size() - 1
	_edge_cache[key] = idx
	return idx
