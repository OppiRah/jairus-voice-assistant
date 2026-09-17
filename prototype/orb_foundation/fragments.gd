extends Node3D
## Fragments (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 8:
## "MultiMeshInstance3D if count > ~15-20, else a small pool of plain
## nodes | Continuous, slow, driven by coherence (more coherent = more
## 'in formation') | Do not default to GPUParticles3D here -- fragments
## need individual, recognizable identity").
##
## FRAGMENT_COUNT (8) is well under the ~15-20 MultiMesh threshold, so this
## uses plain MeshInstance3D nodes per the doc's own stated default for
## that range, not MultiMeshInstance3D. Each fragment is a small,
## hand-built angular shard (SurfaceTool, no external asset) -- "computational
## fragments, not debris" per the design brief's language elsewhere in this
## project, so a faceted crystalline shard rather than an irregular rock.
##
## coherence drives a blend between a scattered/jittered placement (low
## coherence) and a neat, evenly-spaced ring formation (high coherence),
## per section 8's "more coherent = more in formation" instruction --
## each fragment's own seed/phase keeps them individually distinct even
## when "in formation," not identical clones moving in lockstep.

const FRAGMENT_COUNT := 8
const ORBIT_RADIUS := 1.5
const SHARD_SIZE := 0.09


func _ready() -> void:
	for i in range(FRAGMENT_COUNT):
		add_child(_build_fragment(i))


func _build_fragment(index: int) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Fragment%d" % index
	mesh_instance.mesh = _build_shard_mesh()
	mesh_instance.set_meta("seed", float(index) * 1.7 + 0.3)
	mesh_instance.set_meta("formation_angle", TAU * float(index) / float(FRAGMENT_COUNT))
	mesh_instance.set_meta("scatter_offset", Vector3(
		sin(float(index) * 3.1), cos(float(index) * 2.3), sin(float(index) * 4.7)
	) * 0.5)
	mesh_instance.set_meta("spin_speed", 0.3 + 0.5 * fmod(float(index) * 0.63, 1.0))

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.92, 0.97)
	mat.emission_energy_multiplier = 1.3
	mat.albedo_color = Color(0.8, 0.82, 0.88)
	mesh_instance.set_surface_override_material(0, mat)
	return mesh_instance


## Small faceted shard -- a flattened, irregular tetrahedron, built via
## SurfaceTool (no external asset), reading as a "computational fragment"
## rather than smooth debris.
func _build_shard_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, SHARD_SIZE, 0.0)
	var base_a := Vector3(-SHARD_SIZE * 0.5, -SHARD_SIZE * 0.3, SHARD_SIZE * 0.35)
	var base_b := Vector3(SHARD_SIZE * 0.6, -SHARD_SIZE * 0.4, -SHARD_SIZE * 0.2)
	var base_c := Vector3(-SHARD_SIZE * 0.2, -SHARD_SIZE * 0.35, -SHARD_SIZE * 0.5)
	var faces := [
		[tip, base_a, base_b], [tip, base_b, base_c], [tip, base_c, base_a],
		[base_a, base_c, base_b],
	]
	for face in faces:
		var normal: Vector3 = (face[1] - face[0]).cross(face[2] - face[0]).normalized()
		st.set_normal(normal)
		for v in face:
			st.add_vertex(v)
	return st.commit()


func _process(delta: float) -> void:
	var energy := get_node_or_null("/root/EnergyModel")
	if not energy:
		return
	var coherence: float = clampf(energy.current_coherence, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0

	for child in get_children():
		var frag := child as MeshInstance3D
		if not frag:
			continue
		var seed_val: float = frag.get_meta("seed")
		var formation_angle: float = frag.get_meta("formation_angle")
		var scatter_offset: Vector3 = frag.get_meta("scatter_offset")
		var spin_speed: float = frag.get_meta("spin_speed")

		# Slow continuous drift around the object, independent of coherence.
		var drift_angle := formation_angle + t * 0.08 * spin_speed

		# High coherence: clean, evenly-spaced ring at ORBIT_RADIUS.
		var formation_pos := Vector3(cos(drift_angle), sin(seed_val) * 0.15, sin(drift_angle)) * ORBIT_RADIUS

		# Low coherence: same general orbit but jittered off-ring in position
		# and radius, per-fragment (scatter_offset), so "loose" reads as
		# individually scattered, not just a wobblier version of the same ring.
		var scatter_pos := formation_pos + scatter_offset * (1.0 - coherence) \
			+ Vector3(sin(t * 0.4 + seed_val), cos(t * 0.33 + seed_val), sin(t * 0.51 + seed_val)) * 0.15

		frag.position = formation_pos.lerp(scatter_pos, 1.0 - coherence)
		frag.rotation_degrees += Vector3(1.0, 1.4, 0.7) * spin_speed * delta * 40.0

		var mat := frag.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = lerpf(0.8, 1.8, energy.current_intensity)
