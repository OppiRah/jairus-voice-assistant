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
##
## Pass E (particle roles) -- adds CoreSparks and OrbitalParticles, two new
## GPUParticles3D nodes alongside the untouched AmbientParticles (which now
## explicitly serves design-doc section 9's "ambient" role). See the
## comment above EMBLEM_Z_OFFSET's constants block for the full reasoning,
## including why "energy particles" riding the arcs are deliberately not a
## third new role this pass (Pass B's own ribbon-particle decision, carried
## forward unchanged).

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

# RingA's tilt (TorusMesh's default face-normal is the local Z axis, which
# starts pointed straight at Camera3D) -- confirmed via a real rendered
# screenshot that this distance from 0 controls how edge-on a ring reads:
# 55 degrees around X reads as a clear, well-foreshortened ellipse. Also
# reused verbatim by OrbitalParticles below (unchanged from before this
# pass) so its emission plane keeps matching RingA's specifically.
const RING_TILT_DEG := 55.0  # tilt around X, RingA only as of the V2-1 structural pass

# V2-1 structural re-architecture (ORB_V2_DESIGN.md Q3): V1 gave RingB the
# SAME X tilt as RingA plus only an in-plane Z roll -- a roll re-orients an
# already-identically-shaped ellipse within the image plane but can't change
# its eccentricity, so two same-eccentricity ellipses at different radii
# (RingB's 1.55-1.7 band is strictly larger than RingA's 1.3-1.45) generally
# nest rather than cross, regardless of roll -- confirmed by this pass's own
# stage-1 screenshot check (see report) that the old scheme in fact never
# produced a real crossing. RingB now gets a genuinely independent tilt
# AXIS combination -- a smaller X component (less foreshortened, closer to
# face-on) PLUS an added Y-axis component (reorienting the ellipse's major
# axis in 3D, not just rolling it in-plane) -- specifically chosen so its
# projected path crosses RingA's rather than concentrically containing it.
const RING_B_TILT_X_DEG := 25.0
const RING_B_TILT_Y_DEG := 50.0

# Pass B -- segmented ring geometry (per ORB_CONCEPT_GAP_ANALYSIS.md's
# structure gap and design-doc section 5: "Do not simply keep adding
# complete torus rings"). RingA/RingB are no longer single TorusMesh
# nodes; each is now a Node3D container (each receiving its own tilt
# transform -- see RING_TILT_DEG/RING_B_TILT_X_DEG/RING_B_TILT_Y_DEG's own
# comments; V2-1 gave the two containers genuinely independent tilt axes,
# no longer sharing one tilt) holding several flat ribbon segments with
# real angular gaps between them,
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
# Material fix (ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md problem 2, variant
# C -- the investigation's strongest result of the five tested): Godot's
# built-in StandardMaterial3D rim feature added on top of the existing real-
# lit metal recipe. No new shader, stays fully opaque (no transparency-
# sorting risk) -- adds a glassy edge highlight without touching the dark
# base color.
#
# Tuning pass (real screenshot confirmed the first landing -- rim=0.65,
# rim_tint=0.35, metallic=0.65, roughness=0.35 -- read as predominantly
# flat/dark, not convincing crystal): three things were investigated, not
# just one number pushed blindly.
#   1. Rim alone, pushed hard (0.65->0.95, tint 0.35->0.15 so the rim skews
#      toward the light color instead of the dark albedo -- rim_tint=1 means
#      "tint toward albedo," which is the WRONG direction on a near-black
#      base): confirmed via same-angle/state screenshot to visibly brighten
#      the facet edges. Real improvement, but alone left the shadowed facets
#      still fairly flat.
#   2. Metallic/roughness were investigated as a possible SECOND factor, not
#      assumed: at metallic=1 a dark albedo drives both diffuse AND specular
#      toward black (energy conservation uses albedo as F0), so pushing
#      metallic UP on this near-black color actively works against facet
#      definition rather than helping it. Lowering metallic (0.65->0.5,
#      restoring some diffuse fill) and lowering roughness (0.35->0.2,
#      sharpening the specular response) together measurably increased
#      facet-to-facet CONTRAST in a same-angle zoomed comparison (the
#      shadowed facet got darker, the lit facet stayed bright, instead of
#      both blurring toward the same mid-gray).
#   3. Facet SCALE was also checked, since no material tuning can fix a
#      geometry-too-small-to-read problem: at the plates' actual on-screen
#      size (~40x50px at the real 480x480 window), each facet is only
#      roughly 15-20px wide -- small, but a real screenshot crop confirmed
#      genuine facet-to-facet brightness bands are still visible at that
#      size, not just at a favorable zoomed-in crop. So facet count/size was
#      NOT the limiting factor this pass -- rim strength and metallic/
#      roughness were -- but it's close enough to the perceptibility floor
#      that it remains a real ceiling on how much further material-only
#      tuning can push this before geometry would need revisiting.
const PLATE_METALLIC := 0.5
const PLATE_ROUGHNESS := 0.2
const PLATE_RIM := 0.95
const PLATE_RIM_TINT := 0.15
const PLATE_SPIN_SPEED := 0.12  # rad/s at plate_activity=1.0 -- slow and heavy-feeling, not energetic like the rings/arcs

# Geometry fix (ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md problem 2): each
# plate's flat BoxMesh is replaced with _build_crystal_shard() (bipyramid,
# same technique validated in facet_poc_test.gd) sized from that plate's own
# `size` -- equator_radius/half_height set to half of size.x/size.y so the
# crystal's bounding footprint stays comparable to the original box's width/
# height (this also shrinks worst-case center-to-vertex reach vs. the old
# box's half-diagonal, since a bipyramid's max reach is orientation-
# independent -- helps stage 1's containment margin rather than reopening
# it).
#
# Facet-scale pass: CRYSTAL_SIDES was originally 6 (hexagonal bipyramid, 12
# facets total), matching facet_poc_test.gd's own PoC value -- but at the
# plates' real on-screen size (~40x50px), that put each facet at only
# ~15-20px, confirmed via real screenshot (both mine and the person's
# independent judgment) to sit right at the perceptibility floor: the
# material tuning was independently confirmed correct, yet plates still
# read as predominantly flat/dark. Since worst-case center-to-vertex reach
# is exactly max(equator_radius, half_height) regardless of `sides` --
# every equator vertex sits on the same circle whether there are 3 of them
# or 6 -- dropping CRYSTAL_SIDES has NO effect on stage 1's containment
# margin; it only changes how the same footprint is subdivided. Dropped to
# 3 (triangular bipyramid, 6 facets total, each roughly 2x the angular
# width of the hexagonal version) -- the minimum for a real polygon, and
# the most aggressive facet-enlarging move available without growing the
# plate itself.
const CRYSTAL_SIDES := 3
# V2-1 structural re-architecture (ORB_V2_DESIGN.md Q3): every prior pass
# parameterized each plate's angle_deg/radius/height relative only to the
# shared scene origin -- never relative to any OTHER structural element --
# which is exactly why the assembly kept reading as "independent orbits
# sharing a center" no matter how segmented/angular any individual piece
# became. Plate1/Plate3 are now children of RingA and Plate2 a child of
# RingB (orb_scene.tscn), so angle_deg/radius/height below are no longer
# world-space -- they're LOCAL to that ring's own pre-tilt plane, exactly
# the same convention _build_ring_segment_mesh() already uses for the ring
# segments themselves (local XY plane, radius measured from the ring's own
# center) -- so a plate positioned at a segment's own start_deg/span_deg
# angle sits AT that segment's real endpoint angle, not at an
# independently-guessed angle that merely happens to share the same origin.
#
# V2-1 strengthening pass: radius was originally pulled inward from the
# ring's own inner_r by ~0.6x each plate's half_height, on the assumption
# that the shard's half_height axis (its longest reach, pre-rotation) would
# point radially outward toward the ring band. It doesn't -- each plate's
# rotation_deg below was hand-chosen for crystal-facet appearance in an
# earlier material-tuning pass, not for radial alignment, so that reach axis
# actually points in an arbitrary 3D direction. A same-angle zoomed
# real-screenshot check (this pass's own diagnosis) confirmed the result:
# only a single vertex/corner grazed the ring's inner edge in both visible
# cases, with the shard's actual bulk sitting inward of the band entirely --
# real (provable via debug-color pixel inspection) but not visually
# obvious. Fixed by placing radius at the anchor ring's own BAND MIDPOINT
# ((inner_r + outer_r) / 2) instead of pulled inward past inner_r: centered
# inside the band, the plate's center is already within the ring regardless
# of which way rotation_deg happens to point its longest axis, guaranteeing
# a real, substantial crossing rather than a chance graze. Reparenting also
# means each plate now automatically inherits its ring's own rotate_z()
# spin every frame (_update_rings()) on top of its pre-existing independent
# local spin (_update_plates(), unchanged) -- it moves WITH its anchor
# ring, which is what "anchored" has to mean once the ring itself moves.
# size/rotation_deg/CRYSTAL_SIDES/material are all UNCHANGED from the prior
# pass -- only radius (per the strengthening-pass comment above) and,
# before that, angle_deg/radius/height and the scene-tree parent changed.
const PLATE_CONFIGS := [
	{
		# Anchored to RingA segment 0's far endpoint (start_deg=40 +
		# span_deg=70 = 110 degrees). Radius 1.375 = RingA's own band
		# midpoint ((1.3 + 1.45) / 2), not RING_A_INNER_RADIUS itself -- see
		# the strengthening-pass comment above. Local height is a small
		# offset along the ring's own local Z (perpendicular to its tilted
		# plane), giving this plate a touch of independent depth within its
		# anchor ring rather than sitting flush in-plane.
		"angle_deg": 110.0, "radius": 1.375, "height": 0.15,
		"size": Vector3(0.55, 0.85, 0.035), "rotation_deg": Vector3(20.0, 10.0, 55.0),
	},
	{
		# Anchored to RingB segment 1's far endpoint (start_deg=220 +
		# span_deg=60 = 280 degrees). Radius 1.625 = RingB's own band
		# midpoint ((1.55 + 1.7) / 2).
		"angle_deg": 280.0, "radius": 1.625, "height": -0.1,
		"size": Vector3(0.4, 0.6, 0.03), "rotation_deg": Vector3(-15.0, 70.0, 10.0),
	},
	{
		# Anchored to RingA segment 2's near endpoint (start_deg=220) -- a
		# different segment from Plate1's anchor, and the opposite (near, not
		# far) end of it, so all three plates anchor to visibly distinct
		# points, not a repeated pattern. Radius 1.375 = RingA's own band
		# midpoint, same reasoning as Plate1 above. The old angle_deg=200.0/
		# radius=1.1 (and the whole prior camera-occlusion/containment
		# history at this entry) was a world-space value from before this
		# plate had any anchor relationship at all; it's superseded, not
		# extended, by this pass's anchor-derived local placement.
		"angle_deg": 220.0, "radius": 1.375, "height": 0.05,
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

const WISP_SHADER := preload("res://orb_energy_wisp.gdshader")

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
const RENDER_PRIORITY_CORE_SPARKS := -7  # emitted right at CoreHousing's 0.64 boundary (0.68 emission radius) -- between the housing and the arcs (0.75), same "innermost first" ordering
const RENDER_PRIORITY_ARCS := -6
const RENDER_PRIORITY_PARTICLES := -2
const RENDER_PRIORITY_RING_A := 0
const RENDER_PRIORITY_ORBITAL := 0  # emission_ring_radius 1.5 sits between RingA's 1.3-1.45 band and RingB's 1.55-1.7 band -- same approximate-priority caveat as RENDER_PRIORITY_PARTICLES above, since orbiting particles don't hold a single exact radius either
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

# Pass E -- two new particle roles (design-doc section 9: "core sparks" and
# "orbital particles" are distinct behavioral roles, not more ambient
# density). AmbientParticles itself is untouched and now explicitly serves
# section 9's "ambient" role. "Energy particles" (riding the arcs) are
# deliberately NOT added this pass -- Pass B's own report investigated
# ribbon-riding particles and concluded the arc shader's traveling-
# brightness wave already covers that need, and the person has since
# confirmed Pass B "feels as intended, no follow-up needed." That decision
# is carried forward here, not re-litigated.
#
# CoreSparks: emitted from a small sphere shell just outside CoreHousing's
# own 0.64 radius (see SphereMesh_core_housing in orb_scene.tscn), with
# real velocity (0.9-1.6, vs. AmbientParticles' 0.05-0.2) and a short
# lifetime (0.45s) so they read as "spitting off the energy source" and
# fade before reaching the rings' 1.3+ band -- never floating debris.
# Structural placement/velocity/lifetime live in orb_scene.tscn's
# ParticleProcessMaterial_core_sparks (a one-time setup, same as
# AmbientParticles' own process material); only rate/speed/size react to
# state, via the per-state fields below and _core_spark_process_material's
# scale_min/scale_max (mutated at runtime, same "structural constant +
# per-state multiplier" split already used for the glass shells/plates).
const CORE_SPARK_SCALE_MIN := 0.6  # matches ParticleProcessMaterial_core_sparks' own baseline -- kept here too since state's core_spark_size multiplies it at runtime
const CORE_SPARK_SCALE_MAX := 1.3
const CORE_SPARK_EMISSION_ENERGY := 5.0  # brighter than a single ambient mote (EMISSION_ENERGY=3.5) since sparks are meant to read as "energy," but well under the core's own CORE_GLOW_EMISSION_ENERGY=6.0 -- never competing with the actual core for the hierarchy's top spot
const CORE_SPARK_BRIGHTEN := 0.6  # lerp weight toward Color.WHITE, same legibility technique as the emblem/activity label -- keeps sparks reading as sharp bright motes rather than same-hue-as-everything-else glow

# OrbitalParticles: emission_ring_radius 1.5 (orb_scene.tscn's
# ParticleProcessMaterial_orbital) sits between RingA's 1.3-1.45 band and
# RingB's 1.55-1.7 band -- close enough to read as riding along with the
# rings, not a separate unrelated layer. The node is tilted by the same
# RING_TILT_DEG as RingA/RingB in _ready() (not hand-duplicated math) so
# its ring-shaped emission plane matches the rings' own plane; Godot's
# orbit_velocity rotates particles around the emitting node's own local Z
# axis, and emission_ring_axis is already set to that same local Z in the
# .tscn resource, so the tilt carries both into alignment together.
# orbit_velocity_min/max (0.06-0.09 full rotations/sec structurally) is
# deliberately slow at baseline -- orbital_speed below scales it per state,
# same "structural baseline + per-state multiplier" split as everywhere
# else in this file.
const ORBITAL_SCALE_MIN := 0.7
const ORBITAL_SCALE_MAX := 1.2
const ORBITAL_EMISSION_ENERGY := 3.0  # dimmer than a core spark, closer to a ring's own emission (EMISSION_ENERGY*0.6=2.1) -- orbital particles are meant to read as riding along with the rings, not out-competing them

# Pass F -- billboard energy wisps (ORB_VFX_TECHNIQUE_ANALYSIS.md's
# recommended next step: billboard VFX + energy wisps/mist were the one
# genuinely-missing technique category, validated end-to-end by
# vfx_technique_poc_test.gd before this pass). Godot 4 spatial shaders have
# no built-in billboard render mode -- orb_energy_wisp.gdshader reuses the
# PoC's manual vertex() override VERBATIM (rebuilds MODELVIEW_MATRIX from
# INV_VIEW_MATRIX, the same trick StandardMaterial3D.billboard_mode wraps
# internally), not a re-derived approach. Per JAIRUS_ORB_VFX_TECHNIQUE_
# REFERENCE.md section 5's explicit constraint, wisps must read as
# electromagnetic field/plasma/holographic energy, NOT smoke/fire/magical
# fog -- the PoC's specific finding was that radial falloff (soft, no image
# asset, no hard sprite edge) PLUS noise-driven irregularity together (not
# either alone) is what produces that read rather than a plain glow dot.
#
# Three wisps, deliberately positioned (design doc's own "controlled
# asymmetry" -- not evenly spaced, same discipline as PLATE_CONFIGS/
# RING_A_SEGMENTS), straddling RingA/RingB's own 1.3-1.7 band, bridging
# outward past it into the darker exterior -- not randomly floating, per the
# reference doc's explicit distinction. Radius placement was tuned by real
# screenshot, not guessed: an initial placement closer to CoreHousing
# (radius ~0.8-1.35) rendered with genuinely bright pixels (confirmed via
# unproject_position + direct pixel sampling) but was visually swallowed by
# the already-bright core/inner-ring bloom -- an additive glow needs a
# comparatively DARK local background to read as a distinct shape, which the
# region just past the ring band actually has. Each wisp orbits the core at
# its own fixed radius/height (own base_speed, own direction/rate) so it
# reads as energy actually moving around the physical artifact, not a static
# decal; per-state wisp_speed (STATE_PROFILES) scales this same orbit on top
# of each wisp's own structural base_speed -- identical "structural constant
# + per-state multiplier" split already used everywhere else in this file
# (segments, glass shells, particles).
const WISP_CONFIGS := [
	{"angle_deg": 90.0, "radius": 1.6, "height": 0.4, "quad_size": 0.7, "base_speed": 0.22, "render_priority": 1},
	{"angle_deg": 245.0, "radius": 1.85, "height": -0.2, "quad_size": 0.9, "base_speed": -0.15, "render_priority": 2},
	{"angle_deg": 330.0, "radius": 1.45, "height": -0.5, "quad_size": 0.6, "base_speed": 0.3, "render_priority": 1},
]
const WISP_SOFTNESS := 0.35  # lower than the PoC's 0.5 -- a fully soft/gaussian falloff reads as haze; a tighter edge (combined with the smoothstep-sharpened noise below) keeps the shape reading as a torn energy patch instead
const WISP_NOISE_SPEED_BASE := 0.35  # noise scroll rate at wisp_speed=1.0 -- see orb_energy_wisp.gdshader's noise_speed uniform
# NOT the PoC's frequency=0.15, verbatim -- retuned after real screenshots
# showed why it doesn't transfer to this production scale. At frequency=0.15
# and 6.0 both (tested directly, not guessed): a raw pixel scanline through
# a rendered wisp came back a perfectly smooth, monotonic falloff -- zero
# irregularity, not merely blur-softened. Dumping the actual baked
# NoiseTexture2D to disk explained both failures directly: frequency=6.0
# baked pure single-pixel TV-static (no spatial coherence at all -- averages
# to flat gray under any minification/bloom blur, same "too high" failure
# ORB_VFX_TECHNIQUE_ANALYSIS.md already documented for the core noise
# variant); frequency=0.15 baked a finer mottled texture with real
# structure, but at only ~5-10px per blob on a 256px texture, those blobs
# collapse to a handful of screen pixels once mapped onto our ~80px-wide
# wisp quad -- too fine to survive minification + additive bloom's blur
# kernel. frequency=0.03, confirmed by the same dump-to-disk method, bakes
# large, soft, coherent blobs (~30-50px each) that are actually big enough,
# relative to THIS quad's on-screen footprint, to read as genuine shape
# irregularity rather than smoothing away to a uniform gray. Same technique,
# retuned for a much smaller on-screen object than the PoC's isolated,
# unobstructed test quad.
const WISP_NOISE_FREQUENCY := 0.03
const WISP_EMISSION_ENERGY := 1.8  # baseline HDR multiplier, times wisp_intensity per state -- kept well under CORE_GLOW_EMISSION_ENERGY (6.0) in every state, checked in the existing Pass A emission-hierarchy print (see _handle_message())

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
#
# Pass E adds core_spark_rate/speed/size and orbital_rate/speed/size --
# core sparks generally track plate_activity/arc_intensity's own per-state
# shape (calm at idle/offline, peaking at error, since both are meant to
# read as "the energy source getting more agitated"); orbital_speed
# generally tracks ring_speed's own shape (the orbital particles are meant
# to read as riding along with the rings, so their speed story should
# match, not diverge from, the rings' own).
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
		"core_spark_rate": 0.25, "core_spark_speed": 1.0, "core_spark_size": 1.0,
		"orbital_rate": 0.3, "orbital_speed": 1.0, "orbital_size": 1.0,
		"wisp_intensity": 0.5, "wisp_speed": 0.4, "wisp_opacity": 0.5,
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
		"core_spark_rate": 0.3, "core_spark_speed": 1.05, "core_spark_size": 1.0,
		"orbital_rate": 0.35, "orbital_speed": 1.15, "orbital_size": 1.0,
		"wisp_intensity": 0.6, "wisp_speed": 0.5, "wisp_opacity": 0.55,
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
		"core_spark_rate": 0.5, "core_spark_speed": 1.4, "core_spark_size": 1.05,
		"orbital_rate": 0.5, "orbital_speed": 1.8, "orbital_size": 1.05,
		"wisp_intensity": 0.9, "wisp_speed": 1.1, "wisp_opacity": 0.8,
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
		"core_spark_rate": 0.35, "core_spark_speed": 1.15, "core_spark_size": 1.0,
		"orbital_rate": 0.35, "orbital_speed": 1.2, "orbital_size": 1.0,
		"wisp_intensity": 0.7, "wisp_speed": 0.6, "wisp_opacity": 0.65,
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
		"core_spark_rate": 0.65, "core_spark_speed": 1.6, "core_spark_size": 1.1,
		"orbital_rate": 0.55, "orbital_speed": 1.6, "orbital_size": 1.05,
		"wisp_intensity": 1.0, "wisp_speed": 1.3, "wisp_opacity": 0.85,
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
		"core_spark_rate": 0.5, "core_spark_speed": 1.0, "core_spark_size": 1.1,
		"orbital_rate": 0.4, "orbital_speed": 1.1, "orbital_size": 1.0,
		"wisp_intensity": 0.6, "wisp_speed": 0.5, "wisp_opacity": 0.6,
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
		"core_spark_rate": 0.85, "core_spark_speed": 2.0, "core_spark_size": 1.15,
		"orbital_rate": 0.6, "orbital_speed": 2.2, "orbital_size": 1.1,
		# "Controlled disruption," not "brightest wisps": error's rings/arcs/
		# sparks are already the scene's peak brightness -- wisp_speed is
		# pushed the hardest of any state (erratic, fast-moving orbit +
		# noise scroll) so the DISRUPTION reads through motion, while
		# wisp_intensity/opacity stay a notch under executing's so wisps
		# don't pile onto an already-maximal bloom state.
		"wisp_intensity": 0.9, "wisp_speed": 1.8, "wisp_opacity": 0.75,
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
		"core_spark_rate": 0.03, "core_spark_speed": 0.2, "core_spark_size": 0.8,
		"orbital_rate": 0.05, "orbital_speed": 0.1, "orbital_size": 0.8,
		"wisp_intensity": 0.1, "wisp_speed": 0.1, "wisp_opacity": 0.15,
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
		"core_spark_rate": 0.35, "core_spark_speed": 1.0, "core_spark_size": 1.0,
		"orbital_rate": 0.3, "orbital_speed": 0.9, "orbital_size": 1.0,
		"wisp_intensity": 0.55, "wisp_speed": 0.45, "wisp_opacity": 0.55,
	},
}

@onready var core: MeshInstance3D = $Core
@onready var particles: GPUParticles3D = $AmbientParticles
@onready var core_sparks: GPUParticles3D = $CoreSparks
@onready var orbital_particles: GPUParticles3D = $OrbitalParticles
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var ring_a: Node3D = $RingA  # Pass B: container for segments, not a single mesh anymore -- see RING_A_SEGMENTS
@onready var ring_b: Node3D = $RingB
@onready var arc_a: MeshInstance3D = $ArcA
@onready var arc_b: MeshInstance3D = $ArcB
@onready var activity_label: Label = $UI/ActivityLabel
@onready var glass_shells: Array[MeshInstance3D] = [$GlassShell1, $GlassShell2, $GlassShell3, $GlassShell4]
@onready var core_housing: MeshInstance3D = $CoreHousing
@onready var core_emblem: MeshInstance3D = $CoreEmblem
@onready var plates: Array[MeshInstance3D] = [$RingA/Plate1, $RingB/Plate2, $RingA/Plate3]
@onready var wisps: Array[MeshInstance3D] = [$Wisp1, $Wisp2, $Wisp3]

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
var _core_spark_material: StandardMaterial3D
var _core_spark_process_material: ParticleProcessMaterial
var _orbital_material: StandardMaterial3D
var _orbital_process_material: ParticleProcessMaterial
var _wisp_materials: Array[ShaderMaterial] = []
var _wisp_angles: Array[float] = []  # accumulated orbit angle (radians) per wisp, updated each frame in _update_wisps()


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

	# Pass E -- CoreSparks and OrbitalParticles, section 9's two most
	# concrete particle roles (see this pass's own comment above
	# EMBLEM_Z_OFFSET for why "energy particles" riding the arcs are
	# deliberately not a third new role here). Both reuse the exact
	# material_override pattern AmbientParticles already established above
	# -- same emissive/unshaded material family, just two more instances --
	# and each keeps its own ParticleProcessMaterial reference so state can
	# mutate scale_min/scale_max at runtime (orb_scene.tscn only sets their
	# structural baseline once).
	_core_spark_material = _make_translucent_material()
	_core_spark_material.render_priority = RENDER_PRIORITY_CORE_SPARKS
	core_sparks.material_override = _core_spark_material
	_core_spark_process_material = core_sparks.process_material as ParticleProcessMaterial

	_orbital_material = _make_translucent_material()
	_orbital_material.render_priority = RENDER_PRIORITY_ORBITAL
	orbital_particles.material_override = _orbital_material
	_orbital_process_material = orbital_particles.process_material as ParticleProcessMaterial
	# Tilts the orbital ring-emission plane (local XY, per
	# ParticleProcessMaterial_orbital's emission_ring_axis) to match
	# RingA/RingB's own plane -- same RING_TILT_DEG reused, not a new
	# hand-picked angle. orbit_velocity rotates around the node's own local
	# Z axis, which this tilt carries along with the emission plane.
	orbital_particles.rotate_x(deg_to_rad(RING_TILT_DEG))

	_ring_material_a = _make_translucent_material()
	_ring_material_a.render_priority = RENDER_PRIORITY_RING_A
	_build_ring_segments(ring_a, RING_A_SEGMENTS, RING_A_INNER_RADIUS, RING_A_OUTER_RADIUS, _ring_material_a, _ring_segments_a)
	ring_a.rotate_x(deg_to_rad(RING_TILT_DEG))

	_ring_material_b = _make_translucent_material()
	_ring_material_b.render_priority = RENDER_PRIORITY_RING_B
	_build_ring_segments(ring_b, RING_B_SEGMENTS, RING_B_INNER_RADIUS, RING_B_OUTER_RADIUS, _ring_material_b, _ring_segments_b)
	ring_b.rotate_x(deg_to_rad(RING_B_TILT_X_DEG))
	ring_b.rotate_y(deg_to_rad(RING_B_TILT_Y_DEG))

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
		var plate_size: Vector3 = config["size"]
		plate.mesh = _build_crystal_shard(plate_size.x * 0.5, plate_size.y * 0.5, CRYSTAL_SIDES)

		var angle: float = deg_to_rad(config["angle_deg"])
		var radius: float = config["radius"]
		# V2-1: position in the PARENT RING's own local-XY-plane convention
		# (matching _build_ring_segment_mesh()'s Vector3(cos*r, sin*r, 0.0)
		# exactly) now that each plate is a child of RingA/RingB, not the
		# old world-space Vector3(cos*r, height, sin*r) convention (X/Z
		# orbit plane, Y as world "up") the pre-anchoring version used. Using
		# the old convention here would have positioned each plate out of
		# the ring's own plane entirely, undoing the anchoring this pass
		# exists to build -- caught before trusting a screenshot, not after.
		plate.position = Vector3(cos(angle) * radius, sin(angle) * radius, config["height"])
		var rot: Vector3 = config["rotation_deg"]
		plate.rotate_x(deg_to_rad(rot.x))
		plate.rotate_y(deg_to_rad(rot.y))
		plate.rotate_z(deg_to_rad(rot.z))

		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = PLATE_BASE_COLOR
		plate_mat.metallic = PLATE_METALLIC
		plate_mat.roughness = PLATE_ROUGHNESS
		plate_mat.rim_enabled = true
		plate_mat.rim = PLATE_RIM
		plate_mat.rim_tint = PLATE_RIM_TINT
		plate.set_surface_override_material(0, plate_mat)

	# Pass F -- billboard energy wisps. Each gets its own NoiseTexture2D
	# instance (not a single shared texture) so their noise phases don't all
	# scroll in visible lockstep, same reasoning as ArcA/ArcB's seed_offset.
	for i in range(wisps.size()):
		var wisp := wisps[i]
		var config: Dictionary = WISP_CONFIGS[i]

		var quad := QuadMesh.new()
		var quad_size: float = config["quad_size"]
		quad.size = Vector2(quad_size, quad_size)
		wisp.mesh = quad

		var angle: float = deg_to_rad(config["angle_deg"])
		var radius: float = config["radius"]
		wisp.position = Vector3(cos(angle) * radius, config["height"], sin(angle) * radius)
		_wisp_angles.append(angle)

		var wisp_mat := ShaderMaterial.new()
		wisp_mat.shader = WISP_SHADER
		wisp_mat.render_priority = config["render_priority"]
		wisp_mat.set_shader_parameter("softness", WISP_SOFTNESS)
		wisp_mat.set_shader_parameter("use_noise", 1.0)
		wisp_mat.set_shader_parameter("noise_tex", _make_noise_texture(WISP_NOISE_FREQUENCY))
		wisp.set_surface_override_material(0, wisp_mat)
		_wisp_materials.append(wisp_mat)

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

	print("[orb_controller] geometry ready: RingA segments=%d, RingB segments=%d, plates=%d, ArcA vertices=%d, ArcB vertices=%d, glass shells=%d, core housing + %d-point emblem vertices=%d, core sparks=%d, orbital particles=%d, wisps=%d" % [
		_ring_segments_a.size(), _ring_segments_b.size(), plates.size(),
		arc_a.mesh.surface_get_array_len(0), arc_b.mesh.surface_get_array_len(0), _glass_materials.size(),
		EMBLEM_POINTS, core_emblem.mesh.surface_get_array_len(0),
		core_sparks.amount, orbital_particles.amount, wisps.size(),
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


## Real Godot FastNoiseLite -> NoiseTexture2D, generated once at startup (no
## image asset, same discipline as every procedural mesh/material already in
## this project) -- reused VERBATIM from vfx_technique_poc_test.gd's own
## _make_noise_texture(), including its frequency parameterization.
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


## Hexagonal bipyramid ("crystal shard"): a top apex, a bottom apex, and
## `sides` equator points, forming 2*sides triangular facets. Each facet
## gets its OWN three vertex copies (never shared with a neighboring
## facet) with the SAME flat per-face normal on all three -- the
## structural property a single flat plate cannot have regardless of
## material: real, distinct face normals that catch the scene's one
## OmniLight3D differently per face. Reused VERBATIM from
## facet_poc_test.gd's _build_crystal_shard() (ORB_SILHOUETTE_MATERIAL_
## INVESTIGATION.md problem 2, variant B/C) -- same proven technique, not
## re-derived.
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
	_update_core_sparks(profile)
	_update_orbital_particles(profile)
	_update_wisps(delta, profile)

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


## Pass E: CoreSparks read as "energy spitting off the source" -- rate
## (amount_ratio) and speed (speed_scale) follow the exact same knobs
## AmbientParticles already uses, just on a second, independently-tuned
## particle system; size additionally scales _core_spark_process_material's
## scale_min/scale_max at runtime (CORE_SPARK_SCALE_MIN/MAX are the
## structural baseline, core_spark_size is the per-state multiplier -- same
## split as the glass shells' power_offset+rim_intensity).
func _update_core_sparks(profile: Dictionary) -> void:
	var rate: float = profile.get("core_spark_rate", 0.3)
	var speed: float = profile.get("core_spark_speed", 1.0)
	var size: float = profile.get("core_spark_size", 1.0)
	core_sparks.amount_ratio = rate
	core_sparks.speed_scale = speed
	_core_spark_process_material.scale_min = CORE_SPARK_SCALE_MIN * size
	_core_spark_process_material.scale_max = CORE_SPARK_SCALE_MAX * size
	var spark_color := _current_color.lerp(Color.WHITE, CORE_SPARK_BRIGHTEN)
	_core_spark_material.albedo_color = spark_color
	_core_spark_material.emission = spark_color
	_core_spark_material.emission_energy_multiplier = CORE_SPARK_EMISSION_ENERGY


## Pass E: OrbitalParticles read as "riding along with the rings" -- rate/
## speed/size follow the same pattern as _update_core_sparks() above.
## speed_scale here also scales orbit_velocity_min/max (Godot applies
## speed_scale to the whole particle simulation, orbit included), so
## orbital_speed genuinely changes how fast particles circle the orb, not
## just how fast they're emitted.
func _update_orbital_particles(profile: Dictionary) -> void:
	var rate: float = profile.get("orbital_rate", 0.3)
	var speed: float = profile.get("orbital_speed", 1.0)
	var size: float = profile.get("orbital_size", 1.0)
	orbital_particles.amount_ratio = rate
	orbital_particles.speed_scale = speed
	_orbital_process_material.scale_min = ORBITAL_SCALE_MIN * size
	_orbital_process_material.scale_max = ORBITAL_SCALE_MAX * size
	_orbital_material.albedo_color = _current_color
	_orbital_material.emission = _current_color
	_orbital_material.emission_energy_multiplier = ORBITAL_EMISSION_ENERGY


## Pass F: each wisp orbits the core at its own fixed radius/height (own
## structural base_speed from WISP_CONFIGS), scaled by the current state's
## wisp_speed -- so at wisp_speed=1.0 a wisp moves at exactly its own
## structural rate, same "structural constant + per-state multiplier" split
## already used for ring segments/glass shells/particles. base_color ties to
## _current_color (like every other energy element) so wisps participate in
## the state color story rather than reading as a fixed, state-blind layer.
func _update_wisps(delta: float, profile: Dictionary) -> void:
	var wisp_intensity: float = profile.get("wisp_intensity", 0.5)
	var wisp_speed: float = profile.get("wisp_speed", 0.5)
	var wisp_opacity: float = profile.get("wisp_opacity", 0.5)

	for i in range(wisps.size()):
		var config: Dictionary = WISP_CONFIGS[i]
		var base_speed: float = config["base_speed"]
		_wisp_angles[i] += base_speed * wisp_speed * delta

		var radius: float = config["radius"]
		wisps[i].position = Vector3(
			cos(_wisp_angles[i]) * radius, config["height"], sin(_wisp_angles[i]) * radius
		)

		var mat := _wisp_materials[i]
		mat.set_shader_parameter("base_color", _current_color)
		mat.set_shader_parameter("intensity", WISP_EMISSION_ENERGY * wisp_intensity)
		mat.set_shader_parameter("opacity_multiplier", wisp_opacity)
		mat.set_shader_parameter("noise_speed", WISP_NOISE_SPEED_BASE * wisp_speed)


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
		# comment: core_glow/core_emblem must both exceed arc_peak (and, as
		# of Pass F, wisp_peak) in every line this ever prints -- a new
		# bright element is never assumed safe, it's checked the same way
		# the arcs already are.
		var core_intensity: float = profile.get("core_intensity", 1.0)
		var core_glow_emission := CORE_GLOW_EMISSION_ENERGY * core_intensity
		var core_emblem_emission := CORE_EMBLEM_EMISSION_ENERGY * core_intensity
		var arc_peak_emission := ARC_EMISSION_ENERGY * float(profile["arc_intensity"])
		var wisp_peak_emission := WISP_EMISSION_ENERGY * float(profile.get("wisp_intensity", 0.5))
		print("[orb_controller] Pass A emission hierarchy for '%s' -> core_glow=%.2f core_emblem=%.2f arc_peak=%.2f wisp_peak=%.2f (core_intensity=%.2f) -- core_wins=%s" % [
			new_state, core_glow_emission, core_emblem_emission, arc_peak_emission, wisp_peak_emission, core_intensity,
			core_glow_emission > arc_peak_emission and core_emblem_emission > arc_peak_emission
				and core_glow_emission > wisp_peak_emission and core_emblem_emission > wisp_peak_emission,
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
