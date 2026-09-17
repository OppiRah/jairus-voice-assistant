extends Node3D
## Burst/directional particles (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 8: "GPUParticles3D, one_shot = true, triggered from EnergyModel
## on state-transition events (e.g. entering SUCCESS, entering EXECUTING)
## [DOC]... Event-driven only... This is the direct implementation of the
## brief's 'should be event-driven, not continuously running at maximum'
## instruction").
##
## Explicitly NOT continuous -- one_shot = true, emitting stays false until
## a real state-transition event fires. Triggered by connecting to
## EnergyModel's existing, already-public `state_changed` signal (emitted
## once per transition in energy_model.gd's set_state(), unmodified here --
## this is a new external listener, not a change to that protected file)
## and checking the incoming state name, which is exactly "entering X"
## semantics -- no separate transition-tracking state needed.

const BURST_RADIUS := 1.2
const PARTICLE_COUNT := 26
const TRIGGER_STATES := ["SUCCESS", "EXECUTING"]


func _ready() -> void:
	var burst := _build_burst()
	add_child(burst)

	var energy := get_node_or_null("/root/EnergyModel")
	if energy:
		energy.state_changed.connect(_on_state_changed)


func _build_burst() -> GPUParticles3D:
	var burst := GPUParticles3D.new()
	burst.name = "Burst"
	burst.amount = PARTICLE_COUNT
	burst.lifetime = 0.9
	burst.one_shot = true
	burst.emitting = false
	burst.local_coords = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = BURST_RADIUS
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.1
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.4
	mat.damping_max = 0.7
	mat.scale_min = 1.6
	mat.scale_max = 2.6
	burst.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	burst.draw_pass_1 = quad

	burst.material_override = _build_material()
	return burst


## Fixed albedo alpha, blend_mode = MIX -- reusing the confirmed-working
## formula from micro_particles.gd/core_sparks.gd/orbital_particles.gd.
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.97, 0.99)
	mat.emission_energy_multiplier = 2.5
	mat.albedo_color = Color(0.95, 0.95, 0.98, 0.85)
	return mat


func _on_state_changed(state_name: String) -> void:
	if state_name not in TRIGGER_STATES:
		return
	var burst := get_node_or_null("Burst") as GPUParticles3D
	if not burst:
		return

	# SUCCESS's gold pulse vs. EXECUTING's near-white surge -- section 15's
	# gold-reserved-for-symbol_reveal/pulse rule, applied per trigger rather
	# than left at one fixed burst color for both events.
	var mat := burst.material_override as StandardMaterial3D
	if mat:
		mat.emission = Color(0.85, 0.65, 0.18) if state_name == "SUCCESS" else Color(0.96, 0.97, 0.99)

	burst.restart()
	burst.emitting = true
