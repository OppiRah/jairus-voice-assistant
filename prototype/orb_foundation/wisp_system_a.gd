extends Node3D
## Candidate A (wisp decision prototype, JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 11 table row 1 / section 19 step 4): GPUParticles3D + trail_enabled +
## RibbonTrailMesh -- "stochastic, limited per-strand shaping... many small,
## organic, less-deliberate currents" per the doc's own framing. Comparison-
## only scaffolding for the wisp technique decision; not the final wisp
## system regardless of which candidate wins.
##
## A small number of emitters (EMITTER_COUNT), each capped at
## PARTICLES_PER_EMITTER -- enough to judge the stochastic character, not a
## production-scale count. Driven by EnergyModel.current_particle_activity /
## current_intensity read directly off the autoload every frame (not a
## second parameter source) via amount_ratio/speed_scale -- the documented
## live-adjustable GPUParticles3D properties (changing `amount` itself at
## runtime restarts the particle system and pops visibly, so it stays fixed
## as a generous cap; amount_ratio scales the visible count without a
## restart).

const EMITTER_COUNT := 3
const PARTICLES_PER_EMITTER := 24
const EMISSION_RADIUS := 1.35

var _emitters: Array[GPUParticles3D] = []
var _shared_material: StandardMaterial3D


func _ready() -> void:
	_shared_material = _build_material()
	for i in range(EMITTER_COUNT):
		var p := _build_emitter(i)
		add_child(p)
		_emitters.append(p)


func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	# Pale gold, matching core.gdshader's color_gold accent rather than a
	# fantasy-magic hue -- kept dim (emission_energy_multiplier tuned live
	# from intensity in _process()) so these stay visually subordinate to
	# the core per the architecture's brightness-hierarchy principle.
	mat.emission = Color(0.85, 0.65, 0.18)
	mat.emission_energy_multiplier = 1.0
	return mat


func _build_emitter(index: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = PARTICLES_PER_EMITTER
	particles.lifetime = 3.0
	particles.trail_enabled = true
	particles.trail_lifetime = 0.5
	particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	mat.emission_sphere_radius = EMISSION_RADIUS
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.15
	mat.gravity = Vector3.ZERO
	# Orbit velocity so strands drift AROUND the core (a "current" read)
	# instead of just drifting outward/inward.
	mat.orbit_velocity_min = 0.08
	mat.orbit_velocity_max = 0.22
	mat.scale_min = 0.6
	mat.scale_max = 1.0

	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.3, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.7, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex

	particles.process_material = mat

	var trail_mesh := RibbonTrailMesh.new()
	trail_mesh.shape = RibbonTrailMesh.SHAPE_FLAT
	trail_mesh.size = 0.035
	trail_mesh.sections = 6
	trail_mesh.section_length = 0.06
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	trail_mesh.curve = taper
	particles.draw_pass_1 = trail_mesh
	particles.material_override = _shared_material

	# Stagger emitters seeding via rotation so all three don't emit in
	# lockstep from the same sphere orientation.
	particles.rotate_y(TAU * float(index) / float(EMITTER_COUNT))
	return particles


func _process(_delta: float) -> void:
	var energy := get_node_or_null("/root/EnergyModel")
	if not energy:
		return
	var activity: float = energy.current_particle_activity
	var intensity: float = energy.current_intensity

	for p in _emitters:
		# Floor of 0.12 so OFFLINE/IDLE still show a few sparse wisps rather
		# than popping to fully empty -- matches particle_activity never
		# being negative but still lets EXECUTING read as visibly denser.
		p.amount_ratio = clampf(lerpf(0.12, 1.0, activity), 0.05, 1.0)
		p.speed_scale = lerpf(0.3, 1.8, activity)

	if _shared_material:
		_shared_material.emission_energy_multiplier = lerpf(0.5, 2.0, intensity)
