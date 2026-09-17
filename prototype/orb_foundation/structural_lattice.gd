extends Node3D
## Structural Lattice (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 3:
## "thin rings/curves establishing the orbital silhouette"; section 6's
## concrete scene tree: exactly RingA + RingB, "built once from a Curve3D
## tessellation"). Uses Godot's stock TorusMesh primitive directly rather
## than hand-sweeping a tube mesh along a Curve3D -- section 4 explicitly
## lists "a small hand-placed MeshInstance3D torus/arc set" as an equally
## valid option to Curve3D tessellation for this exact component, and
## TorusMesh is a real, built-in Godot primitive (Simplicity First: no
## reason to hand-build geometry a stock node already provides).
##
## Differentiated from each other via material response and orientation
## (see lattice_ring.gdshader's activity_weight), not via broken/gapped
## geometry -- section 2's "symmetrical at rest; asymmetry is a function of
## transient energy behavior, not base geometry" governs this pass, not the
## older archived V1 fix that went the segmented/angular route.
##
## Orientation/radius, both real screenshot-caught mistakes during this
## pass, since corrected:
## 1. TorusMesh's *default* orientation already faces this scene's camera
##    (confirmed via an isolated diagnostic, diag_ring_only.tscn/.gd, with
##    an opaque high-contrast placeholder shader) -- a large from-default
##    rotation (the first fix attempted) turns a working face-on ring INTO
##    a genuinely edge-on, invisible one; the correct move is a *small*
##    tilt from the default, not a large one toward "face-on."
## 2. A too-large first radius (~2.0) sat close enough to this camera's
##    frustum edge to clip; a too-small second radius (1.55-1.7) mostly hid
##    behind the core's own opaque depth (core's max displaced radius is
##    ~1.34, so a ring only ~20-25% larger than that has most of its
##    circumference occluded by the core's depth-tested silhouette,
##    leaving only short visible crescents near the edge that read as
##    near-straight strokes rather than an obviously curved halo). Radius
##    below clears the core with real margin while still fitting this
##    camera's frustum (half-height ~2.3 at z=3).
## 3. Compound two-axis rotations (rotation_degrees with all three of X/Y/Z
##    set) produced less predictable results than a clean single-axis tilt
##    per ring -- each ring below rotates around exactly one axis.

const RING_SHADER := preload("res://lattice_ring.gdshader")

const RING_A_RADIUS := 1.95
const RING_B_RADIUS := 1.78
const TUBE_THICKNESS := 0.028


func _ready() -> void:
	# Small tilts (kept well under 30 degrees) so each ring reads as a
	# rounded halo encircling the object -- a real screenshot-caught
	# finding: larger tilts (32/38 degrees, tried first) made both rings
	# look like eccentric straight-ish slashes rather than orbital rings,
	# even once fully visible (see the blend_mix fix above).
	add_child(_build_ring(RING_A_RADIUS, Vector3(16.0, 0.0, 0.0), 0.35, "RingA"))
	add_child(_build_ring(RING_B_RADIUS, Vector3(0.0, 0.0, -20.0), 0.8, "RingB"))


func _build_ring(radius: float, rotation_deg: Vector3, activity_weight: float, node_name: String) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.outer_radius = radius
	torus.inner_radius = radius - TUBE_THICKNESS
	torus.rings = 6
	torus.ring_segments = 48

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = torus
	mesh_instance.rotation_degrees = rotation_deg

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("activity_weight", activity_weight)
	mesh_instance.set_surface_override_material(0, mat)

	return mesh_instance
