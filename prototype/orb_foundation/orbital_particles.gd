extends Node3D
## Orbital particles (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 8:
## "GPUParticles3D, custom process shader constraining motion to orbital
## paths... Continuous, density scales with activity... Highest-effort
## population to get looking non-random; budget real prototyping time
## here"). Section 4 names the mechanism: "GPUParticles3D with a custom
## ParticleProcessMaterial... driving orbit motion" -- Godot's built-in
## `orbit_velocity_min/max` on ParticleProcessMaterial is exactly this (a
## real, documented property, not hand-written shader code), already used
## successfully for drift in wisp_system_a.gd during the wisp decision
## pass.
##
## Anchored to the already-built StructuralLattice rings rather than an
## independently-parameterized radius/orientation -- this project has hit
## the "positioned independently of real structure" mistake before
## (archive/orb_v1/docs/ORB_CONCEPT_GAP_ANALYSIS.md's particle-role gaps
## were never anchored to the rings/plates the way this brief wants). Radii
## are read directly from structural_lattice.gd's own RING_A_RADIUS/
## RING_B_RADIUS constants (not touching that protected file -- GDScript
## constants are readable externally via preload().CONST_NAME); the
## rotation values are duplicated as literals with this comment citing
## structural_lattice.gd as their source of truth, since that file's
## rotations aren't exposed as named constants and editing it is out of
## scope for this pass.

const LATTICE_SCRIPT := preload("res://structural_lattice.gd")

const RING_A_ROTATION_DEG := Vector3(16.0, 0.0, 0.0) # matches structural_lattice.gd RingA exactly
const RING_B_ROTATION_DEG := Vector3(0.0, 0.0, -20.0) # matches structural_lattice.gd RingB exactly

const EMISSION_THICKNESS := 0.12
const PARTICLE_COUNT := 18


func _ready() -> void:
	add_child(_build_orbit("OrbitalA", LATTICE_SCRIPT.RING_A_RADIUS, RING_A_ROTATION_DEG, 0.9))
	add_child(_build_orbit("OrbitalB", LATTICE_SCRIPT.RING_B_RADIUS, RING_B_ROTATION_DEG, -0.7))


func _build_orbit(node_name: String, radius: float, rotation_deg: Vector3, orbit_sign: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = PARTICLE_COUNT
	particles.lifetime = 6.0
	particles.local_coords = true
	particles.rotation_degrees = rotation_deg

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = radius
	mat.emission_ring_inner_radius = radius - EMISSION_THICKNESS
	mat.emission_ring_height = 0.02
	mat.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
	mat.direction = Vector3.ZERO
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	# The actual "follow the ring's path" motion -- orbiting around this
	# node's local Z axis, which emission_ring_axis above aligns with the
	# ring's own plane normal (same axis convention wisp_system_a.gd's
	# orbit_velocity already established as working).
	mat.orbit_velocity_min = 0.05 * orbit_sign
	mat.orbit_velocity_max = 0.09 * orbit_sign
	mat.scale_min = 1.4
	mat.scale_max = 2.2
	particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	particles.draw_pass_1 = quad

	particles.material_override = _build_material()
	return particles


## Fixed albedo alpha, blend_mode = MIX -- reusing the confirmed-working
## formula from micro_particles.gd/core_sparks.gd directly.
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.97, 0.99)
	mat.emission_energy_multiplier = 1.8
	mat.albedo_color = Color(0.9, 0.93, 0.98, 0.65)
	return mat


func _process(_delta: float) -> void:
	var energy := get_node_or_null("/root/EnergyModel")
	if not energy:
		return
	var activity: float = energy.current_activity
	for node_name in ["OrbitalA", "OrbitalB"]:
		var p := get_node_or_null(node_name) as GPUParticles3D
		if not p:
			continue
		# "density scales with activity" per section 8 -- direct read.
		p.amount_ratio = clampf(lerpf(0.2, 1.0, activity), 0.15, 1.0)
		p.speed_scale = lerpf(0.4, 1.5, activity)
