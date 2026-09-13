extends Node3D
## orb_controller.gd — Jairus Orb Renderer, real integration.
##
## Adapted from orb_renderer_poc/ (validated standalone first -- see
## ORB_RENDERER_INVESTIGATION.md and that folder's own README.md). Connects
## read-only to the real renderer_bridge (src/jairus/interfaces/renderer/
## bridge.py) on port 8767 -- 8765 is the separate, real Android Gateway
## (Phase 13), 8766 was the PoC's own throwaway test port; neither is ever
## touched here. Never calls into anything resembling Jairus's real Agent
## Core/tools -- this process has no awareness of them at all, by design.
##
## Visual richness pass 1 gave every real AssistantStatus value its own
## pulse/particle/glow feel (STATE_PROFILES), not just a color. This
## geometry pass adds new scene content on top, without reworking any of
## that: two semi-transparent TorusMesh rings orbiting the core at
## different tilts/speeds, and two thin emissive "energy arc" ribbons
## built procedurally (SurfaceTool, no external assets/shaders) that
## flicker on and off at a per-state frequency. Both are driven by new
## STATE_PROFILES fields (ring_speed/ring_opacity/arc_intensity/
## arc_frequency), same table, same discipline as the pulse/particle/glow
## fields already there.
##
## Activity text overlay: a screen-space Label (orb_scene.tscn's UI
## CanvasLayer) shows the bridge's real "activity" string verbatim -- no
## new checklist/confirm-cancel UI, that remains out of scope until real
## backend data for it exists. Text fades out/swaps/fades in via a Tween
## rather than cutting instantly, and is tinted from the same _current_color
## driving the rest of the orb (brightened toward white for legibility).

const WS_URL := "ws://localhost:8767"

# idle's breathing frequency (rad/s) before any per-state pulse_speed
# multiplier is applied -- pulse_speed=1.0 reproduces the orb's original,
# pre-richness feel exactly.
const BASE_PULSE_FREQUENCY := 1.6

# COMPLETED's brief "brightness pop, then settle" transient: triggered
# once on genuine entry into the completed state (not re-triggered by
# every message while already completed), decaying linearly to 0 over
# this many seconds. Tunable independently of the steady-state profile
# values below.
const POP_DURATION_SECONDS := 1.0
const POP_EMISSION_BOOST := 2.5  # extra emission_energy_multiplier at the instant the pop starts
const POP_GLOW_BOOST := 0.8      # extra glow_intensity at the instant the pop starts

const EMISSION_ENERGY := 3.5  # baseline HDR multiplier so the core color actually blooms (unchanged from the PoC)

# Rings: RingB always rotates at RING_B_SPEED_FACTOR times RingA's speed
# (and RingA/RingB spin around different axes -- set once in _ready() via
# rotate_x()/rotate_y(), not hand-computed transform matrices, so there's
# no risk of an accidentally-skewed rotation) so the two never move in
# lockstep, reading as two independent orbits rather than one ring
# duplicated.
const RING_B_SPEED_FACTOR := -0.7  # negative: opposite direction, slightly slower

# Both rings tilt the same amount away from facing the camera (TorusMesh's
# default face-normal is the local Z axis, which starts pointed straight at
# Camera3D) -- confirmed via a real rendered screenshot that RING_TILT_DEG's
# distance from 0 controls how edge-on a ring reads, regardless of which
# axis it's tilted around: the original pass tilted RingA 60 degrees around
# X (read as a clear ellipse) but RingB 75 degrees around Y (read as a
# nearly edge-on flat bar, since 75 degrees is much closer to the 90-degree
# edge-on limit). Both rings now share the same X tilt so both stay equally
# readable, and RingB gets an additional Z-axis roll on top -- a roll spins
# the already-tilted ellipse's orientation within the image plane without
# changing how edge-on it is, so it's the safe way to make the two rings
# still look like distinct crossing orbits.
const RING_TILT_DEG := 55.0  # tilt around X, shared by both rings
const RING_B_ROLL_DEG := 90.0  # RingB's extra Z-axis roll, applied after the shared tilt

# Energy arcs: built once as static ribbon meshes at _ready() (regenerating
# geometry every frame is real, avoidable CSG/mesh-rebuild cost this pass
# doesn't need) -- their "crackling" comes from rotating slowly plus
# flickering visibility on/off at a per-state frequency, not from
# reshaping. See _build_arc_mesh()'s own comment for why a hand-built
# SurfaceTool ribbon was chosen over a custom shader or CSG.
const ARC_POINT_COUNT := 7        # vertices along one arc's path
const ARC_RADIUS := 0.75          # distance from the core center the arc path sits at
const ARC_SPAN_RADIANS := PI * 0.6  # how much of a circle one arc sweeps
const ARC_JAGGEDNESS := 0.08      # max perpendicular offset applied to interior points, for a "lightning" feel
const ARC_THICKNESS := 0.015      # ribbon half-width
const ARC_ROTATION_SPEED := 0.35  # rad/s, both arcs rotate at this fixed rate regardless of state (only visibility/brightness vary per state)
const ARC_FLICKER_THRESHOLD := 0.3  # sin(...) must exceed this to be visible -- higher = rarer/shorter flashes at a given frequency
const ARC_EMISSION_ENERGY := 4.0  # baseline HDR multiplier for arc material, independent of the core's EMISSION_ENERGY

# Activity text overlay: shows the real "activity" string the bridge sends
# (assistant_state.py's _current_activity, defaulting to "Idle" -- matched
# here so both renderers agree on the idle default). No new palette: the
# label is tinted by the same lerped _current_color driving the rest of the
# orb, just blended toward white so it stays legible against a dark or
# transparent desktop background (a raw state color like OFFLINE's
# near-gray would otherwise be too dim to read).
const ACTIVITY_TEXT_BRIGHTEN := 0.45  # lerp weight toward Color.WHITE
const ACTIVITY_FADE_SECONDS := 0.25   # each half of the fade-out/swap/fade-in transition

# One row per real AssistantStatus value -- every value that makes a
# state FEEL different, not just a different color, lives here as a
# single named table rather than scattered through _process()'s logic,
# so a future tuning pass only ever needs to edit these numbers.
#
# "idle" reproduces this scene's original pre-richness behavior exactly
# for pulse/particle/glow (pulse_speed 1.0, particle_amount 0.3,
# glow_intensity/strength matching orb_scene.tscn's original Environment
# defaults) -- seeing this feel validated is a design constraint, not a
# coincidence. ring_speed/ring_opacity/arc_intensity/arc_frequency are
# new this pass; full per-state reasoning (why ERROR's rings are fast and
# chaotic, why OFFLINE's are nearly still, etc.) is in this pass's
# integration report. Colors for executing/completed/error/offline
# deliberately reuse the exact RGB values theme.py's ORB_COLORS already
# picked for the Qt orb (Phase 9) -- one project, one meaning per state,
# even across two independent rendering surfaces. waiting_confirmation
# has no Python-side color to borrow (theme.py deliberately omits one,
# since it never fires there either) so it gets a new, distinct amber.
const STATE_PROFILES := {
	"idle": {
		"color": Color(70.0 / 255.0, 130.0 / 255.0, 200.0 / 255.0),
		"pulse_speed": 1.0, "pulse_irregular": false,
		"particle_amount": 0.3, "particle_speed": 1.0,
		"glow_intensity": 1.2, "glow_strength": 1.3,
		"ring_speed": 0.15, "ring_opacity": 0.35,
		"arc_intensity": 1.0, "arc_frequency": 0.15,
	},
	"listening": {
		"color": Color(60.0 / 255.0, 200.0 / 255.0, 140.0 / 255.0),
		"pulse_speed": 1.1, "pulse_irregular": false,
		"particle_amount": 0.35, "particle_speed": 1.1,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.25, "ring_opacity": 0.45,
		"arc_intensity": 1.2, "arc_frequency": 0.3,
	},
	"thinking": {
		"color": Color(170.0 / 255.0, 90.0 / 255.0, 220.0 / 255.0),
		"pulse_speed": 1.8, "pulse_irregular": true,
		"particle_amount": 0.4, "particle_speed": 1.3,
		"glow_intensity": 1.3, "glow_strength": 1.3,
		"ring_speed": 0.6, "ring_opacity": 0.5,
		"arc_intensity": 1.4, "arc_frequency": 0.8,
	},
	"speaking": {
		"color": Color(250.0 / 255.0, 170.0 / 255.0, 60.0 / 255.0),
		"pulse_speed": 1.0, "pulse_irregular": false,
		"particle_amount": 0.3, "particle_speed": 1.0,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.2, "ring_opacity": 0.4,
		"arc_intensity": 1.3, "arc_frequency": 0.4,
	},
	"executing": {
		"color": Color(60.0 / 255.0, 190.0 / 255.0, 210.0 / 255.0),
		"pulse_speed": 1.3, "pulse_irregular": false,
		"particle_amount": 0.55, "particle_speed": 1.4,
		"glow_intensity": 1.4, "glow_strength": 1.5,
		"ring_speed": 0.7, "ring_opacity": 0.55,
		"arc_intensity": 1.5, "arc_frequency": 0.5,
	},
	"completed": {
		"color": Color(210.0 / 255.0, 250.0 / 255.0, 225.0 / 255.0),
		"pulse_speed": 0.8, "pulse_irregular": false,
		"particle_amount": 0.25, "particle_speed": 0.9,
		"glow_intensity": 1.2, "glow_strength": 1.3,
		"ring_speed": 0.3, "ring_opacity": 0.5,
		"arc_intensity": 1.6, "arc_frequency": 0.2,
	},
	"error": {
		"color": Color(224.0 / 255.0, 82.0 / 255.0, 79.0 / 255.0),
		"pulse_speed": 2.2, "pulse_irregular": true,
		"particle_amount": 0.6, "particle_speed": 1.8,
		"glow_intensity": 1.5, "glow_strength": 1.6,
		"ring_speed": 1.4, "ring_opacity": 0.6,
		"arc_intensity": 1.8, "arc_frequency": 1.5,
	},
	"offline": {
		"color": Color(74.0 / 255.0, 77.0 / 255.0, 94.0 / 255.0),
		"pulse_speed": 0.3, "pulse_irregular": false,
		"particle_amount": 0.03, "particle_speed": 0.2,
		"glow_intensity": 0.3, "glow_strength": 0.4,
		"ring_speed": 0.02, "ring_opacity": 0.1,
		"arc_intensity": 0.3, "arc_frequency": 0.0,
	},
	"waiting_confirmation": {
		"color": Color(235.0 / 255.0, 195.0 / 255.0, 80.0 / 255.0),
		"pulse_speed": 0.9, "pulse_irregular": false,
		"particle_amount": 0.35, "particle_speed": 1.0,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.2, "ring_opacity": 0.4,
		"arc_intensity": 1.1, "arc_frequency": 0.25,
	},
}

@onready var core: MeshInstance3D = $Core
@onready var particles: GPUParticles3D = $AmbientParticles
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var ring_a: MeshInstance3D = $RingA
@onready var ring_b: MeshInstance3D = $RingB
@onready var arc_a: MeshInstance3D = $ArcA
@onready var arc_b: MeshInstance3D = $ArcB
@onready var activity_label: Label = $UI/ActivityLabel

var _socket := WebSocketPeer.new()
var _connected_once := false
var _current_state := "idle"
var _current_color: Color = STATE_PROFILES["idle"]["color"]
var _target_color: Color = STATE_PROFILES["idle"]["color"]
var _level := 0.0
var _elapsed := 0.0
var _material: StandardMaterial3D
var _environment: Environment
var _pop_remaining := 0.0  # seconds left in COMPLETED's brightness-pop-then-settle transient
var _ring_material_a: StandardMaterial3D
var _ring_material_b: StandardMaterial3D
var _arc_material_a: StandardMaterial3D
var _arc_material_b: StandardMaterial3D
var _particle_material: StandardMaterial3D
var _current_activity := "Idle"  # matches ActivityLabel's own .tscn default text
var _activity_tween: Tween


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true  # see _make_translucent_material()'s comment -- same fix, applied here too
	core.set_surface_override_material(0, _material)
	_environment = world_environment.environment
	_apply_color(_current_color)

	# AmbientParticles previously drew with no material at all (its
	# SphereMesh_particle draw pass had no surface material assigned), so it
	# fell back to Godot's default lit material -- dim gray dots relying on
	# the scene's one weak OmniLight3D, not the bright glowing sparks the
	# rest of the orb uses. material_override replaces that for every
	# particle instance with the same emissive/unshaded material family as
	# the core/rings/arcs, tinted from _current_color each frame in _process().
	_particle_material = _make_translucent_material()
	particles.material_override = _particle_material

	_ring_material_a = _make_translucent_material()
	ring_a.set_surface_override_material(0, _ring_material_a)
	ring_a.rotate_x(deg_to_rad(RING_TILT_DEG))

	_ring_material_b = _make_translucent_material()
	ring_b.set_surface_override_material(0, _ring_material_b)
	ring_b.rotate_x(deg_to_rad(RING_TILT_DEG))
	ring_b.rotate_z(deg_to_rad(RING_B_ROLL_DEG))

	_arc_material_a = _make_translucent_material()
	arc_a.mesh = _build_arc_mesh(0.0)
	arc_a.set_surface_override_material(0, _arc_material_a)

	_arc_material_b = _make_translucent_material()
	arc_b.mesh = _build_arc_mesh(3.3)  # different seed_offset -> a differently-jagged path than ArcA
	arc_b.set_surface_override_material(0, _arc_material_b)
	arc_b.rotate_y(deg_to_rad(120.0))  # offset so the two arcs don't start overlapping

	print("[orb_controller] geometry ready: RingA/RingB (TorusMesh), ArcA vertices=%d, ArcB vertices=%d" % [
		arc_a.mesh.surface_get_array_len(0), arc_b.mesh.surface_get_array_len(0),
	])

	var err := _socket.connect_to_url(WS_URL)
	if err != OK:
		print("[orb_controller] connect_to_url failed immediately: ", err)


func _make_translucent_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# emission_enabled defaults to false on StandardMaterial3D -- without it,
	# setting .emission/.emission_energy_multiplier does nothing at all, and
	# the WorldEnvironment's glow effect (which only blooms pixels above
	# glow_hdr_threshold) never sees anything bright enough to bloom. This
	# was the confirmed root cause of "no visible glow" (rendering-quality
	# pass): every value in STATE_PROFILES was real, but no material had
	# emission switched on to make use of them.
	mat.emission_enabled = true
	return mat


## Builds one "energy arc" as a flat emissive ribbon (a strip of triangles
## following a short jagged path around the core), via SurfaceTool -- a
## real Godot core API needing no shader files or external assets.
## Considered and rejected: a custom .gdshader (visual result impossible
## to validate without a GPU session, and headless mode's dummy renderer
## wouldn't even exercise shader compilation, so a broken shader could
## pass every test here and still fail for real); CSGPolygon3D path
## extrusion (a real, asset-free option too, but CSG boolean geometry is
## comparatively expensive to keep live-reshaping, and this pass doesn't
## need reshaping -- a ribbon built once and just rotated is cheaper and
## just as controllable for a first pass). seed_offset only changes the
## deterministic jag pattern (via sin(), not randomness) so ArcA and ArcB
## look different from each other while staying reproducible for testing.
func _build_arc_mesh(seed_offset: float) -> ArrayMesh:
	var points: PackedVector3Array = []
	for i in range(ARC_POINT_COUNT):
		var t := float(i) / float(ARC_POINT_COUNT - 1)
		var angle := -ARC_SPAN_RADIANS * 0.5 + ARC_SPAN_RADIANS * t
		var point := Vector3(sin(angle), 0.0, cos(angle)) * ARC_RADIUS
		if i > 0 and i < ARC_POINT_COUNT - 1:
			point.y += sin((t * 11.0 + seed_offset) * TAU) * ARC_JAGGEDNESS
		points.append(point)

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

		var perp := direction.cross(Vector3.UP)
		if perp.length() < 0.001:
			perp = direction.cross(Vector3.RIGHT)
		perp = perp.normalized() * ARC_THICKNESS

		st.add_vertex(points[i] - perp)
		st.add_vertex(points[i] + perp)

	# No generate_normals() call: SurfaceTool only supports it for
	# PRIMITIVE_TRIANGLES, not the PRIMITIVE_TRIANGLE_STRIP used here
	# (confirmed by a real runtime error during testing, not assumed) --
	# and the arc material is unshaded, so normals are unused anyway.
	return st.commit()


func _process(delta: float) -> void:
	_elapsed += delta
	_poll_socket()

	var profile: Dictionary = STATE_PROFILES.get(_current_state, STATE_PROFILES["idle"])

	# smooth transition between states, same spirit as the real orb's
	# breathing/pulse math (assistant_state.py's level + a sine breathe) --
	# preserved unchanged from the validated PoC.
	_current_color = _current_color.lerp(_target_color, delta * 4.0)
	_apply_color(_current_color)

	var breathe := _compute_breathe(profile["pulse_speed"], profile["pulse_irregular"])
	var pulse_scale := 1.0 + 0.12 * breathe + 0.25 * _level
	core.scale = Vector3.ONE * pulse_scale

	var particle_baseline: float = profile["particle_amount"]
	if particles:
		particles.amount_ratio = clamp(particle_baseline + _level, 0.0, 1.0)
		particles.speed_scale = profile["particle_speed"]
	_particle_material.albedo_color = _current_color
	_particle_material.emission = _current_color
	_particle_material.emission_energy_multiplier = EMISSION_ENERGY

	var glow_intensity: float = profile["glow_intensity"]
	var glow_strength: float = profile["glow_strength"]
	var emission_energy := EMISSION_ENERGY

	if _pop_remaining > 0.0:
		_pop_remaining = max(0.0, _pop_remaining - delta)
		var pop_factor := _pop_remaining / POP_DURATION_SECONDS  # 1.0 the instant it starts, linearly down to 0.0
		glow_intensity += POP_GLOW_BOOST * pop_factor
		emission_energy += POP_EMISSION_BOOST * pop_factor

	if _environment:
		_environment.glow_intensity = glow_intensity
		_environment.glow_strength = glow_strength
	_material.emission_energy_multiplier = emission_energy

	_update_rings(delta, profile)
	_update_arcs(delta, profile)

	activity_label.add_theme_color_override("font_color", _current_color.lerp(Color.WHITE, ACTIVITY_TEXT_BRIGHTEN))


func _update_rings(delta: float, profile: Dictionary) -> void:
	var ring_speed: float = profile["ring_speed"]
	var ring_opacity: float = profile["ring_opacity"]

	ring_a.rotate_z(ring_speed * delta)
	ring_b.rotate_z(ring_speed * RING_B_SPEED_FACTOR * delta)

	var ring_color := Color(_current_color.r, _current_color.g, _current_color.b, ring_opacity)
	for mat in [_ring_material_a, _ring_material_b]:
		mat.albedo_color = ring_color
		mat.emission = _current_color
		mat.emission_energy_multiplier = EMISSION_ENERGY * 0.6


func _update_arcs(delta: float, profile: Dictionary) -> void:
	var frequency: float = profile["arc_frequency"]
	var intensity: float = profile["arc_intensity"]

	arc_a.rotate_y(ARC_ROTATION_SPEED * delta)
	arc_b.rotate_y(-ARC_ROTATION_SPEED * 0.8 * delta)

	# Deterministic on/off flicker: two different phase offsets so ArcA and
	# ArcB don't flash in perfect unison even at the same frequency.
	# frequency == 0.0 (OFFLINE) means the sine term is constant, always
	# below the threshold -- arcs correctly never light up, not "broken".
	var flicker_a := sin(_elapsed * TAU * frequency)
	var flicker_b := sin(_elapsed * TAU * frequency + 2.1)

	var visible_a := flicker_a > ARC_FLICKER_THRESHOLD
	var visible_b := flicker_b > ARC_FLICKER_THRESHOLD

	arc_a.visible = visible_a
	arc_b.visible = visible_b

	if visible_a:
		_arc_material_a.albedo_color = _current_color
		_arc_material_a.emission = _current_color
		_arc_material_a.emission_energy_multiplier = ARC_EMISSION_ENERGY * intensity
	if visible_b:
		_arc_material_b.albedo_color = _current_color
		_arc_material_b.emission = _current_color
		_arc_material_b.emission_energy_multiplier = ARC_EMISSION_ENERGY * intensity


func _compute_breathe(pulse_speed: float, irregular: bool) -> float:
	var freq := BASE_PULSE_FREQUENCY * pulse_speed
	if irregular:
		# a second wave at a non-integer-multiple frequency plus a phase
		# offset means the sum never settles into a clean, predictable
		# repeating beat -- reads as "searching"/"agitated" rather than a
		# regular breath, without needing anything randomized (still
		# fully deterministic/reproducible for testing).
		var wave1 := sin(_elapsed * freq)
		var wave2 := sin(_elapsed * freq * 0.41 + 1.7)
		return (wave1 * 0.6 + wave2 * 0.4 + 1.0) / 2.0
	return (sin(_elapsed * freq) + 1.0) / 2.0


func _poll_socket() -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected_once:
			_connected_once = true
			print("[orb_controller] connected to ", WS_URL)
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			_handle_message(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected_once:
			var code := _socket.get_close_code()
			print("[orb_controller] connection closed, code=", code)
			_connected_once = false


func _handle_message(raw_text: String) -> void:
	var data = JSON.parse_string(raw_text)
	if data == null or not (data is Dictionary):
		print("[orb_controller] received unparseable message: ", raw_text)
		return

	print("[orb_controller] received state message: ", data)

	var new_state: String = data.get("state", "idle")
	if not STATE_PROFILES.has(new_state):
		new_state = "idle"

	if new_state != _current_state:
		if new_state == "completed":
			_pop_remaining = POP_DURATION_SECONDS
		var profile: Dictionary = STATE_PROFILES[new_state]
		print("[orb_controller] entered state '%s' -> pulse_speed=%.2f pulse_irregular=%s particle_amount=%.2f particle_speed=%.2f glow_intensity=%.2f glow_strength=%.2f ring_speed=%.2f ring_opacity=%.2f arc_intensity=%.2f arc_frequency=%.2f" % [
			new_state, profile["pulse_speed"], profile["pulse_irregular"], profile["particle_amount"],
			profile["particle_speed"], profile["glow_intensity"], profile["glow_strength"],
			profile["ring_speed"], profile["ring_opacity"], profile["arc_intensity"], profile["arc_frequency"],
		])

	_current_state = new_state
	_target_color = STATE_PROFILES[new_state]["color"]
	_level = clamp(float(data.get("level", 0.0)), 0.0, 1.0)

	var new_activity: String = data.get("activity", "Idle")
	if new_activity != _current_activity:
		print("[orb_controller] activity changed: '%s' -> '%s'" % [_current_activity, new_activity])
		_current_activity = new_activity
		_set_activity_text(new_activity)


func _apply_color(color: Color) -> void:
	_material.albedo_color = color
	_material.emission = color


## Swaps the activity label's text with a brief fade-out/swap/fade-in
## instead of an instant hard cut, using the engine's own Tween (no new
## animation system). Kills any tween still running from a rapid prior
## change so overlapping fades never fight over the label's alpha.
func _set_activity_text(new_text: String) -> void:
	if _activity_tween:
		_activity_tween.kill()
	_activity_tween = create_tween()
	_activity_tween.tween_property(activity_label, "modulate:a", 0.0, ACTIVITY_FADE_SECONDS)
	_activity_tween.tween_callback(activity_label.set_text.bind(new_text))
	_activity_tween.tween_property(activity_label, "modulate:a", 1.0, ACTIVITY_FADE_SECONDS)
