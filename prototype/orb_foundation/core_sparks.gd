extends Node3D
## Core sparks (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 8:
## "GPUParticles3D, sub_emitter targeting Core's surface... Continuous
## trickle + burst on THINKING/EXECUTING... Sub-emitter relationship means
## this population's own base emission should be disabled by design, not
## left as a leftover default [DOC]").
##
## HONEST DEVIATION FROM THE LITERAL TECHNIQUE, time-boxed and documented,
## not silently substituted: the doc-specified two-node sub-emitter pair
## (a spawner GPUParticles3D with no draw_pass of its own, driving a child
## GPUParticles3D via GPUParticles3D.sub_emitter + ParticleProcessMaterial.
## sub_emitter_mode = SUB_EMITTER_AT_END, the real documented Godot 4
## mechanism) was built and tested four times -- confirmed-working
## materials from this same pass (micro_particles.gd's fixed-alpha
## approach, and a fully opaque no-transparency material that rendered
## correctly in a standalone, non-sub-emitted diagnostic) both rendered
## completely blank when driven purely through sub-emission, with
## `RENDER_TOTAL_PRIMITIVES_IN_FRAME` confirming real geometry was being
## submitted throughout. Transparency, blend mode, and local_coords were
## each ruled out as the cause by direct test. Root cause not found within
## this pass's time budget (5 populations to cover) -- flagged here as a
## real, unresolved technical gap, not declared solved.
##
## Substituted here: a single continuously-emitting GPUParticles3D at the
## core's surface, each particle itself a spark (not spawned via literal
## sub-emission chaining) -- same spatial intent (sparks originating from
## the core's surface) and same state-reactivity (trickle scales with
## activity) as the doc's design, without the broken mechanism. A future
## pass should revisit the literal sub_emitter API with more time budget
## before treating this substitution as final.

const CORE_SURFACE_RADIUS := 1.05
const SPARK_COUNT := 24


func _ready() -> void:
	add_child(_build_sparks())


func _build_sparks() -> GPUParticles3D:
	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = SPARK_COUNT
	sparks.lifetime = 0.7
	sparks.local_coords = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = CORE_SURFACE_RADIUS
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 3.5
	sparks.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	sparks.draw_pass_1 = quad

	sparks.material_override = _build_material()
	return sparks


## Fixed albedo alpha, blend_mode = MIX -- reusing micro_particles.gd's
## already-confirmed-working formula directly rather than re-deriving it.
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.97, 0.99)
	mat.emission_energy_multiplier = 2.5
	mat.albedo_color = Color(0.96, 0.9, 0.85, 0.8)
	return mat


func _process(_delta: float) -> void:
	var energy := get_node_or_null("/root/EnergyModel")
	if not energy:
		return
	var sparks := get_node_or_null("Sparks") as GPUParticles3D
	if not sparks:
		return
	var activity: float = energy.current_activity
	var intensity: float = energy.current_intensity
	# "Continuous trickle + burst on THINKING/EXECUTING" falls out of the
	# already-set activity values in STATE_PROFILES (THINKING=0.75,
	# EXECUTING=0.9) rather than needing a special-cased state check, same
	# pattern the wisp/shell passes established.
	sparks.amount_ratio = clampf(lerpf(0.15, 1.0, activity), 0.1, 1.0)
	sparks.speed_scale = lerpf(0.5, 1.8, activity)

	var mat := sparks.material_override as StandardMaterial3D
	if mat:
		# Gold reserved for symbol_reveal/pulse per section 15 -- sparks
		# default to near-white, only leaning gold during a pulse event.
		var pulse_amount: float = clampf(energy.current_pulse, 0.0, 1.0)
		mat.emission = Color(0.96, 0.97, 0.99).lerp(Color(0.85, 0.65, 0.18), pulse_amount * 0.6)
		mat.emission_energy_multiplier = lerpf(1.2, 3.0, intensity)
