extends Node3D
## Candidate B (wisp decision prototype, JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 11 table row 2 / section 19 step 4): a small number of static,
## hand-placed "hero" tubes built from Curve3D, shader-driven flow -- "full
## artistic control of path shape... a small number of hero currents whose
## exact path matters" per the doc's own framing. Comparison-only
## scaffolding for the wisp technique decision; not the final wisp system
## regardless of which candidate wins.
##
## Mesh-building technique (camera-facing ribbon strip via SurfaceTool,
## PRIMITIVE_TRIANGLE_STRIP, UV.x tagging position-along-path) and the flow-
## animation technique it feeds (wisp_hero_ribbon.gdshader) are both reused
## directly from archive/orb_v1/godot_project/orb_controller.gd's
## _build_ribbon_strip_mesh()/orb_arc_ribbon.gdshader -- not rebuilt from
## zero, per that precedent already being a working, tested mechanism for
## exactly this "camera-facing emissive ribbon along a path" technique.

const HERO_SHADER := preload("res://wisp_hero_ribbon.gdshader")

const HERO_COUNT := 3
const RIBBON_RADIUS := 1.55
const RIBBON_THICKNESS := 0.035
const CURVE_ANCHOR_COUNT := 5  # hand-placed control points per hero path
const TESSELLATE_STAGES := 4   # Curve3D.tessellate() subdivision

var _ribbons: Array[MeshInstance3D] = []


func _ready() -> void:
	var camera := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = camera.global_position if camera else Vector3(0, 0, 3)

	for i in range(HERO_COUNT):
		var curve := _build_hero_curve(i)
		var points: PackedVector3Array = curve.tessellate(TESSELLATE_STAGES, 4)
		var mesh := _build_ribbon_strip_mesh(points, cam_pos)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh

		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = HERO_SHADER
		shader_mat.set_shader_parameter("time_offset", float(i) * 2.4)
		# Alternate white/gold so the three hero currents read as distinct
		# strands rather than one uniform color, matching core.gdshader's
		# existing white/gold palette rather than introducing a new hue.
		var color := Color(0.96, 0.97, 0.99) if i % 2 == 0 else Color(0.85, 0.65, 0.18)
		shader_mat.set_shader_parameter("base_color", color)
		mesh_instance.set_surface_override_material(0, shader_mat)

		add_child(mesh_instance)
		_ribbons.append(mesh_instance)


## Hand-placed anchor points on a sphere around the core, one path per hero
## index -- deterministic, not random, matching this project's existing
## "reproducible, not random" principle (see wisp_hero_ribbon.gdshader's
## header comment on the same point). Each hero gets a distinct orientation
## (theta_start/phi_center) and a mild radius/phi meander so paths read as
## gently curved currents in 3D, not flat rings confined to one plane.
func _hero_anchor_points(index: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var theta_start := TAU * float(index) / float(HERO_COUNT)
	var theta_span := deg_to_rad(150.0)
	var phi_center := deg_to_rad(70.0 + index * 25.0)
	for i in range(CURVE_ANCHOR_COUNT):
		var t := float(i) / float(CURVE_ANCHOR_COUNT - 1)
		var theta := theta_start + theta_span * t
		var phi := phi_center + sin(t * TAU * 1.3 + float(index)) * deg_to_rad(18.0)
		var r := RIBBON_RADIUS * (1.0 + 0.06 * sin(t * TAU * 2.0 + float(index) * 1.7))
		pts.append(Vector3(
			r * sin(phi) * cos(theta),
			r * cos(phi),
			r * sin(phi) * sin(theta)
		))
	return pts


func _build_hero_curve(index: int) -> Curve3D:
	var curve := Curve3D.new()
	var anchors := _hero_anchor_points(index)
	for i in range(anchors.size()):
		var handle := Vector3.ZERO
		if i > 0 and i < anchors.size() - 1:
			handle = (anchors[i + 1] - anchors[i - 1]) * 0.25
		elif i == 0:
			handle = (anchors[i + 1] - anchors[i]) * 0.25
		else:
			handle = (anchors[i] - anchors[i - 1]) * 0.25
		curve.add_point(anchors[i], -handle, handle)
	return curve


## Reused near-verbatim from archive/orb_v1/godot_project/orb_controller.gd's
## _build_ribbon_strip_mesh() -- camera-facing thickness direction
## (direction.cross(cam_pos - point)) so the strip stays visible regardless
## of which way its path bends in 3D, same fix that precedent's own comment
## documents finding necessary for a non-planar path.
func _build_ribbon_strip_mesh(points: PackedVector3Array, cam_pos: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(points.size()):
		var direction: Vector3
		if i == 0:
			direction = (points[i + 1] - points[i]).normalized()
		elif i == points.size() - 1:
			direction = (points[i] - points[i - 1]).normalized()
		else:
			direction = (points[i + 1] - points[i - 1]).normalized()

		var perp := direction.cross(cam_pos - points[i])
		if perp.length() < 0.001:
			perp = direction.cross(Vector3.UP)
		perp = perp.normalized() * RIBBON_THICKNESS

		var t := float(i) / float(points.size() - 1)
		st.set_uv(Vector2(t, 0.0))
		st.add_vertex(points[i] - perp)
		st.set_uv(Vector2(t, 1.0))
		st.add_vertex(points[i] + perp)

	return st.commit()
