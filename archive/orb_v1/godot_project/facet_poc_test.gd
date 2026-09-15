extends Node3D
## facet_poc_test.tscn's root script -- standalone plate-material
## investigation test for ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md's
## Problem 2, NOT wired into the real orb_scene.tscn/orb_controller.gd in
## any way. Five variants side by side, same OmniLight3D (matching the
## real scene's light_energy=0.6 position/range), same base dark color,
## so the only difference between them is geometry + material:
##
## A) Flat BoxMesh + the real, currently-shipped metal StandardMaterial3D
##    (PLATE_METALLIC/PLATE_ROUGHNESS from orb_controller.gd) -- baseline,
##    reproduces the "flat dark cardboard" problem.
## B) Faceted crystal-shard mesh (hand-built via SurfaceTool, real
##    per-face flat normals -- not smoothed) + the SAME metal
##    StandardMaterial3D as A -- isolates geometry's own contribution,
##    with material held constant.
## C) Same faceted mesh + StandardMaterial3D with rim_enabled (Godot's
##    built-in opaque rim-light feature) added on top of the same
##    metallic/roughness -- candidate recommendation: real per-facet PBR
##    specular from the actual light, PLUS a cheap glass-like edge
##    highlight, while staying fully opaque (no custom shader, no
##    transparency-sorting risk).
## D) Same faceted mesh + the real, already-validated
##    orb_glass_shell.gdshader reused AS-IS (unshaded, Fresnel-only) --
##    tests the investigation's literal "extend the existing Fresnel
##    technique to the plates" question honestly, including its real cost
##    (losing real light response, see the investigation doc's findings).
##    A BackgroundMarker sits behind this one specifically so lensing
##    (lens_distortion > 0) has something visible to warp, for the
##    same-scene-lensing sub-question.
## E) Flat BoxMesh (same geometry as A) + facet_fake_normal.gdshader (the
##    "cheap procedural per-facet shading" alternative) -- tests whether
##    faking facet normals on an actually-flat surface reads as
##    convincingly different from flat, or just as a flat surface with a
##    fake pattern on it.

const PLATE_BASE_COLOR := Color(0.09, 0.095, 0.11)
const PLATE_METALLIC := 0.65
const PLATE_ROUGHNESS := 0.35

const CRYSTAL_EQUATOR_RADIUS := 0.32
const CRYSTAL_HALF_HEIGHT := 0.4
const CRYSTAL_SIDES := 6

const GLASS_SHELL_SHADER := preload("res://orb_glass_shell.gdshader")
const FAKE_NORMAL_SHADER := preload("res://facet_fake_normal.gdshader")


func _ready() -> void:
	get_window().size = Vector2i(1700, 560)

	var crystal_mesh := _build_crystal_shard(CRYSTAL_EQUATOR_RADIUS, CRYSTAL_HALF_HEIGHT, CRYSTAL_SIDES)
	var flat_mesh := BoxMesh.new()
	flat_mesh.size = Vector3(0.42, 0.9, 0.06)

	# A: flat box + real metal material (baseline)
	_spawn(flat_mesh, _metal_material(), Vector3(-3.2, 0, 0))

	# B: faceted crystal + same metal material (geometry-only contribution)
	_spawn(crystal_mesh, _metal_material(), Vector3(-1.6, 0, 0))

	# C: faceted crystal + metal material WITH built-in rim (candidate)
	var rim_mat := _metal_material()
	rim_mat.rim_enabled = true
	rim_mat.rim = 0.65
	rim_mat.rim_tint = 0.35
	_spawn(crystal_mesh, rim_mat, Vector3(0, 0, 0))

	# D: faceted crystal + existing unshaded Fresnel shell shader, reused
	# as-is. BackgroundMarker placed behind it for the lensing check.
	var fresnel_mat := ShaderMaterial.new()
	fresnel_mat.shader = GLASS_SHELL_SHADER
	fresnel_mat.set_shader_parameter("base_color", Vector3(0.6, 0.75, 1.0))
	fresnel_mat.set_shader_parameter("fresnel_power", 3.0)
	fresnel_mat.set_shader_parameter("rim_alpha", 0.85)
	fresnel_mat.set_shader_parameter("core_alpha", 0.05)
	fresnel_mat.set_shader_parameter("lens_distortion", 0.12)  # >0 on purpose -- see the investigation doc's lensing finding: toggling this to 0.0 for comparison during testing showed only a marginal difference from ordinary alpha blending against BackgroundMarker, well within this shader's already-documented lensing limits
	_spawn(crystal_mesh, fresnel_mat, Vector3(1.6, 0, 0))

	var marker := MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.5
	marker_mesh.height = 1.0
	marker.mesh = marker_mesh
	marker.position = Vector3(1.6, 0, -1.6)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.emission_enabled = true
	marker_mat.albedo_color = Color(1.0, 0.1, 0.85)
	marker_mat.emission = Color(1.0, 0.1, 0.85)
	marker_mat.emission_energy_multiplier = 2.0
	marker.set_surface_override_material(0, marker_mat)
	add_child(marker)

	# E: flat box (same geometry as A) + procedural fake-facet shader
	var fake_mat := ShaderMaterial.new()
	fake_mat.shader = FAKE_NORMAL_SHADER
	_spawn(flat_mesh, fake_mat, Vector3(3.2, 0, 0))

	print("[facet_poc_test] ready: A=flat+metal, B=facet+metal, C=facet+metal+rim, D=facet+fresnel(unshaded)+lensing, E=flat+fake-facet-shader")


func _metal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLATE_BASE_COLOR
	mat.metallic = PLATE_METALLIC
	mat.roughness = PLATE_ROUGHNESS
	return mat


func _spawn(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.rotate_y(deg_to_rad(50.0))
	inst.rotate_x(deg_to_rad(18.0))
	inst.set_surface_override_material(0, mat)
	add_child(inst)


## Hexagonal bipyramid ("crystal shard"): a top apex, a bottom apex, and
## `sides` equator points, forming 2*sides triangular facets. Each facet
## gets its OWN three vertex copies (never shared with a neighboring
## facet) with the SAME flat per-face normal on all three -- the
## structural property a single flat plate cannot have regardless of
## material: real, distinct face normals that catch the scene's one
## OmniLight3D differently per face.
func _build_crystal_shard(equator_radius: float, half_height: float, sides: int) -> ArrayMesh:
	var top := Vector3(0, half_height, 0)
	var bottom := Vector3(0, -half_height, 0)
	var equator: Array[Vector3] = []
	for i in range(sides):
		var angle := float(i) / float(sides) * TAU
		equator.append(Vector3(cos(angle) * equator_radius, 0.0, sin(angle) * equator_radius))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var a: Vector3 = equator[i]
		var b: Vector3 = equator[(i + 1) % sides]

		var n_top := (b - a).cross(top - a).normalized()
		st.set_normal(n_top)
		st.add_vertex(top)
		st.set_normal(n_top)
		st.add_vertex(a)
		st.set_normal(n_top)
		st.add_vertex(b)

		var n_bottom := (a - b).cross(bottom - b).normalized()
		st.set_normal(n_bottom)
		st.add_vertex(bottom)
		st.set_normal(n_bottom)
		st.add_vertex(b)
		st.set_normal(n_bottom)
		st.add_vertex(a)

	return st.commit()
