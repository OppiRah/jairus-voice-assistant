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
## built procedurally (SurfaceTool, no external assets/shaders). Both are
## driven by new STATE_PROFILES fields (ring_speed/ring_opacity/
## arc_intensity/arc_frequency), same table, same discipline as the
## pulse/particle/glow fields already there. (The arcs' original binary
## on/off flicker was later replaced -- see the Pass B "ribbons take 2"
## note below.)
##
## Activity text overlay: a screen-space Label (orb_scene.tscn's UI
## CanvasLayer) shows the bridge's real "activity" string verbatim -- no
## new checklist/confirm-cancel UI, that remains out of scope until real
## backend data for it exists. Text fades out/swaps/fades in via a Tween
## rather than cutting instantly, and is tinted from the same _current_color
## driving the rest of the orb (brightened toward white for legibility).
##
## Pass A -- redesigned core (per ORB_CONCEPT_GAP_ANALYSIS.md's two named
## core problems): the former plain "Core" sphere is now the innermost
## layer of three: CoreEmblem (a flat, opaque, procedurally-built 4-point
## star -- same asset-free SurfaceTool technique as the energy arcs, since
## no existing Jairus brand mark was found anywhere in the repo) sits just
## in front of Core (now the "glow" sphere, shrunk to make room), which
## itself sits inside CoreHousing, a shell reusing the same validated
## Fresnel technique as the outer glass shells (orb_glass_shell.gdshader)
## but inverted in intent: dark near-opaque at the rim (a real silhouette,
## "housing"), transparent at center (so the glow/emblem read through it)
## -- the only geometrically-correct way to get "dark shell around visible
## inner glow" with concentric same-center spheres, since two solid
## same-center spheres of different opaque radii can never produce a
## visible rim (the larger one, whichever color, fully occludes the
## smaller one from every angle -- verified by working through the
## near-surface-distance math before building this, not assumed). This
## also fixes the measured core/arc emission-hierarchy inversion the gap
## analysis found: ARC_EMISSION_ENERGY is lowered and new
## CORE_GLOW_EMISSION_ENERGY/CORE_EMBLEM_EMISSION_ENERGY constants (times
## each state's new core_intensity) are set so the core outbrights the
## arcs in every one of the 9 states, not just at baseline.
##
## Pass B (structure) -- segmented rings + dark plates, see the
## RING_A_SEGMENTS/PLATE_CONFIGS comments further down. Left completely
## alone by every pass after it, including this one.
##
## Pass B (energy ribbons, take 2) -- the arcs' original binary
## sin()>threshold on/off flicker read as choppy, not "fluid/organic"
## (design doc section 6's explicit contrast against the rigid, precise
## rings/segments/plates). Replaced with: (1) ARC_POINT_COUNT raised from
## 7 to 31 so the same deterministic path reads as a smooth curve, and
## (2) orb_arc_ribbon.gdshader, a small new shader (same established
## pattern as CoreHousing/the glass shells, not a new technique) that
## reads each vertex's UV.x -- tagging its position along the ribbon,
## added in _build_arc_mesh() -- to drive a brightness wave that
## genuinely travels along the ribbon's length over time and never
## reaches true zero, replacing the hard on/off cut entirely. Particle
## trails (mentioned as optional in both the design doc and the gap
## analysis) were investigated and deliberately not built this pass --
## see this pass's own report for why.

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

const EMISSION_ENERGY := 3.5  # baseline HDR multiplier for particles/rings only now -- see CORE_GLOW_EMISSION_ENERGY below for the core itself (Pass A split this out so the core could be raised independently)

# Pass A core-emission constants: the core (glow sphere + emblem, combined)
# must outbloom the energy arcs in every one of the 9 states, including
# ERROR (arc_intensity's highest value, 1.8) -- not just at idle baseline,
# which is exactly the bug the gap analysis measured (arcs previously used
# a flat 4.0 base, higher than the core's flat 3.5, in every state). Checked
# by hand across all 9 STATE_PROFILES rows below: with ARC_EMISSION_ENERGY
# lowered to 2.2, the worst-case arc value is error's 2.2*1.8=3.96, while
# the worst-case *core* value is offline's 6.0*0.2=1.2 for the glow sphere
# alone -- still comfortably ahead of every arc value except offline, where
# offline's own arc_frequency is 0.0 (arcs never actually become visible
# there at all, per _update_arcs()'s existing flicker-threshold logic) and
# the emblem alone (9.0*0.2=1.8) still exceeds it. See this pass's own
# report for the full per-state table.
const CORE_GLOW_EMISSION_ENERGY := 6.0
const CORE_EMBLEM_EMISSION_ENERGY := 9.0  # the emblem is always the single brightest element in the scene -- it's the intended focal point
const CORE_EMBLEM_BRIGHTEN := 0.55  # lerp weight toward Color.WHITE, same legibility technique already used for ActivityLabel -- keeps the symbol reading as a sharp, distinct mark rather than just another same-hue glow

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

# Pass B -- segmented ring geometry (per ORB_CONCEPT_GAP_ANALYSIS.md's
# structure gap and design-doc section 5: "Do not simply keep adding
# complete torus rings"). RingA/RingB are no longer single TorusMesh
# nodes; each is now a Node3D container (still receiving the same
# RING_TILT_DEG/RING_B_ROLL_DEG transform as before, unchanged) holding
# several flat ribbon segments with real angular gaps between them,
# built with the same SurfaceTool triangle-strip technique already
# validated twice in this project (the energy arcs, and Pass A's
# CoreHousing reuse of the glass shell shader) -- no new geometry-
# building approach introduced. Segments lie flat in the local XY plane
# (matching TorusMesh's own default orientation, per RING_TILT_DEG's
# existing comment above), parameterized directly by inner/outer radius
# rather than the arcs' tangent-perpendicular method: a circular path's
# "thickness direction" at any point IS the radial direction, so this is
# simpler and exactly equivalent for a ring shape.
#
# Each entry: start_deg/span_deg lay out real, deliberately UNEQUAL
# segment lengths and gaps (section 12's "controlled asymmetry" -- not
# evenly-sliced, not symmetric) -- verified by hand to be non-overlapping
# and to leave a visible gap before wrapping back to the first segment.
# speed_factor is used starting in this pass's stage 2 (independent
# per-segment rotation); stage 1 builds the geometry only.
const RING_SEGMENT_DEGREES_PER_POINT := 8.0  # geometry density along a segment's arc -- similar vertex spacing to the energy arcs
const RING_A_INNER_RADIUS := 1.3
const RING_A_OUTER_RADIUS := 1.45
const RING_A_SEGMENTS := [
	{"start_deg": 40.0, "span_deg": 70.0, "speed_factor": 1.4},
	{"start_deg": 135.0, "span_deg": 50.0, "speed_factor": -0.6},
	{"start_deg": 220.0, "span_deg": 85.0, "speed_factor": 0.85},
	{"start_deg": 325.0, "span_deg": 35.0, "speed_factor": 1.15},
]
const RING_B_INNER_RADIUS := 1.55
const RING_B_OUTER_RADIUS := 1.7
const RING_B_SEGMENTS := [
	{"start_deg": 70.0, "span_deg": 100.0, "speed_factor": -0.75},
	{"start_deg": 220.0, "span_deg": 60.0, "speed_factor": 1.25},
	{"start_deg": 310.0, "span_deg": 40.0, "speed_factor": 0.9},
]

# Pass B -- dark angular "plate" elements (design-doc section 8: metal/
# mechanical components should contrast with everything luminous). Unlike
# every other material in this file, plates deliberately do NOT go
# through _make_translucent_material() -- they keep StandardMaterial3D's
# real default shading (shading_mode is left at its default
# SHADING_MODE_PER_PIXEL, emission_enabled left at its default false), so
# the scene's existing OmniLight3D gives them genuine specular
# highlights instead of another flat unshaded glow. metallic/roughness
# push that further toward "brushed dark metal." Placement (angle_deg/
# radius/height/rotation_deg) is deliberately UNEVEN -- not evenly
# spaced around the circle, not mirrored, different depths -- per
# section 12's "controlled asymmetry": three distinct numbers chosen by
# hand, not a formula that would produce even spacing.
const PLATE_BASE_COLOR := Color(0.09, 0.095, 0.11)
const PLATE_METALLIC := 0.65
const PLATE_ROUGHNESS := 0.35
const PLATE_SPIN_SPEED := 0.12  # rad/s at plate_activity=1.0 -- slow and heavy-feeling, not energetic like the rings/arcs
const PLATE_CONFIGS := [
	{
		"angle_deg": 35.0, "radius": 1.12, "height": 0.32,
		"size": Vector3(0.55, 0.85, 0.035), "rotation_deg": Vector3(20.0, 10.0, 55.0),
	},
	{
		"angle_deg": 158.0, "radius": 1.58, "height": -0.42,
		"size": Vector3(0.4, 0.6, 0.03), "rotation_deg": Vector3(-15.0, 70.0, 10.0),
	},
	{
		# Bug fix (post-Pass-B): originally angle_deg=262.0, radius=0.92 --
		# at 262 degrees, sin(262 deg) ~= -0.99, so the position vector
		# landed almost entirely along local Z, the SAME axis the camera
		# looks down. That put Plate3 only ~2.8 degrees off the camera's
		# view axis while sitting farther from the camera (world Z ~= -0.91)
		# than the opaque Core sphere (radius 0.5 at the origin, angular
		# radius ~9.5 degrees from the camera) -- so the Core fully eclipsed
		# it, confirmed by a real diagnostic print of both angles before
		# touching any numbers, not assumed. Enlarging the old radius alone
		# would NOT have fixed this: at angle_deg=262 nearly the entire
		# position vector is radial along the view axis, so a bigger radius
		# mostly just pushes the plate further behind the Core, not further
		# off-axis. angle_deg=200.0 keeps sin/cos more balanced (position
		# offset lands mostly in X, which IS perpendicular to the view
		# axis), putting the plate at ~19.7 degrees off-axis -- clear of the
		# Core's ~9.5-degree occlusion cone with real margin. radius raised
		# 0.92->1.3 alongside it (still a distinct third radius from Plate1's
		# 1.12/Plate2's 1.58) for a clearer, less core-adjacent silhouette.
		# height/size/rotation_deg untouched -- rotation was never the
		# problem (face_to_camera_deg=42 degrees, a perfectly normal
		# readable angle, not edge-on).
		"angle_deg": 200.0, "radius": 1.3, "height": 0.14,
		"size": Vector3(0.62, 0.48, 0.04), "rotation_deg": Vector3(35.0, -25.0, 120.0),
	},
]

# Energy arcs: built once as static ribbon meshes at _ready() (regenerating
# geometry every frame is real, avoidable CSG/mesh-rebuild cost this pass
# doesn't need) -- their "crackling" comes from rotating slowly plus a
# continuous brightness wave traveling along their length (Pass B: energy
# ribbons take 2 -- see ARC_SHADER and orb_arc_ribbon.gdshader below),
# not from reshaping. See _build_arc_mesh()'s own comment for why a
# hand-built SurfaceTool ribbon was chosen over CSG.
const ARC_POINT_COUNT := 31        # Pass B: raised from 7 -- same underlying sin()-based path formula in _build_arc_mesh(), just sampled far more densely, so the identical deterministic curve reads as a smooth flowing line instead of a jagged low-poly one.
const ARC_RADIUS := 0.75          # distance from the core center the arc path sits at
const ARC_SPAN_RADIANS := PI * 0.6  # how much of a circle one arc sweeps
const ARC_JAGGEDNESS := 0.08      # max perpendicular offset applied to interior points, for a "lightning" feel
const ARC_THICKNESS := 0.015      # ribbon half-width
const ARC_ROTATION_SPEED := 0.35  # rad/s, both arcs rotate at this fixed rate regardless of state (only brightness varies per state now)
const ARC_EMISSION_ENERGY := 2.2  # Pass A: lowered from 4.0 -- at the old value the arcs out-bloomed the core in every state (a measured bug, see CORE_GLOW_EMISSION_ENERGY above); this baseline, times arc_intensity (max 1.8 at error), now stays under the core's floor in every state

# Pass B (energy ribbons take 2) -- orb_arc_ribbon.gdshader replaces the
# old binary sin()>threshold on/off flicker with a continuous brightness
# wave that genuinely travels along the ribbon's length (using each
# vertex's UV.x, set in _build_arc_mesh() above) rather than the whole
# ribbon snapping uniformly on or off. This is a new small shader, but
# not a new TECHNIQUE for this project -- CoreHousing and the 4 glass
# shells already use hand-written .gdshader materials for exactly this
# kind of continuous, state-driven visual behavior; this is the same
# established pattern applied to the arcs. ARC_RIPPLE_CYCLES is
# structural (how many visible brightness waves fit along one ribbon at
# once) and stays fixed; flow speed and turbulence (how deep the ripple
# dips) come from STATE_PROFILES below, pushed as shader parameters every
# frame in _update_arcs(), same as every other shader material here.
const ARC_SHADER := preload("res://orb_arc_ribbon.gdshader")
const ARC_RIPPLE_CYCLES := 2.0
const ARC_ALPHA := 0.6

# Activity text overlay: shows the real "activity" string the bridge sends
# (assistant_state.py's _current_activity, defaulting to "Idle" -- matched
# here so both renderers agree on the idle default). No new palette: the
# label is tinted by the same lerped _current_color driving the rest of the
# orb, just blended toward white so it stays legible against a dark or
# transparent desktop background (a raw state color like OFFLINE's
# near-gray would otherwise be too dim to read).
const ACTIVITY_TEXT_BRIGHTEN := 0.45  # lerp weight toward Color.WHITE
const ACTIVITY_FADE_SECONDS := 0.25   # each half of the fade-out/swap/fade-in transition

const GLASS_SHELL_SHADER := preload("res://orb_glass_shell.gdshader")

# Full Fresnel glass + layered depth pass: 4 concentric, non-uniformly-
# scaled (ellipsoid, not perfect-sphere -- a plain sphere looks identical
# under any rotation, so an ellipsoid is what actually makes "varying
# rotations/tilts" visible) glass shells around the core, reusing the
# Fresnel rim-lighting technique validated in glass_poc_fresnel.gdshader
# (ORB_RENDERER_INVESTIGATION.md section 9). power_offset/rim_offset/tint
# are per-shell STRUCTURAL differences (so the 4 shells read as distinct
# layers even in the same state); STATE_PROFILES' glass_rim_intensity/
# glass_lens_strength below are the per-STATE behavior layered on top of
# these, same "structural constant + state-driven multiplier" split
# already used for rings (RING_TILT_DEG is structural; ring_speed/
# ring_opacity are per-state). power_offset increases outward (innermost
# shell has the broadest/softest rim, outermost the sharpest/brightest) so
# the 4 layers read as "energy building outward," echoing the concept
# image's layered-depth feel.
const GLASS_BASE_FRESNEL_POWER := 3.0
const GLASS_BASE_RIM_ALPHA := 0.65
const GLASS_CORE_ALPHA := 0.06  # near-invisible body so the core/rings stay the visual focus, not the glass itself
const GLASS_LENS_DISTORTION_BASE := 0.05  # deliberately subtle -- see orb_glass_shell.gdshader's own comment on what this can and can't show

# Sizing/visibility note (revised after two real screenshots): attempt 1
# spread the 4 shells from radius 0.85 to 1.85, directly overlapping
# RingA/RingB's own 1.3-1.7 band -- read as a muddy stack of extra "rings"
# competing with the actual rings. Attempt 2 clustered them at 0.8-1.2
# (safely under RingA's 1.3 inner radius), which fixed that, but a
# Fresnel-lit sphere always brightens its own silhouette edge -- 4 equally
# bright concentric shells inherently read as 4 equally-visible nested
# rings, not "glass depth" (an intrinsic property of the technique on a
# static front view, not a tunable bug). This third pass keeps the same
# sizing but makes the inner two shells deliberately much dimmer (soft
# ambient haze around the core, barely visible on their own) so only the
# outer two read as distinct glass edges -- fewer equally-weighted rings,
# more "soft glow building outward to a visible edge."
const GLASS_SHELL_CONFIGS := [
	{
		"scale": Vector3(0.8, 0.77, 0.8), "tilt_x_deg": 10.0, "tilt_z_deg": 0.0,
		"power_offset": -1.0, "rim_offset": -0.42, "tint": Color(0.02, 0.0, -0.02),
		"render_priority": -5,
	},
	{
		"scale": Vector3(0.93, 0.89, 0.91), "tilt_x_deg": 25.0, "tilt_z_deg": 40.0,
		"power_offset": -0.4, "rim_offset": -0.30, "tint": Color(0.0, 0.02, 0.02),
		"render_priority": -4,
	},
	{
		"scale": Vector3(1.07, 1.02, 1.05), "tilt_x_deg": 40.0, "tilt_z_deg": 90.0,
		"power_offset": 0.3, "rim_offset": -0.02, "tint": Color(-0.02, 0.0, 0.03),
		"render_priority": -3,
	},
	{
		"scale": Vector3(1.2, 1.13, 1.17), "tilt_x_deg": 55.0, "tilt_z_deg": 140.0,
		"power_offset": 0.9, "rim_offset": 0.05, "tint": Color(0.03, -0.01, 0.02),
		"render_priority": -1,
	},
]

# render_priority for every OTHER layered-transparent element, chosen to
# match their real radial position relative to the 4 glass shells above
# (arcs at radius 0.75, particles scattered around ~1.1 on average --
# approximate, since particles actually move outward over their lifetime,
# so a single static priority can only ever be a reasonable estimate --
# RingA at inner/outer 1.3/1.45, RingB at 1.55/1.7) so the combined draw
# order is consistently "innermost first, outermost last" across every
# transparent object in the scene, not just within the glass shells
# themselves. This is the investigation's named mitigation for AABB-based
# sorting being unreliable when multiple transparent objects share (near
# enough) the same center -- exactly this scene's shape now that there are
# 4 more concentric objects than before.
const RENDER_PRIORITY_CORE_HOUSING := -8  # innermost transparent object in the scene (radius 0.64, smaller than the arcs' 0.75) -- drawn first, per the same "innermost first" convention as everything below
const RENDER_PRIORITY_ARCS := -6
const RENDER_PRIORITY_PARTICLES := -2
const RENDER_PRIORITY_RING_A := 0
const RENDER_PRIORITY_RING_B := 1

# CoreHousing reuses GLASS_SHELL_SHADER (same Fresnel technique as the 4
# outer glass shells) but with the *opposite* visual intent: dark and
# near-opaque at the rim (a real, deliberate silhouette -- "housing"),
# transparent at center (so the glow sphere and emblem inside read
# through it, unobstructed). A high fresnel_power keeps that rim tight
# and sharp rather than a soft glass-like gradient, and lens_distortion
# is left at 0 -- a dark shell has no reason to visibly warp anything
# behind it, unlike the bright outer shells where the lensing reads as
# part of the "glass" material language.
const CORE_HOUSING_BASE_COLOR := Color(0.04, 0.045, 0.06)
const CORE_HOUSING_FRESNEL_POWER := 4.5
const CORE_HOUSING_RIM_ALPHA := 0.92
const CORE_HOUSING_CORE_ALPHA := 0.08
const CORE_HOUSING_LENS_DISTORTION := 0.0

# CoreEmblem: a flat, opaque, 4-point "sparkle" star built once via
# SurfaceTool (same asset-free approach _build_arc_mesh() already uses) --
# see this pass's report for why no existing Jairus mark was reused (none
# exists in the repo). Positioned just outside the glow sphere's own front
# surface (glow radius 0.5, see SphereMesh_core in orb_scene.tscn) so it's
# never occluded by the opaque glow sphere behind it.
const EMBLEM_OUTER_RADIUS := 0.32
const EMBLEM_INNER_RADIUS := 0.09
const EMBLEM_POINTS := 4
const EMBLEM_Z_OFFSET := 0.53

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
# integration report. glass_rim_intensity/glass_lens_strength (full
# Fresnel glass pass) multiply the 4 glass shells' structural per-shell
# baselines (GLASS_SHELL_CONFIGS) -- e.g. ERROR's shells run brighter/more
# distorted, OFFLINE's are barely visible, matching each state's existing
# ring/arc/particle behavior rather than introducing a new, separate mood.
# Colors for executing/completed/error/offline
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
		"glass_rim_intensity": 1.0, "glass_lens_strength": 1.0,
		"core_intensity": 1.0,
		"segment_spread": 0.35,
		"plate_activity": 0.3,
		"arc_turbulence": 0.25,
	},
	"listening": {
		"color": Color(60.0 / 255.0, 200.0 / 255.0, 140.0 / 255.0),
		"pulse_speed": 1.1, "pulse_irregular": false,
		"particle_amount": 0.35, "particle_speed": 1.1,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.25, "ring_opacity": 0.45,
		"arc_intensity": 1.2, "arc_frequency": 0.3,
		"glass_rim_intensity": 1.1, "glass_lens_strength": 1.1,
		"core_intensity": 1.05,
		"segment_spread": 0.45,
		"plate_activity": 0.4,
		"arc_turbulence": 0.3,
	},
	"thinking": {
		"color": Color(170.0 / 255.0, 90.0 / 255.0, 220.0 / 255.0),
		"pulse_speed": 1.8, "pulse_irregular": true,
		"particle_amount": 0.4, "particle_speed": 1.3,
		"glow_intensity": 1.3, "glow_strength": 1.3,
		"ring_speed": 0.6, "ring_opacity": 0.5,
		"arc_intensity": 1.4, "arc_frequency": 0.8,
		"glass_rim_intensity": 1.3, "glass_lens_strength": 1.6,
		"core_intensity": 1.15,
		"segment_spread": 1.0,
		"plate_activity": 0.8,
		"arc_turbulence": 0.6,
	},
	"speaking": {
		"color": Color(250.0 / 255.0, 170.0 / 255.0, 60.0 / 255.0),
		"pulse_speed": 1.0, "pulse_irregular": false,
		"particle_amount": 0.3, "particle_speed": 1.0,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.2, "ring_opacity": 0.4,
		"arc_intensity": 1.3, "arc_frequency": 0.4,
		"glass_rim_intensity": 1.15, "glass_lens_strength": 1.1,
		"core_intensity": 1.05,
		"segment_spread": 0.5,
		"plate_activity": 0.4,
		"arc_turbulence": 0.35,
	},
	"executing": {
		"color": Color(60.0 / 255.0, 190.0 / 255.0, 210.0 / 255.0),
		"pulse_speed": 1.3, "pulse_irregular": false,
		"particle_amount": 0.55, "particle_speed": 1.4,
		"glow_intensity": 1.4, "glow_strength": 1.5,
		"ring_speed": 0.7, "ring_opacity": 0.55,
		"arc_intensity": 1.5, "arc_frequency": 0.5,
		"glass_rim_intensity": 1.4, "glass_lens_strength": 1.3,
		"core_intensity": 1.2,
		"segment_spread": 0.7,
		"plate_activity": 0.6,
		"arc_turbulence": 0.45,
	},
	"completed": {
		"color": Color(210.0 / 255.0, 250.0 / 255.0, 225.0 / 255.0),
		"pulse_speed": 0.8, "pulse_irregular": false,
		"particle_amount": 0.25, "particle_speed": 0.9,
		"glow_intensity": 1.2, "glow_strength": 1.3,
		"ring_speed": 0.3, "ring_opacity": 0.5,
		"arc_intensity": 1.6, "arc_frequency": 0.2,
		"glass_rim_intensity": 1.2, "glass_lens_strength": 0.8,
		"core_intensity": 1.1,
		"segment_spread": 0.5,
		"plate_activity": 0.35,
		"arc_turbulence": 0.3,
	},
	"error": {
		"color": Color(224.0 / 255.0, 82.0 / 255.0, 79.0 / 255.0),
		"pulse_speed": 2.2, "pulse_irregular": true,
		"particle_amount": 0.6, "particle_speed": 1.8,
		"glow_intensity": 1.5, "glow_strength": 1.6,
		"ring_speed": 1.4, "ring_opacity": 0.6,
		"arc_intensity": 1.8, "arc_frequency": 1.5,
		"glass_rim_intensity": 1.6, "glass_lens_strength": 2.0,
		"core_intensity": 1.3,
		"segment_spread": 1.2,
		"plate_activity": 1.0,
		"arc_turbulence": 0.85,
	},
	"offline": {
		"color": Color(74.0 / 255.0, 77.0 / 255.0, 94.0 / 255.0),
		"pulse_speed": 0.3, "pulse_irregular": false,
		"particle_amount": 0.03, "particle_speed": 0.2,
		"glow_intensity": 0.3, "glow_strength": 0.4,
		"ring_speed": 0.02, "ring_opacity": 0.1,
		"arc_intensity": 0.3, "arc_frequency": 0.0,
		"glass_rim_intensity": 0.15, "glass_lens_strength": 0.1,
		"core_intensity": 0.2,
		"segment_spread": 0.05,
		"plate_activity": 0.02,
		"arc_turbulence": 0.1,
	},
	"waiting_confirmation": {
		"color": Color(235.0 / 255.0, 195.0 / 255.0, 80.0 / 255.0),
		"pulse_speed": 0.9, "pulse_irregular": false,
		"particle_amount": 0.35, "particle_speed": 1.0,
		"glow_intensity": 1.3, "glow_strength": 1.4,
		"ring_speed": 0.2, "ring_opacity": 0.4,
		"arc_intensity": 1.1, "arc_frequency": 0.25,
		"glass_rim_intensity": 1.1, "glass_lens_strength": 1.0,
		"core_intensity": 1.05,
		"segment_spread": 0.5,
		"plate_activity": 0.35,
		"arc_turbulence": 0.35,
	},
}

@onready var core: MeshInstance3D = $Core
@onready var particles: GPUParticles3D = $AmbientParticles
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var ring_a: Node3D = $RingA  # Pass B: container for segments, not a single mesh anymore -- see RING_A_SEGMENTS
@onready var ring_b: Node3D = $RingB
@onready var arc_a: MeshInstance3D = $ArcA
@onready var arc_b: MeshInstance3D = $ArcB
@onready var activity_label: Label = $UI/ActivityLabel
@onready var glass_shells: Array[MeshInstance3D] = [$GlassShell1, $GlassShell2, $GlassShell3, $GlassShell4]
@onready var core_housing: MeshInstance3D = $CoreHousing
@onready var core_emblem: MeshInstance3D = $CoreEmblem
@onready var plates: Array[MeshInstance3D] = [$Plate1, $Plate2, $Plate3]

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
var _arc_material_a: ShaderMaterial
var _arc_material_b: ShaderMaterial
var _particle_material: StandardMaterial3D
var _current_activity := "Idle"  # matches ActivityLabel's own .tscn default text
var _activity_tween: Tween
var _glass_materials: Array[ShaderMaterial] = []
var _housing_material: ShaderMaterial
var _emblem_material: StandardMaterial3D
var _ring_segments_a: Array[MeshInstance3D] = []
var _ring_segments_b: Array[MeshInstance3D] = []


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true  # see _make_translucent_material()'s comment -- same fix, applied here too
	core.set_surface_override_material(0, _material)
	_environment = world_environment.environment
	_apply_color(_current_color)

	# Pass A: CoreHousing (dark Fresnel-rim shell, see its constants' own
	# comment for why this is the correct technique) and CoreEmblem (a
	# flat, opaque, procedurally-built mark) redesign what "the core" reads
	# as. Both wired here, in the same spot the other geometry passes set
	# their own new nodes up.
	_housing_material = ShaderMaterial.new()
	_housing_material.shader = GLASS_SHELL_SHADER
	_housing_material.render_priority = RENDER_PRIORITY_CORE_HOUSING
	_housing_material.set_shader_parameter("base_color", CORE_HOUSING_BASE_COLOR)
	_housing_material.set_shader_parameter("fresnel_power", CORE_HOUSING_FRESNEL_POWER)
	_housing_material.set_shader_parameter("rim_alpha", CORE_HOUSING_RIM_ALPHA)
	_housing_material.set_shader_parameter("core_alpha", CORE_HOUSING_CORE_ALPHA)
	_housing_material.set_shader_parameter("lens_distortion", CORE_HOUSING_LENS_DISTORTION)
	core_housing.set_surface_override_material(0, _housing_material)

	_emblem_material = StandardMaterial3D.new()
	_emblem_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_emblem_material.emission_enabled = true
	_emblem_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # same defensive choice as the arcs -- a flat mesh should stay visible even if something later gives it any rotation
	core_emblem.mesh = _build_emblem_mesh()
	core_emblem.position = Vector3(0.0, 0.0, EMBLEM_Z_OFFSET)
	core_emblem.set_surface_override_material(0, _emblem_material)

	# AmbientParticles previously drew with no material at all (its
	# SphereMesh_particle draw pass had no surface material assigned), so it
	# fell back to Godot's default lit material -- dim gray dots relying on
	# the scene's one weak OmniLight3D, not the bright glowing sparks the
	# rest of the orb uses. material_override replaces that for every
	# particle instance with the same emissive/unshaded material family as
	# the core/rings/arcs, tinted from _current_color each frame in _process().
	_particle_material = _make_translucent_material()
	_particle_material.render_priority = RENDER_PRIORITY_PARTICLES
	particles.material_override = _particle_material

	_ring_material_a = _make_translucent_material()
	_ring_material_a.render_priority = RENDER_PRIORITY_RING_A
	_build_ring_segments(ring_a, RING_A_SEGMENTS, RING_A_INNER_RADIUS, RING_A_OUTER_RADIUS, _ring_material_a, _ring_segments_a)
	ring_a.rotate_x(deg_to_rad(RING_TILT_DEG))

	_ring_material_b = _make_translucent_material()
	_ring_material_b.render_priority = RENDER_PRIORITY_RING_B
	_build_ring_segments(ring_b, RING_B_SEGMENTS, RING_B_INNER_RADIUS, RING_B_OUTER_RADIUS, _ring_material_b, _ring_segments_b)
	ring_b.rotate_x(deg_to_rad(RING_TILT_DEG))
	ring_b.rotate_z(deg_to_rad(RING_B_ROLL_DEG))

	_arc_material_a = ShaderMaterial.new()
	_arc_material_a.shader = ARC_SHADER
	_arc_material_a.render_priority = RENDER_PRIORITY_ARCS
	_arc_material_a.set_shader_parameter("ripple_cycles", ARC_RIPPLE_CYCLES)
	_arc_material_a.set_shader_parameter("alpha", ARC_ALPHA)
	arc_a.mesh = _build_arc_mesh(0.0)
	arc_a.set_surface_override_material(0, _arc_material_a)

	_arc_material_b = ShaderMaterial.new()
	_arc_material_b.shader = ARC_SHADER
	_arc_material_b.render_priority = RENDER_PRIORITY_ARCS
	_arc_material_b.set_shader_parameter("ripple_cycles", ARC_RIPPLE_CYCLES)
	_arc_material_b.set_shader_parameter("alpha", ARC_ALPHA)
	_arc_material_b.set_shader_parameter("time_offset", 3.3)  # phase offset so ArcA/ArcB never ripple in perfect unison, same spirit as the old flicker's phase-offset trick
	arc_b.mesh = _build_arc_mesh(3.3)  # different seed_offset -> a differently-jagged path than ArcA
	arc_b.set_surface_override_material(0, _arc_material_b)
	arc_b.rotate_y(deg_to_rad(120.0))  # offset so the two arcs don't start overlapping

	for i in range(plates.size()):
		var plate := plates[i]
		var config: Dictionary = PLATE_CONFIGS[i]
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

	for i in range(glass_shells.size()):
		var shell := glass_shells[i]
		var config: Dictionary = GLASS_SHELL_CONFIGS[i]
		shell.scale = config["scale"]
		shell.rotate_x(deg_to_rad(config["tilt_x_deg"]))
		shell.rotate_z(deg_to_rad(config["tilt_z_deg"]))

		var mat := ShaderMaterial.new()
		mat.shader = GLASS_SHELL_SHADER
		mat.render_priority = config["render_priority"]
		shell.set_surface_override_material(0, mat)
		_glass_materials.append(mat)

	print("[orb_controller] geometry ready: RingA segments=%d, RingB segments=%d, plates=%d, ArcA vertices=%d, ArcB vertices=%d, glass shells=%d, core housing + %d-point emblem vertices=%d" % [
		_ring_segments_a.size(), _ring_segments_b.size(), plates.size(),
		arc_a.mesh.surface_get_array_len(0), arc_b.mesh.surface_get_array_len(0), _glass_materials.size(),
		EMBLEM_POINTS, core_emblem.mesh.surface_get_array_len(0),
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

		# Pass B: UV.x tags each vertex with its position along the path
		# (0.0 at one end, 1.0 at the other), read by
		# orb_arc_ribbon.gdshader to drive a brightness wave that
		# genuinely travels along the ribbon's length -- both vertices at
		# this point share the same t, since they're a thickness pair, not
		# a step along the path.
		var t := float(i) / float(points.size() - 1)
		st.set_uv(Vector2(t, 0.0))
		st.add_vertex(points[i] - perp)
		st.set_uv(Vector2(t, 1.0))
		st.add_vertex(points[i] + perp)

	# No generate_normals() call: SurfaceTool only supports it for
	# PRIMITIVE_TRIANGLES, not the PRIMITIVE_TRIANGLE_STRIP used here
	# (confirmed by a real runtime error during testing, not assumed) --
	# and the arc material is unshaded, so normals are unused anyway.
	return st.commit()


## Builds the Jairus emblem as a flat, opaque, 4-point "sparkle" star (a
## triangle fan: one center vertex, EMBLEM_POINTS*2 rim vertices
## alternating between EMBLEM_OUTER_RADIUS tips and EMBLEM_INNER_RADIUS
## concave valleys) in the local XY plane -- SurfaceTool, no external
## asset, same reasoning as _build_arc_mesh() above for why a hand-built
## mesh was chosen over a shader or CSG. No existing Jairus brand mark was
## found anywhere in the repo (checked the Qt app's icon usage in
## theme.py, which only ever uses generic qtawesome/Font Awesome glyphs,
## and searched for any *.ico/*logo*/*emblem*/*brand* asset file -- none
## exist), so this is a clean, simple, unambiguous geometric mark rather
## than an attempt at a new logo design, per this pass's own scope.
func _build_emblem_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var center := Vector3.ZERO
	var rim_count := EMBLEM_POINTS * 2
	var rim: PackedVector3Array = []
	for i in range(rim_count):
		var angle := float(i) / float(rim_count) * TAU
		var r := EMBLEM_OUTER_RADIUS if i % 2 == 0 else EMBLEM_INNER_RADIUS
		rim.append(Vector3(cos(angle) * r, sin(angle) * r, 0.0))

	for i in range(rim_count):
		var a := rim[i]
		var b := rim[(i + 1) % rim_count]
		st.add_vertex(center)
		st.add_vertex(a)
		st.add_vertex(b)

	st.generate_normals()  # PRIMITIVE_TRIANGLES supports this (unlike _build_arc_mesh()'s strip) -- harmless since the material is unshaded anyway, but free and correct
	return st.commit()


## Builds one ring segment as a flat annulus-wedge ribbon (inner/outer
## radius alternating vertices along a triangle strip, span_deg wide),
## starting at local angle 0 -- the segment NODE itself is rotated by its
## own start_deg once in _build_ring_segments() below, the same pattern
## RING_TILT_DEG already uses for the whole ring. Same SurfaceTool
## technique as _build_arc_mesh(); see the RING_A_SEGMENTS comment for
## why inner/outer radius is used directly instead of a tangent-
## perpendicular offset.
func _build_ring_segment_mesh(inner_r: float, outer_r: float, span_deg: float) -> ArrayMesh:
	var span_rad := deg_to_rad(span_deg)
	var point_count: int = maxi(3, int(ceil(span_deg / RING_SEGMENT_DEGREES_PER_POINT)) + 1)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(point_count):
		var t := float(i) / float(point_count - 1)
		var angle := span_rad * t
		st.add_vertex(Vector3(cos(angle) * inner_r, sin(angle) * inner_r, 0.0))
		st.add_vertex(Vector3(cos(angle) * outer_r, sin(angle) * outer_r, 0.0))

	return st.commit()


## Builds every segment for one ring: one MeshInstance3D child per
## `configs` entry, sharing `mat` (the same single Material resource
## already shared across a whole ring before this pass -- still correct
## now that a ring is several nodes instead of one, since Godot lets any
## number of MeshInstance3Ds reference the same Material). Appends each
## created node to `out_segments` so _process() can spin them
## individually later in this pass.
func _build_ring_segments(parent: Node3D, configs: Array, inner_r: float, outer_r: float, mat: StandardMaterial3D, out_segments: Array[MeshInstance3D]) -> void:
	for config in configs:
		var seg := MeshInstance3D.new()
		seg.mesh = _build_ring_segment_mesh(inner_r, outer_r, config["span_deg"])
		seg.set_surface_override_material(0, mat)
		parent.add_child(seg)
		seg.rotate_z(deg_to_rad(config["start_deg"]))
		out_segments.append(seg)


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
	# CoreEmblem breathes with the glow (it's part of the same "energy"
	# reading) -- CoreHousing deliberately does NOT scale with the pulse at
	# all (stays Vector3.ONE, its .tscn default): per the design doc's own
	# material-contrast principle (glass/metal.md section 8), mechanical
	# components should read as "controlled" while energy components
	# "animate" -- a rigid, non-pulsing housing around a breathing glow is
	# exactly that contrast, not an oversight.
	core_emblem.scale = Vector3.ONE * pulse_scale

	var particle_baseline: float = profile["particle_amount"]
	if particles:
		particles.amount_ratio = clamp(particle_baseline + _level, 0.0, 1.0)
		particles.speed_scale = profile["particle_speed"]
	_particle_material.albedo_color = _current_color
	_particle_material.emission = _current_color
	_particle_material.emission_energy_multiplier = EMISSION_ENERGY

	var glow_intensity: float = profile["glow_intensity"]
	var glow_strength: float = profile["glow_strength"]
	var core_intensity: float = profile.get("core_intensity", 1.0)
	var glow_emission := CORE_GLOW_EMISSION_ENERGY * core_intensity
	var emblem_emission := CORE_EMBLEM_EMISSION_ENERGY * core_intensity

	if _pop_remaining > 0.0:
		_pop_remaining = max(0.0, _pop_remaining - delta)
		var pop_factor := _pop_remaining / POP_DURATION_SECONDS  # 1.0 the instant it starts, linearly down to 0.0
		glow_intensity += POP_GLOW_BOOST * pop_factor
		glow_emission += POP_EMISSION_BOOST * pop_factor
		emblem_emission += POP_EMISSION_BOOST * pop_factor

	if _environment:
		_environment.glow_intensity = glow_intensity
		_environment.glow_strength = glow_strength
	_material.emission_energy_multiplier = glow_emission

	var emblem_color := _current_color.lerp(Color.WHITE, CORE_EMBLEM_BRIGHTEN)
	_emblem_material.albedo_color = emblem_color
	_emblem_material.emission = emblem_color
	_emblem_material.emission_energy_multiplier = emblem_emission

	_update_rings(delta, profile)
	_update_arcs(delta, profile)
	_update_glass_shells(profile)
	_update_core_housing()
	_update_plates(delta, profile)

	activity_label.add_theme_color_override("font_color", _current_color.lerp(Color.WHITE, ACTIVITY_TEXT_BRIGHTEN))


func _update_rings(delta: float, profile: Dictionary) -> void:
	var ring_speed: float = profile["ring_speed"]
	var ring_opacity: float = profile["ring_opacity"]
	var segment_spread: float = profile.get("segment_spread", 0.0)

	ring_a.rotate_z(ring_speed * delta)
	ring_b.rotate_z(ring_speed * RING_B_SPEED_FACTOR * delta)
	_spin_ring_segments(_ring_segments_a, RING_A_SEGMENTS, ring_speed, segment_spread, delta)
	_spin_ring_segments(_ring_segments_b, RING_B_SEGMENTS, ring_speed * RING_B_SPEED_FACTOR, segment_spread, delta)

	var ring_color := Color(_current_color.r, _current_color.g, _current_color.b, ring_opacity)
	for mat in [_ring_material_a, _ring_material_b]:
		mat.albedo_color = ring_color
		mat.emission = _current_color
		mat.emission_energy_multiplier = EMISSION_ENERGY * 0.6


## Pass B stage 2: each segment already inherits the ring's shared
## base_speed rotation from its parent Node3D (ring_a/ring_b, rotated in
## _update_rings() above) -- this adds each segment's own EXTRA rotation
## on top, scaled by (its structural speed_factor - 1.0) so that at
## segment_spread=0 every segment still moves in perfect lockstep with
## the shared rate (identical to stage 1's behavior, and to the pre-Pass-B
## single-torus rings), and as segment_spread rises toward 1.0 a
## segment's total rate approaches base_speed*speed_factor -- its own,
## genuinely independent rotation. This is why speed_factor lives on each
## segment (a per-segment property) while segment_spread lives in
## STATE_PROFILES (a per-state property): the design doc asks for both
## "independently rotating sections" (structural) and per-state motion
## (behavioral), and this keeps them as two separate, separately-tunable
## numbers rather than conflating them.
func _spin_ring_segments(segments: Array[MeshInstance3D], configs: Array, base_speed: float, segment_spread: float, delta: float) -> void:
	for i in range(segments.size()):
		var speed_factor: float = configs[i]["speed_factor"]
		var extra := base_speed * (speed_factor - 1.0) * segment_spread
		segments[i].rotate_z(extra * delta)


## Pass B (energy ribbons take 2): arc_frequency is repurposed from "how
## often does the whole ribbon flash on" to "how fast does the brightness
## wave travel along the ribbon" -- both arcs stay visible at all times
## now (no more .visible toggling); orb_arc_ribbon.gdshader's own
## continuous wave, never reaching true zero brightness, is what replaces
## the old binary on/off read. arc_turbulence is new this pass (how deep
## the wave dips -- see the shader's own comment).
func _update_arcs(delta: float, profile: Dictionary) -> void:
	var flow_speed: float = profile["arc_frequency"]
	var turbulence: float = profile.get("arc_turbulence", 0.3)
	var intensity: float = profile["arc_intensity"]

	arc_a.rotate_y(ARC_ROTATION_SPEED * delta)
	arc_b.rotate_y(-ARC_ROTATION_SPEED * 0.8 * delta)

	for mat in [_arc_material_a, _arc_material_b]:
		mat.set_shader_parameter("base_color", _current_color)
		mat.set_shader_parameter("emission_energy", ARC_EMISSION_ENERGY * intensity)
		mat.set_shader_parameter("flow_speed", flow_speed)
		mat.set_shader_parameter("turbulence", turbulence)


## STAGE 2 of the full Fresnel glass pass: same-scene lensing now enabled
## (lens_distortion driven from STATE_PROFILES' glass_lens_strength),
## on top of the Fresnel rim layering verified alone in stage 1's real
## screenshots. See orb_glass_shell.gdshader's own comment for exactly
## what this can and can't warp (the core and empty/desktop background --
## never the rings/particles/other shells, which are transparent and not
## yet drawn when the single per-frame screen copy is taken).
func _update_glass_shells(profile: Dictionary) -> void:
	var rim_intensity: float = profile["glass_rim_intensity"]
	var lens_strength: float = profile["glass_lens_strength"]
	for i in range(_glass_materials.size()):
		var config: Dictionary = GLASS_SHELL_CONFIGS[i]
		var mat := _glass_materials[i]
		mat.set_shader_parameter("base_color", (_current_color + config["tint"]).clamp())
		mat.set_shader_parameter("fresnel_power", GLASS_BASE_FRESNEL_POWER + config["power_offset"])
		mat.set_shader_parameter("rim_alpha", clamp(GLASS_BASE_RIM_ALPHA + config["rim_offset"], 0.0, 1.0) * rim_intensity)
		mat.set_shader_parameter("core_alpha", GLASS_CORE_ALPHA)
		mat.set_shader_parameter("lens_distortion", GLASS_LENS_DISTORTION_BASE * lens_strength)


## CoreHousing's base_color gets only a faint tint of _current_color (15%)
## on top of its fixed dark base -- enough for the "controlled highlights"
## the design doc asks of mechanical components (the housing visibly
## belongs to the current state's color story) without turning it into
## another bright emissive layer (EMISSION in orb_glass_shell.gdshader is
## derived directly from base_color, so keeping base_color mostly dark
## keeps emission mostly dark too). No STATE_PROFILES field needed for
## this -- it rides on the same _current_color every other element
## already reacts to.
func _update_core_housing() -> void:
	var tinted := CORE_HOUSING_BASE_COLOR.lerp(_current_color, 0.15)
	_housing_material.set_shader_parameter("base_color", tinted)


## Plates get NO color/emission update here, deliberately -- unlike every
## other element in the scene, they never tint toward _current_color.
## That's the point: a genuinely neutral dark metal that doesn't
## participate in the energy color story is what makes it read as "the
## machine's housing" rather than "more energy," per section 8's material
## contrast. Only their rotation reacts to state, via plate_activity
## (rotate_object_local so each plate spins around its OWN local Y axis,
## which differs per plate since each already has a different structural
## rotation_deg -- so even a shared spin *rate* still looks different per
## plate on screen, without needing a second per-plate speed constant).
func _update_plates(delta: float, profile: Dictionary) -> void:
	var activity: float = profile.get("plate_activity", 0.3)
	for i in range(plates.size()):
		var per_plate_rate := PLATE_SPIN_SPEED * (0.7 + 0.3 * float(i))  # mild per-plate variety, deterministic, same spirit as the arcs' seed_offset
		plates[i].rotate_object_local(Vector3.UP, per_plate_rate * activity * delta)


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
		# Pass A hierarchy check, logged every state entry so it's directly
		# verifiable from the console/OS log rather than only asserted in a
		# comment: core_glow/core_emblem must both exceed arc_peak in every
		# line this ever prints.
		var core_intensity: float = profile.get("core_intensity", 1.0)
		var core_glow_emission := CORE_GLOW_EMISSION_ENERGY * core_intensity
		var core_emblem_emission := CORE_EMBLEM_EMISSION_ENERGY * core_intensity
		var arc_peak_emission := ARC_EMISSION_ENERGY * float(profile["arc_intensity"])
		print("[orb_controller] Pass A emission hierarchy for '%s' -> core_glow=%.2f core_emblem=%.2f arc_peak=%.2f (core_intensity=%.2f) -- core_wins=%s" % [
			new_state, core_glow_emission, core_emblem_emission, arc_peak_emission, core_intensity,
			core_glow_emission > arc_peak_emission and core_emblem_emission > arc_peak_emission,
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
