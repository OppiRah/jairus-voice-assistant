# Orb Silhouette + Material Investigation

## Status: Investigation only — the live orb scene was not touched

Same discipline as `ORB_RENDERER_INVESTIGATION.md` and the glass/PBR
material investigation it led to: this document identifies the best
achievable real-time techniques for two problems found in a visual
comparison against the concept image, proposes one concrete plan for
each (not a menu), and backs the material question with real,
self-verified test evidence. `orb_scene.tscn` and `orb_controller.gd`
were not modified — `git status` at the end of this investigation shows
only new, standalone test files, exactly like `glass_poc_test.tscn` did
for the earlier material investigation.

**The two problems, as given:** dark plates extend visibly past the
overall spherical/orbital silhouette ("poking out like flaps"); the
plates read as flat, matte, dark cardboard rather than glass/crystal,
against a backdrop of insufficient camera-driven depth, monotone color,
and sparse particles.

**Constraints honored:** no Python changes; the Mobile/Vulkan renderer
decision was not revisited; genuine desktop refraction was not
reopened; every finding below that could be tested was tested with a
real, standalone Godot scene and a real OS-level screenshot
(`System.Drawing.Graphics.CopyFromScreen`), not asserted from reasoning
alone.

---

## What was built to test this

Two new, standalone scenes, following the exact precedent of
`glass_poc_test.tscn`/`.gd` (zero coupling to `orb_scene.tscn` or
`orb_controller.gd` — if either test file were deleted tomorrow, nothing
about the real running app would change):

- **`silhouette_poc_test.tscn` / `.gd`** — three switchable "rigs"
  (`ACTIVE_RIG` constant, 0/1/2) approximating the real orb's proportions
  (Core/CoreHousing radii, RingA/RingB radii, the 4-glass-shell scale
  band, and `PLATE_CONFIGS`' real values copied verbatim) closely enough
  to judge silhouette containment and camera-driven depth, without
  needing the real scene's segmented-ring/arc/particle machinery.
- **`facet_poc_test.tscn` / `.gd`** + **`facet_fake_normal.gdshader`** —
  five plate-material variants side by side under one shared light, so
  material is the only thing differing between adjacent variants.

Both are throwaway investigation artifacts, same as `glass_poc_test.*`
— useful to keep in the repo as evidence and for the follow-up
implementation to re-run, not meant to ever be wired into the real
scene.

---

## Problem 1: Silhouette cohesion

### Finding

The plates poke out for a concrete, measurable reason, not a vague
"feels off": `PLATE_CONFIGS`' `radius` + each plate's own half-diagonal
reach (`size`, at worst-case orientation) already exceeds the outer ring
band before any screenshot is taken.

| Plate | radius | size half-diagonal | worst-case reach | RingB outer edge |
|---|---|---|---|---|
| 1 | 1.12 | 0.51 | **1.63** | 1.70 |
| 2 | 1.58 | 0.36 | **1.94** | 1.70 |
| 3 | 1.30 | 0.39 | **1.69** | 1.70 |

Plate 2 in particular reaches ~1.94 — well past RingB's own outer edge
of 1.70, and past the 4 glass shells (max scale 1.2× a radius-1.0
sphere) by an even wider margin. `silhouette_poc_test.tscn` Rig 0
reproduces this with the real `PLATE_CONFIGS` values and the real
dead-on camera transform: the screenshot shows two of the three plates
clearly breaking the outer glow silhouette, exactly matching the
reported "flaps" problem.

### The visible-vs-contained tension, resolved

The instinct to "just make the plates smaller" was checked directly,
per the task's explicit warning not to assume it. **Apparent visibility
comes from `size` (screen-space footprint) and contrast (dark object
against bright bloom); it does not require exceeding the ring band's
radius.** A plate sitting entirely inside the established silhouette is
just as visible as one poking out of it — dark-on-bright reads clearly
either way — so containment and visibility are not actually in tension.
The lever that trades them off against each other is `size`; the lever
that does not is `radius`/`height` (position).

**Rig 1** (`silhouette_poc_test.gd`'s `PLATE_CONFIGS_FIXED`) proves
this: every plate keeps its exact original `size` and `rotation_deg`
(same apparent footprint, same prominence) and only `radius`/`height`
were pulled inward (Plate 1: 1.12→1.0, Plate 2: 1.58→1.15, Plate 3:
1.3→1.1), keeping worst-case reach under ~1.55 — comfortably inside
RingB's 1.7 edge. The screenshot shows all three plates now fully
contained within the ring/glow silhouette, and just as visually
prominent as before — nothing was sacrificed.

### Camera's contribution, tested independently

**Rig 2** adds a single small, static off-axis tilt (18° yaw, 10° pitch
— not animation or parallax; that remains Pass G's job) on top of the
same fixed geometry. Comparing Rig 1 vs. Rig 2 screenshots: the tilt
produces a real, legible depth improvement beyond what the geometry fix
alone gives — the rings read as visibly elliptical rather than perfect
concentric circles, and the near-camera plate shows genuine
perspective size difference from the far one. This is a cheap, one-time
static transform change (no engine feature beyond `rotate_x`/`rotate_y`
already used everywhere else in this codebase), and it did not
reintroduce any silhouette overflow in the test.

### Recommendation: both together, one is necessary and one is a cheap bonus

**Geometry repositioning is the direct, necessary fix for the reported
problem** (camera changes alone cannot un-poke a plate that geometrically
extends past the silhouette from every angle a small tilt would use).
**The camera tilt is a genuine but secondary improvement** — worth
including in the same pass since it is nearly free and independently
verified to help, but it does not substitute for fixing the geometry.

**Concrete plan:** apply `PLATE_CONFIGS_FIXED`-equivalent values (pull
`radius`/`height` inward, keep `size`/`rotation_deg` unchanged) to the
real `PLATE_CONFIGS` in `orb_controller.gd`, and add one static
`Camera3D` transform change in `orb_scene.tscn` (equivalent to Rig 2's
18°/10° tilt) — both small, additive, independently revertable, same as
every prior pass's discipline.

---

## Problem 2: Material realism

### Finding, per sub-question — all tested in `facet_poc_test.tscn`

Five variants, same dark base color, same single `OmniLight3D`:

- **A — flat `BoxMesh` + the real metal `StandardMaterial3D`** (current,
  shipped): reads as one uniformly dark, flat-shaded silhouette. This
  reproduces "flat dark cardboard" directly.
- **B — faceted crystal-shard mesh + the same metal material, no other
  change**: with a favorable light/rotation, this alone shows a real,
  visible brightness split between adjacent facets — genuine per-facet
  specular response the flat box structurally cannot produce, confirmed
  by real screenshot (two facets of the same object at visibly different
  brightness under the same single light). This directly confirms the
  investigation's hypothesis: **geometry is a real, independent
  contributor, not a placebo** — but note it required a reasonably
  oblique light/camera angle to read clearly; at a near-flat angle the
  effect nearly disappears, which matters for how the real plates get
  posed once this lands.
- **C — same faceted mesh + Godot's built-in `StandardMaterial3D.rim_enabled`**
  (native engine feature: `rim`, `rim_tint`, no custom shader) on top of
  the same metallic/roughness: screenshot shows the clearest result of
  all five — real per-facet PBR specular from B, plus a distinct
  glass-like rim brightening on the near-edge facet. **This is the
  strongest result in the whole test**, and it costs nothing beyond
  flipping properties already built into `StandardMaterial3D` — no new
  shader file, stays fully opaque (real z-buffer sort, no
  `render_priority` bookkeeping needed, unlike every transparent element
  in this scene).
- **D — same faceted mesh + the real, already-validated
  `orb_glass_shell.gdshader` reused exactly as-is**: this is the
  literal "extend the existing Fresnel technique to the plates"
  option, and the screenshot shows exactly why it is the wrong answer
  for this element specifically: the shader's `render_mode ... unshaded`
  means it never queries `OmniLight3D` at all — its brightness comes
  only from a view-angle Fresnel term. The result reads as a pale,
  glassy shape indistinguishable in character from the 4 existing glass
  shells, not a dark crystal shard. **Reusing this shader unmodified
  does not give the plates a "crystal" look — it turns them into a 5th
  glass shell**, which erases the dark/light material contrast that was
  Pass A2's entire reason for the plates existing (design doc §8).
  Pass A2's original *material family choice* (a separate, real-lit
  metal material distinct from the unshaded glass recipe) was correct
  to keep separate from the glass shells; what needs revisiting is only
  the *geometry* it's applied to (flat → faceted) and adding the rim
  feature from variant C, not swapping in the glass shader.
- **E — flat `BoxMesh` (identical to A) + a procedural fake-facet shader**
  (`facet_fake_normal.gdshader`, hashes UV cells to a pseudo-random
  tilted shading normal, assigned directly to `NORMAL` in `fragment()` —
  the same underlying mechanism a real baked normal-map texture would
  use, just generated instead of sampled): the screenshot shows this
  reads as indistinguishable from A at the sizes/angles the real plates
  are actually seen at. **The investigation's skepticism here was
  correct**: faking a facet normal on a surface that is still
  geometrically flat does not read as "faceted" — a real normal map
  would face the identical limitation, since both perturb the exact
  same underlying flat geometry the exact same way for lighting
  purposes. This is not a viable substitute for real geometry.

### Same-scene lensing on the plates specifically

`orb_glass_shell.gdshader`'s lensing samples `SCREEN_TEXTURE`, which is
only populated correctly for objects in the **transparent** render
queue (the shader's own existing comment already documents this: the
screen copy happens after the opaque pass, before transparent
geometry draws). That means lensing is structurally incompatible with
keeping the plates **opaque** — the property variant C's recommended
material relies on for automatic z-buffer sorting. Toggling
`lens_distortion` between 0.0 and 0.12 on variant D (with a
`BackgroundMarker` placed behind it specifically for this check) showed
only a marginal difference, within what ordinary alpha blending against
that marker already produces. **Recommendation: do not add lensing to
the plates.** It would require making them translucent (reopening the
AABB transparency-sorting risk `orb_controller.gd`'s own comments
already flag as growing with every new layered element), for a visual
gain this test could not distinguish from noise. Lensing stays exactly
where it already earns its cost: the genuinely translucent glass
shells and `CoreHousing`.

### Recommendation: one concrete material, not a menu

**Replace the flat `BoxMesh` plates with a low-poly faceted mesh (the
hexagonal-bipyramid "crystal shard" technique proven in
`facet_poc_test.gd`'s `_build_crystal_shard()` — real per-face flat
normals via unshared vertices per triangle, built with `SurfaceTool`,
same asset-free technique already used for the emblem and energy arcs),
keep the existing shaded metal `StandardMaterial3D` recipe (`metallic`/
`roughness` unchanged from Pass A2), and add `rim_enabled = true` with a
modest `rim`/`rim_tint`.** This is additive to Pass A2's material
family, not a replacement of it — Pass A2's choice to keep the plates on
a separate, real-lit, non-emissive material was correct and stays;
only the geometry gains facets and the material gains one built-in
property. No new shader file is needed for the plates themselves.

---

## Secondary findings (brief, reasoned — not independently screenshotted)

- **Color monotone vs. the concept's internal gradient**: this is a
  shallow, material-level fix, not a lighting-architecture change. The
  core glow is one flat emissive color; a two-tone gradient (e.g. a
  warmer/brighter center fading to the state's cooler base color toward
  the rim) is a same-category change to the existing unshaded core
  material — a few lines in a small fragment shader keyed on local
  position or `NORMAL`, reusing the exact "small `.gdshader` for one
  element" pattern already established by `orb_arc_ribbon.gdshader` and
  `orb_glass_shell.gdshader`. No new technique, no `WorldEnvironment`
  change required.
- **Particle density/fineness vs. the concept's dust-like field**: Pass
  E already solved the *role* problem (core sparks / orbital / ambient
  are now distinct). The remaining gap is purely a tuning question for
  the *ambient* role specifically — more, smaller, dimmer particles read
  as "fine dust"; fewer, larger, brighter ones read as "sparse motes"
  (the current complaint). Given this project's own measured headroom
  (>1600 FPS with meaningfully more scene content than a particle-count
  bump would add), this is safely "more of what exists, tuned finer":
  raise `AmbientParticles.amount`, lower `scale_min`/`scale_max`, and
  slightly lower per-particle `emission_energy_multiplier` so more,
  smaller particles don't flood the bloom threshold. No new emission
  shape is needed for this role — `orbital`/`core_spark` already got
  their own dedicated shapes in Pass E.

---

## Proposed staged implementation sequence (for the follow-up prompt)

Following this project's own established discipline — one small,
independently screenshot-verified change per stage, not a bundled
rewrite:

1. **Plate containment** — apply the `PLATE_CONFIGS_FIXED`-equivalent
   radius/height values to the real `PLATE_CONFIGS`. Verify: real
   screenshot confirms no plate silhouette exceeds the outer glow band,
   in every state (bloom expands slightly with `glow_intensity` per
   state, so check at least `error`, the brightest).
2. **Plate geometry** — replace the plates' `BoxMesh` with the faceted
   crystal-shard mesh (reuse `_build_crystal_shard()` from
   `facet_poc_test.gd` verbatim, sized to roughly match each plate's
   current footprint). Verify: real screenshot shows visible per-facet
   brightness variation under the scene's real `OmniLight3D`, at the
   real camera angle chosen in stage 4 below (not a favorable
   POC-only angle).
3. **Plate material** — add `rim_enabled`/`rim`/`rim_tint` to the
   existing plate `StandardMaterial3D` (no new shader). Verify: real
   screenshot comparison against stage 2 alone, confirming the rim
   adds a distinct glassy edge without washing out the dark base color.
4. **Camera tilt** — apply the small static off-axis transform to
   `orb_scene.tscn`'s `Camera3D` (equivalent to Rig 2's 18°/10°).
   Verify: real screenshot confirms rings read as visibly elliptical
   and stage 1-3's plate containment still holds from the new angle
   (re-check worst-case reach under the tilt, not just dead-on).
5. **(Optional, smaller/lower-priority) Core color gradient** — small
   fragment-shader tweak to the core glow material for the internal
   two-tone gradient.
6. **(Optional, smaller/lower-priority) Ambient particle fineness** —
   tune `AmbientParticles.amount`/`scale_min`/`scale_max`/
   `emission_energy_multiplier` for a finer dust read.

Stages 1-4 directly answer this investigation's two named problems and
should land together as one reviewable pass (each individually
screenshot-checked per this project's discipline, per stage, before
moving to the next); 5-6 are independent, smaller, and can follow
separately or be deferred without blocking 1-4.
