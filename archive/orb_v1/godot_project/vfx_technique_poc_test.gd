extends Node3D
## vfx_technique_poc_test.tscn's root script -- standalone technique
## investigation for ORB_VFX_TECHNIQUE_ANALYSIS.md (JAIRUS_ORB_VFX_
## TECHNIQUE_REFERENCE.md's mapping task), NOT wired into the real
## orb_scene.tscn/orb_controller.gd in any way. Four objects side by
## side, testing the two techniques confirmed genuinely absent from the
## real codebase (grep for NoiseTexture2D/FastNoiseLite/billboard_mode/
## BILLBOARD across every file in this folder returned zero matches
## before this PoC was written):
##
## A) Baseline: a flat, uniformly emissive sphere -- the real orb's
##    CURRENT core recipe exactly (StandardMaterial3D, unshaded,
##    emission_enabled, one flat color/energy). Control for B.
## B) Same sphere, same base color/energy, but noise_core_poc.gdshader:
##    a real FastNoiseLite-generated NoiseTexture2D scrolled across the
##    surface to modulate emission brightness -- tests design-doc
##    section 4's still-open "subtle internal motion" for the core
##    specifically (not a replacement of the core's material family,
##    an additive modulation on top of the same flat base).
## C) A billboard (camera-facing) QuadMesh with billboard_wisp_poc.gdshader,
##    use_noise=0 -- a plain soft radial-falloff glow, procedural (no
##    image asset), additive blending. Tests whether a billboard reads
##    as a convincing soft energy phenomenon in this transparent-desktop
##    context at all, before adding noise.
## D) Same billboard quad, use_noise=1 -- a real FastNoiseLite texture
##    breaks up the plain radial falloff into an irregular "wisp" shape.
##    Direct before/after of the SAME billboard technique, isolating
##    what noise specifically adds over a plain soft-glow billboard.

const NOISE_CORE_SHADER := preload("res://noise_core_poc.gdshader")
const BILLBOARD_WISP_SHADER := preload("res://billboard_wisp_poc.gdshader")


func _ready() -> void:
	get_window().size = Vector2i(1500, 520)

	var noise_tex := _make_noise_texture(0.15)
	var wisp_noise_tex := _make_noise_texture(0.15)

	# A: baseline flat emissive sphere (real orb's current core recipe)
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 1.0
	var baseline := MeshInstance3D.new()
	baseline.mesh = sphere_mesh
	baseline.position = Vector3(-3.3, 0, 0)
	var baseline_mat := StandardMaterial3D.new()
	baseline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	baseline_mat.emission_enabled = true
	baseline_mat.albedo_color = Color(0.55, 0.75, 1.0)
	baseline_mat.emission = Color(0.55, 0.75, 1.0)
	baseline_mat.emission_energy_multiplier = 4.0
	baseline.set_surface_override_material(0, baseline_mat)
	add_child(baseline)

	# B: same sphere, noise-modulated internal motion. Getting this to
	# actually show anything took real debugging (see this PoC's own
	# findings in ORB_VFX_TECHNIQUE_ANALYSIS.md) -- three real bugs, not
	# tuning taste: (1) the shader originally left ALBEDO a flat constant
	# and only modulated EMISSION, and on an unshaded material ALBEDO
	# alone already dominates the visible pixel, masking the modulation
	# entirely; (2) `noise_tex` had no `repeat_enable` hint, so any
	# noise_scale pushing sampled UV outside [0,1] clamped to a single
	# edge texel across most of the surface; (3) FastNoiseLite frequency
	# has to be matched to how much of the noise texture the visible
	# UV range actually covers -- too low aliases flat (limited range
	# never leaves one "blob"), too high aliases flat too (per-texel
	# noise gets minification-blurred to uniform gray). frequency=0.15/
	# noise_scale=2.0 (this PoC's final values) is the specific
	# combination confirmed, by real screenshot, to actually show
	# visible, animating grain -- not a value to treat as universally
	# correct for a different mesh/UV setup.
	var noise_core := MeshInstance3D.new()
	noise_core.mesh = sphere_mesh
	noise_core.position = Vector3(-1.1, 0, 0)
	var noise_mat := ShaderMaterial.new()
	noise_mat.shader = NOISE_CORE_SHADER
	noise_mat.set_shader_parameter("noise_tex", noise_tex)
	noise_mat.set_shader_parameter("noise_strength", 1.0)  # deliberately pushed well past a plausible production value -- if the effect can't be seen even here, it can't be seen at any value worth shipping
	noise_mat.set_shader_parameter("noise_scale", 2.0)
	noise_mat.set_shader_parameter("emission_energy", 6.0)  # matches the real orb's CORE_GLOW_EMISSION_ENERGY exactly -- the real test of whether this survives at production intensity, not just at a convenient low PoC value
	noise_core.set_surface_override_material(0, noise_mat)
	add_child(noise_core)

	# C: billboard wisp, plain radial falloff (no noise)
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(1.6, 1.6)
	var wisp_plain := MeshInstance3D.new()
	wisp_plain.mesh = quad_mesh
	wisp_plain.position = Vector3(1.1, 0, 0)
	var wisp_plain_mat := ShaderMaterial.new()
	wisp_plain_mat.shader = BILLBOARD_WISP_SHADER
	wisp_plain_mat.set_shader_parameter("use_noise", 0.0)
	wisp_plain_mat.render_priority = 1
	wisp_plain.set_surface_override_material(0, wisp_plain_mat)
	add_child(wisp_plain)

	# D: same billboard quad, real FastNoiseLite-driven wisp shape
	var wisp_noisy := MeshInstance3D.new()
	wisp_noisy.mesh = quad_mesh
	wisp_noisy.position = Vector3(3.3, 0, 0)
	var wisp_noisy_mat := ShaderMaterial.new()
	wisp_noisy_mat.shader = BILLBOARD_WISP_SHADER
	wisp_noisy_mat.set_shader_parameter("use_noise", 1.0)
	wisp_noisy_mat.set_shader_parameter("noise_tex", wisp_noise_tex)
	wisp_noisy_mat.render_priority = 1
	wisp_noisy.set_surface_override_material(0, wisp_noisy_mat)
	add_child(wisp_noisy)

	print("[vfx_technique_poc_test] ready: A=flat core (baseline), B=noise-modulated core, C=billboard wisp (no noise), D=billboard wisp (FastNoiseLite)")


## Real Godot FastNoiseLite -> NoiseTexture2D, generated once at startup
## (no image asset, same discipline as every procedural mesh already in
## this project) -- `frequency` controls how fine/coarse the resulting
## pattern reads at the sampled UV scale each shader applies on top.
func _make_noise_texture(frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	return tex
