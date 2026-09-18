extends Node3D
## Core sparks (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 8:
## "GPUParticles3D, sub_emitter targeting Core's surface... Continuous
## trickle + burst on THINKING/EXECUTING... Sub-emitter relationship means
## this population's own base emission should be disabled by design, not
## left as a leftover default [DOC]").
##
## RESOLVED (previously an honest, flagged substitution -- root-caused and
## fixed in a dedicated follow-up pass): the literal two-node sub-emitter
## pair (spawner with no draw_pass, driving a visible child via
## GPUParticles3D.sub_emitter + ParticleProcessMaterial.sub_emitter_mode =
## SUB_EMITTER_AT_END) previously rendered blank across four isolated
## tests. A focused root-cause investigation checked the strongest
## hypothesis first -- this project's Forward Mobile renderer lacking
## compute-shader support, the confirmed cause of the wisp pass's
## trail_enabled failure -- and found it does NOT apply here: an isolated
## minimal scene (no core/lattice/UI, just a camera and two
## GPUParticles3D nodes) confirmed sub-emission DOES work correctly under
## Forward Mobile with baseline parameters. Systematically re-adding scene
## structure (WorldEnvironment, CameraRig, KeyLight, hidden Core) never
## broke it either. Reproducing the exact original failing parameters DID
## reproduce the failure, and a binary search isolated the cause to a
## single variable: `spawner.lifetime` -- 1.5s and under works, 1.6s and
## above (the original value) renders blank. The exact internal Godot
## mechanism behind that specific threshold was not identified (tested and
## ruled out: capture timing, visibility_aabb on both nodes, capacity
## overflow, spawner/burst lifetime ratio), but the fix itself is real,
## reproducible, and confirmed against the exact original failing
## configuration otherwise unchanged. `spawner.lifetime` below kept at 1.4s
## (a safety margin under the confirmed 1.5s ceiling), not 1.6s.

const CORE_SURFACE_RADIUS := 1.05
const SPAWNER_COUNT := 16
const SPARK_CAPACITY := 40


func _ready() -> void:
	var burst := _build_burst()
	var spawner := _build_spawner()
	add_child(burst)
	add_child(spawner)
	spawner.sub_emitter = spawner.get_path_to(burst)


func _build_spawner() -> GPUParticles3D:
	var spawner := GPUParticles3D.new()
	spawner.name = "Spawner"
	spawner.amount = SPAWNER_COUNT
	# Kept at 1.4, a safety margin under the confirmed 1.5-works/1.6-fails
	# threshold -- see the header comment for how this was found.
	spawner.lifetime = 1.4
	spawner.local_coords = true
	# No draw_pass_1 assigned -- the spawner has nothing to render, per
	# section 8's explicit "base emission should be disabled by design"
	# instruction. It exists purely as a simulated point source on the
	# core's surface for the sub-emitter below.

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = CORE_SURFACE_RADIUS
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	mat.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_END
	mat.sub_emitter_amount_at_end = 3
	spawner.process_material = mat
	return spawner


func _build_burst() -> GPUParticles3D:
	var burst := GPUParticles3D.new()
	burst.name = "SparkBurst"
	burst.amount = SPARK_CAPACITY
	burst.lifetime = 0.45
	burst.local_coords = false
	# emitting = true (Godot's own default) -- the diagnostic pass confirmed
	# setting this false broke sub-emission entirely; true also gives this
	# node its own independent point-emission at its own (world-origin)
	# position, but that position sits inside the opaque core's silhouette,
	# so it's naturally occluded and has no visible effect.

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.55
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 3.5
	burst.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	burst.draw_pass_1 = quad

	burst.material_override = _build_material()
	return burst


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
	var spawner := get_node_or_null("Spawner") as GPUParticles3D
	if not spawner:
		return
	var activity: float = energy.current_activity
	var intensity: float = energy.current_intensity
	# "Continuous trickle + burst on THINKING/EXECUTING" falls out of the
	# already-set activity values in STATE_PROFILES (THINKING=0.75,
	# EXECUTING=0.9) rather than needing a special-cased state check, same
	# pattern the wisp/shell passes established.
	spawner.amount_ratio = clampf(lerpf(0.15, 1.0, activity), 0.1, 1.0)
	spawner.speed_scale = lerpf(0.5, 1.8, activity)

	var burst := get_node_or_null("SparkBurst") as GPUParticles3D
	var mat := burst.material_override as StandardMaterial3D if burst else null
	if mat:
		# Gold reserved for symbol_reveal/pulse per section 15 -- sparks
		# default to near-white, only leaning gold during a pulse event.
		var pulse_amount: float = clampf(energy.current_pulse, 0.0, 1.0)
		mat.emission = Color(0.96, 0.97, 0.99).lerp(Color(0.85, 0.65, 0.18), pulse_amount * 0.6)
		mat.emission_energy_multiplier = lerpf(1.2, 3.0, intensity)
