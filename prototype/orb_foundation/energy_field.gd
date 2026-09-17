extends Node3D
## Energy Field (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 3: "the
## layered translucent 'atmosphere' volume(s) immediately around the core";
## section 6's concrete scene tree: exactly ShellInner + ShellOuter).
##
## Stock SphereMesh (bumped rings/radial_segments for smooth noise
## displacement) rather than the core's hand-built icosphere -- the core's
## icosphere subdivision exists specifically to support core.gdshader's
## large, faceted displacement; this shell only needs a light vertex wobble
## (energy_shell.gdshader's noise_amplitude, far below the core's), so a
## stock primitive is sufficient (Simplicity First).
##
## Deliberately built against the V1 failure mode
## (archive/orb_v1/docs/ORB_CONCEPT_GAP_ANALYSIS.md: "4 equally bright
## concentric shells inherently read as 4 equally-visible nested rings"
## because only transform varied, never appearance): SHELL_INNER and
## SHELL_OUTER get different fresnel_power/base_alpha/intensity_weight
## values below, not just different radii -- see energy_shell.gdshader's
## own header comment for the full reasoning.

const SHELL_SHADER := preload("res://energy_shell.gdshader")

const SHELL_INNER_RADIUS := 1.45
const SHELL_OUTER_RADIUS := 1.85
const SPHERE_RINGS := 24
const SPHERE_RADIAL_SEGMENTS := 32


func _ready() -> void:
	add_child(_build_shell(
		SHELL_INNER_RADIUS, "ShellInner",
		{"fresnel_power": 5.5, "base_alpha": 0.22, "intensity_weight": 0.75, "noise_seed_offset": 0.0}
	))
	add_child(_build_shell(
		SHELL_OUTER_RADIUS, "ShellOuter",
		{"fresnel_power": 2.2, "base_alpha": 0.12, "intensity_weight": 0.2, "noise_seed_offset": 17.3}
	))


func _build_shell(radius: float, node_name: String, params: Dictionary) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.rings = SPHERE_RINGS
	sphere.radial_segments = SPHERE_RADIAL_SEGMENTS

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = sphere

	var mat := ShaderMaterial.new()
	mat.shader = SHELL_SHADER
	for key in params.keys():
		mat.set_shader_parameter(key, params[key])
	mesh_instance.set_surface_override_material(0, mat)

	return mesh_instance
