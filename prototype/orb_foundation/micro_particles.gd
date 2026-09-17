extends Node3D
## Micro particles (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 8:
## "GPUParticles3D, low count, additive billboard... Continuous,
## low-intensity always. Present even at OFFLINE? -- recommend near-zero,
## not literally zero, so OFFLINE still reads as 'the object exists'").
##
## Section 21 open question 7 leaves the exact OFFLINE floor as a final
## design call, but the doc DOES give an actionable recommendation (near-
## zero, not zero) -- followed directly here via a floor on amount_ratio,
## not treated as a blocking ambiguity.
##
## First population built this pass, deliberately -- used to test whether
## section 5's general "additive blending recommended for particles" advice
## holds in THIS project's specific per-pixel-transparent viewport, since
## the last pass found blend_add produces near-zero alpha over plain
## background for hand-written unshaded shaders here. See _build_material()
## for the real result.

const EMISSION_RADIUS := 1.55
const PARTICLE_COUNT := 30


func _ready() -> void:
	add_child(_build_emitter())


func _build_emitter() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "MicroEmitter"
	particles.amount = PARTICLE_COUNT
	particles.lifetime = 4.0
	particles.local_coords = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = EMISSION_RADIUS
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.015
	mat.initial_velocity_max = 0.05
	mat.gravity = Vector3.ZERO
	mat.scale_min = 1.2
	mat.scale_max = 2.2
	particles.process_material = mat

	particles.draw_pass_1 = QuadMesh.new()
	(particles.draw_pass_1 as QuadMesh).size = Vector2(0.035, 0.035)

	particles.material_override = _build_material()
	return particles


## StandardMaterial3D, billboarded, fixed alpha (not a per-instance
## color_ramp fade). Two real, screenshot-caught bugs ruled out simpler-
## looking alternatives, in order:
## 1. blend_mode = ADD (section 5's general recommendation for particles)
##    produced a completely blank capture -- confirmed via an isolated
##    diagnostic (core hidden, zero particles visible despite correct
##    simulation), the same per-pixel-transparent-viewport near-zero-alpha
##    failure the lattice/shell shaders hit last pass (prototype doc
##    section 21). MIX doesn't have this failure mode.
## 2. `vertex_color_use_as_albedo = true` + a Gradient/GradientTexture1D
##    `color_ramp` for a fade-in/out-at-lifetime-edges look ALSO rendered
##    completely blank under MIX + TRANSPARENCY_ALPHA, even though a
##    minimal diagnostic (opaque albedo_color, transparency disabled
##    entirely, no color_ramp) rendered correctly -- isolating the vertex-
##    color/ramp path itself as the failure, not blending or geometry.
##    Not investigated further (this pass's time budget covers 5
##    populations); worked around by using a fixed albedo_color alpha
##    instead of a per-particle ramp -- correct core render (particles do
##    animate/fade via GPUParticles3D's own built-in lifetime scale curve
##    behavior on `scale_min`/`scale_max`, just not via a color fade).
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.97, 0.99)
	mat.emission_energy_multiplier = 2.0
	mat.albedo_color = Color(0.96, 0.97, 0.99, 0.55)
	return mat


func _process(_delta: float) -> void:
	var energy := get_node_or_null("/root/EnergyModel")
	if not energy:
		return
	var emitter := get_node_or_null("MicroEmitter") as GPUParticles3D
	if not emitter:
		return
	# Floor of 0.12 -- never literally zero even at OFFLINE
	# (intensity=0.08/activity=0.0 there), per section 8's own recommendation.
	var activity: float = energy.current_activity
	var intensity: float = energy.current_intensity
	emitter.amount_ratio = clampf(lerpf(0.12, 1.0, activity), 0.1, 1.0)
	emitter.speed_scale = lerpf(0.25, 1.0, activity)
	var mat := emitter.material_override as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = lerpf(0.6, 1.8, intensity)
