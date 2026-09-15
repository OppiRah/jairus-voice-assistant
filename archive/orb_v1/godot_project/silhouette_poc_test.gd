extends Node3D
## silhouette_poc_test.tscn's root script -- standalone silhouette/camera
## investigation test for ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md, NOT
## wired into the real orb_scene.tscn/orb_controller.gd in any way.
## Approximates the real orb's proportions (Core/CoreHousing radii, RingA/
## RingB radii, 4-glass-shell scale band, PLATE_CONFIGS) closely enough to
## judge silhouette containment and camera-driven depth, without needing
## the real scene's full segmented-ring/arc/particle machinery -- this
## test is only about whether plates stay within the established "ring
## band" silhouette and whether a camera change reveals more depth.
##
## Three side-by-side rigs, each its own Node3D at a different X offset,
## each with its own Camera3D (only one active/`current` at a time via
## _ready()'s ACTIVE_RIG index -- Godot only renders from the current
## camera, so three coexisting cameras let this scene be re-screenshotted
## for each rig just by changing ACTIVE_RIG and re-running, no scene
## editing needed):
##   0 = BASELINE: real, unmodified PLATE_CONFIGS (reproduces the
##       "poking out" problem), dead-on camera (matches orb_scene.tscn's
##       real Camera3D transform exactly).
##   1 = FIXED GEOMETRY ONLY: repositioned (not resized) plates, same
##       dead-on camera -- isolates the geometry fix's own contribution.
##   2 = FIXED GEOMETRY + CAMERA: same repositioned plates, plus a small
##       fixed off-axis tilt (no parallax/animation -- that is Pass G's
##       job, out of scope here) -- isolates what the camera change adds
##       on top of the geometry fix alone.
const ACTIVE_RIG := 2  # change to 0/1/2 and re-run to capture each rig

const CORE_RADIUS := 0.5
const HOUSING_RADIUS := 0.64
const RING_A_RADIUS := 1.375  # midpoint of real 1.3/1.45
const RING_B_RADIUS := 1.625  # midpoint of real 1.55/1.7
const RING_A_TUBE := 0.075
const RING_B_TUBE := 0.075
const RING_TILT_DEG := 55.0

# Real PLATE_CONFIGS values, copied verbatim from orb_controller.gd (not
# imported -- this file has zero coupling to the real controller by
# design, same as every other POC in this project) so BASELINE
# reproduces the real, currently-shipped poking-out problem exactly.
const PLATE_CONFIGS_BASELINE := [
	{"angle_deg": 35.0, "radius": 1.12, "height": 0.32, "size": Vector3(0.55, 0.85, 0.035), "rotation_deg": Vector3(20.0, 10.0, 55.0)},
	{"angle_deg": 158.0, "radius": 1.58, "height": -0.42, "size": Vector3(0.4, 0.6, 0.03), "rotation_deg": Vector3(-15.0, 70.0, 10.0)},
	{"angle_deg": 200.0, "radius": 1.3, "height": 0.14, "size": Vector3(0.62, 0.48, 0.04), "rotation_deg": Vector3(35.0, -25.0, 120.0)},
]

# Proposed fix: radius/height pulled inward so (radius + the box's own
# half-diagonal reach) stays under ~1.55 -- comfortably inside RingB's
# 1.7 outer edge -- for every plate, in the worst-case orientation.
# SIZE is deliberately UNCHANGED from baseline (this is the investigation's
# core answer to "does shrinking undermine visibility": apparent on-screen
# size/prominence comes from `size`, not from `radius` -- pulling a
# same-size plate inward preserves its visual weight while fixing
# containment, rather than trading visibility away for containment).
const PLATE_CONFIGS_FIXED := [
	{"angle_deg": 35.0, "radius": 1.0, "height": 0.28, "size": Vector3(0.55, 0.85, 0.035), "rotation_deg": Vector3(20.0, 10.0, 55.0)},
	{"angle_deg": 158.0, "radius": 1.15, "height": -0.34, "size": Vector3(0.4, 0.6, 0.03), "rotation_deg": Vector3(-15.0, 70.0, 10.0)},
	{"angle_deg": 200.0, "radius": 1.1, "height": 0.12, "size": Vector3(0.62, 0.48, 0.04), "rotation_deg": Vector3(35.0, -25.0, 120.0)},
]

const PLATE_BASE_COLOR := Color(0.09, 0.095, 0.11)
const PLATE_METALLIC := 0.65
const PLATE_ROUGHNESS := 0.35

const GLASS_SHELL_SHADER := preload("res://orb_glass_shell.gdshader")
const GLASS_SCALES := [0.8, 0.93, 1.07, 1.2]  # real GLASS_SHELL_CONFIGS' approximate uniform scale per shell


func _ready() -> void:
	_build_rig($Rig0, PLATE_CONFIGS_BASELINE, 0.0)
	_build_rig($Rig1, PLATE_CONFIGS_FIXED, 0.0)
	_build_rig($Rig2, PLATE_CONFIGS_FIXED, 18.0)  # small fixed off-axis tilt, degrees

	# Only one rig may ever be visible at a time: all three occupy the same
	# world-origin coordinates (simplest way to keep each rig's own camera
	# math above unchanged regardless of which is active), so with more
	# than one visible they would render as one overlapping mess even
	# though only one camera is ever `current`.
	var rigs := [$Rig0, $Rig1, $Rig2]
	var cams := [$Rig0/Camera3D, $Rig1/Camera3D, $Rig2/Camera3D]
	for i in range(rigs.size()):
		rigs[i].visible = (i == ACTIVE_RIG)
		cams[i].current = (i == ACTIVE_RIG)

	get_window().size = Vector2i(480, 480)
	print("[silhouette_poc_test] ready, ACTIVE_RIG=", ACTIVE_RIG, " (0=baseline poking-out, 1=fixed geometry only, 2=fixed geometry + camera tilt)")


func _build_rig(rig: Node3D, plate_configs: Array, camera_yaw_deg: float) -> void:
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = CORE_RADIUS
	core_mesh.height = CORE_RADIUS * 2.0
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.emission_enabled = true
	core_mat.albedo_color = Color(0.55, 0.75, 1.0)
	core_mat.emission = Color(0.55, 0.75, 1.0)
	core_mat.emission_energy_multiplier = 4.0
	core.set_surface_override_material(0, core_mat)
	rig.add_child(core)

	var housing := MeshInstance3D.new()
	var housing_mesh := SphereMesh.new()
	housing_mesh.radius = HOUSING_RADIUS
	housing_mesh.height = HOUSING_RADIUS * 2.0
	housing.mesh = housing_mesh
	var housing_mat := ShaderMaterial.new()
	housing_mat.shader = GLASS_SHELL_SHADER
	housing_mat.render_priority = -8
	housing_mat.set_shader_parameter("base_color", Color(0.04, 0.045, 0.06))
	housing_mat.set_shader_parameter("fresnel_power", 4.5)
	housing_mat.set_shader_parameter("rim_alpha", 0.92)
	housing_mat.set_shader_parameter("core_alpha", 0.08)
	housing.set_surface_override_material(0, housing_mat)
	rig.add_child(housing)

	for scale in GLASS_SCALES:
		var shell := MeshInstance3D.new()
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = 1.0
		shell_mesh.height = 2.0
		shell.mesh = shell_mesh
		shell.scale = Vector3.ONE * scale
		var shell_mat := ShaderMaterial.new()
		shell_mat.shader = GLASS_SHELL_SHADER
		shell_mat.render_priority = -5 + int((scale - 0.8) * 10.0)
		shell_mat.set_shader_parameter("base_color", Color(0.6, 0.75, 1.0))
		shell_mat.set_shader_parameter("fresnel_power", 3.0)
		shell_mat.set_shader_parameter("rim_alpha", 0.55)
		shell_mat.set_shader_parameter("core_alpha", 0.06)
		shell.set_surface_override_material(0, shell_mat)
		rig.add_child(shell)

	for ring_data in [[RING_A_RADIUS, RING_A_TUBE], [RING_B_RADIUS, RING_B_TUBE]]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = ring_data[0] - ring_data[1]
		torus.outer_radius = ring_data[0] + ring_data[1]
		ring.mesh = torus
		ring.rotate_x(deg_to_rad(RING_TILT_DEG))
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_mat.emission_enabled = true
		ring_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.4)
		ring_mat.emission = Color(0.55, 0.75, 1.0)
		ring_mat.emission_energy_multiplier = 1.8
		ring.set_surface_override_material(0, ring_mat)
		rig.add_child(ring)

	for config in plate_configs:
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = config["size"]
		plate.mesh = box
		var angle: float = deg_to_rad(config["angle_deg"])
		var radius: float = config["radius"]
		plate.position = Vector3(cos(angle) * radius, config["height"], sin(angle) * radius)
		var rot: Vector3 = config["rotation_deg"]
		plate.rotate_x(deg_to_rad(rot.x))
		plate.rotate_y(deg_to_rad(rot.y))
		plate.rotate_z(deg_to_rad(rot.z))
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = PLATE_BASE_COLOR
		plate_mat.metallic = PLATE_METALLIC
		plate_mat.roughness = PLATE_ROUGHNESS
		plate.set_surface_override_material(0, plate_mat)
		rig.add_child(plate)

	var light := OmniLight3D.new()
	light.position = Vector3(1.5, 1.5, 2.0)
	light.light_energy = 0.6
	light.omni_range = 6.0
	rig.add_child(light)

	var cam := rig.get_node("Camera3D") as Camera3D
	cam.position = Vector3(0, 0, 3)
	if camera_yaw_deg != 0.0:
		# Small fixed off-axis tilt: orbit the camera around the rig's Y
		# axis by camera_yaw_deg while keeping it pointed at the origin,
		# and pitch it down slightly too -- a single static angle change,
		# not animation/parallax (that is Pass G's job, out of scope here).
		var yaw := deg_to_rad(camera_yaw_deg)
		var pitch := deg_to_rad(10.0)
		var dist := 3.0
		cam.position = Vector3(sin(yaw) * dist * cos(pitch), sin(pitch) * dist, cos(yaw) * dist * cos(pitch))
		cam.look_at(Vector3.ZERO, Vector3.UP)
