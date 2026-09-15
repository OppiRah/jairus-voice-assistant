# Orb Concept Gap Analysis

## Status: Planning only — no renderer code changed

This document is a visual gap-analysis and prioritized roadmap comparing the
live Godot orb renderer against `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md`.
Nothing in `src/jairus/interfaces/renderer/godot_project/` was modified to
produce this document. No commits were made.

**A note on the reference image itself**: the AI-generated concept image
described in `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md` was not found as a file
anywhere in this repository (checked the repo tree and the user's Desktop for
image files; none matched — two candidate PNGs on the Desktop turned out to
be unrelated worksheet scans). This analysis is therefore grounded entirely
in the design direction document's own detailed, section-by-section
description of that image (its sections 3–16), which is specific enough
(central emblem, dark housing, segmented/angular orbital geometry, glass vs.
metal material contrast, layered bloom hierarchy, etc.) to drive a real
comparison. If a copy of the actual image can be placed in the repo, re-check
section 2 and the gap table below against it directly — this document should
be treated as accurate-to-the-brief, not verified-against-pixels.

---

## 1. Current renderer summary

**Where it lives**: `src/jairus/interfaces/renderer/godot_project/`
(`orb_scene.tscn` + `orb_controller.gd` + `orb_glass_shell.gdshader`), a
Godot 4.x transparent/borderless/always-on-top process, driven read-only
over `ws://localhost:8767` by `bridge.py`, which mirrors
`AssistantState.get_snapshot()`/`get_activity_snapshot()`. This
architecture is sound, already validated end-to-end (real OS-level
screenshots, real FPS measurements, real subprocess lifecycle), and is
explicitly out of scope to change per this task's constraints.

**Scene contents, exactly as built today** (`orb_scene.tscn`):

| Node | Mesh/type | Shape |
|---|---|---|
| `Core` | `SphereMesh`, radius 0.6, 48×24 segments | perfect sphere |
| `RingA` | `TorusMesh`, inner 1.3 / outer 1.45 | perfect, continuous torus |
| `RingB` | `TorusMesh`, inner 1.55 / outer 1.7 | perfect, continuous torus |
| `ArcA`/`ArcB` | procedural `SurfaceTool` ribbon, 7 points, radius 0.75 | short jagged strip |
| `GlassShell1-4` | `SphereMesh`, radius 1.0, non-uniform scale | ellipsoids |
| `AmbientParticles` | `GPUParticles3D`, 220 × tiny `SphereMesh` (radius 0.018) | omnidirectional drifting dust |
| `Camera3D` | fixed, `z=3`, no rotation/animation | static, dead-on |
| `WorldEnvironment` | `glow_enabled`, single global post-process | — |
| `OmniLight3D` | one weak light (0.6 energy) | — |

**Materials**: every single material in the scene is
`StandardMaterial3D` with `shading_mode = UNSHADED` and
`emission_enabled = true` (core, rings, arcs, particles), or the one
`ShaderMaterial` (`orb_glass_shell.gdshader`, Fresnel rim-lighting + a
same-scene screen-texture lensing term) on the 4 glass shells. There is
no material anywhere in the scene that is dark, low-emission, or reads as
metal/mechanical — literally everything present emits light.

**State system** (`STATE_PROFILES` in `orb_controller.gd`): 9 rows
(`idle, listening, thinking, speaking, executing, completed, error,
offline, waiting_confirmation` — a superset of the 8 states the design
doc asks for), each independently tuning 12 parameters: `color,
pulse_speed, pulse_irregular, particle_amount, particle_speed,
glow_intensity, glow_strength, ring_speed, ring_opacity, arc_intensity,
arc_frequency, glass_rim_intensity, glass_lens_strength`. This table is
real, already centralizes tuning as required, and already makes states
differ by more than color.

**What it visually reads as today, plainly stated**: a bright core
sphere, surrounded by two perfectly smooth rotating rings, surrounded by
four faint, smooth, semi-transparent bubbles, with two short flickering
light-strands and a light dust haze around it — i.e., **seven
concentric/orbiting round or ellipsoidal primitives, differentiated only
by size, tilt, opacity and color.** That is close to a literal
description of "nested glowing spheres," the exact anti-pattern the
design document names and explicitly rejects (§1, §5). This is the
single most important finding in this document and the frame for
everything below.

---

## 2. Visual reference breakdown (from the design document)

Per `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md`, the reference concept's
visual language is:

- A **recognizable central emblem** (diamond/star-like Jairus symbol) inside a **dark inner housing**, not an undifferentiated glowing ball (§4).
- **Segmented, angular, asymmetric orbital structure** — partial arcs, offset plates, varied thickness, independently-oriented and independently-rotating pieces, gaps — explicitly *not* concentric complete circles (§5, §12).
- **Energy ribbons** that read as fluid/organic/continuously flowing, visually distinct from the rigid, mechanical, precise rings (§6).
- **Glass/crystal layers** that create depth via *unequal* brightness between layers, plus **dark metal/mechanical components** that contrast with the luminous parts — the glass and the metal are two different material languages used deliberately against each other (§7, §8).
- A **bloom hierarchy**: core strongest → ribbons → Fresnel edges → particles, weakest (§10).
- **Four distinct particle roles** (core sparks, orbital, energy-ribbon, ambient), not particle count (§9).
- **3D depth** the viewer can actually perceive — multiple depth planes, differing orientations, parallax (§11).
- **Controlled asymmetry** — not procedural/random, not perfectly symmetric (§12).
- State behavior expressed through **more than color**: intensity, speed, direction, irregularity, particle behavior (§13).

---

## 3. Current-vs-target comparison, by category

### CORE
Current: a single unshaded emissive sphere; color and pulse (uniform
scale) are the only differentiators; no emblem, no housing, no internal
structure. Target: dark housing + sharp symbol + concentrated brightness
+ internal layered depth. **This is close to a complete miss** — not "the
core needs polish," but "the core, as a designed object, does not exist
yet." The sphere is a placeholder for where the core should be.

### STRUCTURE
Current: 2 complete, smooth `TorusMesh` rings + 4 complete, smooth
ellipsoid shells. Every structural element is a full 360° surface of
revolution. The only variation between elements is transform (tilt,
roll, non-uniform scale) — never the geometry itself. Target: segmented/
partial/angular/gapped geometry. **This is the literal "nested glowing
spheres" pattern**, and per the design document's own framing (§5) is
one of the two biggest priorities in this whole analysis.

### ENERGY
Current: 2 short (7-vertex, `ARC_RADIUS=0.75`, half-width 0.015) ribbons
that binary flicker on/off based on a `sin()` threshold test
(`ARC_FLICKER_THRESHOLD`), rotating at a fixed rate. This is
conceptually the right idea — a separate, more organic-feeling element
distinct from the rigid rings — but in practice it is too small, too
sparse, and its motion (discrete visibility toggling, not continuous
flow) doesn't read as "energy circulating." Target: fluid, continuous,
visibly flowing arcs. **Gap is real but the foundation (a working
ribbon-mesh technique, already proven) is closer to reusable than any
other structural element.**

### MATERIALS
Current: the glass technique itself (Fresnel rim-lighting,
`orb_glass_shell.gdshader`) is genuinely sound engineering — validated
with real OS screenshots, a documented and correct understanding of why
screen-texture "desktop refraction" is architecturally impossible here,
and real render-priority sorting mitigations for the AABB transparency-
sorting risk. But **every other material in the scene (core, rings,
arcs, particles) uses the exact same unshaded-emissive recipe** — there
is no dark, low-transparency, restrained-emission "metal" material
anywhere. The design document's material contrast (§8) is entirely
one-sided in the current implementation.

### LIGHTING
Current: one global `WorldEnvironment.glow_*` post-process, tuned
per-state (`glow_intensity`/`glow_strength`), plus per-material
`emission_energy_multiplier` values that feed into that same global
bloom. **Concrete, verifiable defect**: the actual baseline multipliers
are `ARC_EMISSION_ENERGY = 4.0` (×`arc_intensity`, up to 7.2 at
`error`) vs. `EMISSION_ENERGY = 3.5` for the core (flat, no per-state
multiplier except the brief `completed` pop) vs. `EMISSION_ENERGY * 0.6
= 2.1` for rings. **The arcs already out-bloom the core in every state,
and always have.** This is the exact inverse of the design document's
required hierarchy ("Core energy → strongest," §10) — not a matter of
taste, a specific, fixable numeric bug in `_process()`/`_update_arcs()`.

### PARTICLES
Current: exactly one of the four requested roles exists — "ambient"
(`AmbientParticles`, 220 instances, `emission_sphere_radius=1.1`,
`spread=180` i.e. functionally omnidirectional, slow drift, no gravity).
It's reasonably well-tuned for what it is (subtle, doesn't obscure
structure — the thing the brief explicitly warns against is *not*
happening here). Core sparks, orbital-path particles, and energy-ribbon
particles (§9) don't exist as separate emitters/behaviors at all.

### COMPOSITION
Current: `Camera3D` is static — fixed position, fixed rotation, no
animation, ever. The silhouette is close to circular from every state
(a sphere, two round tori, four round shells) with the only asymmetry
coming from differing *tilts* of otherwise-identical round shapes. At
480×480 with a dead-on camera, there is no parallax and very little
depth cue beyond the shells' own Fresnel self-brightening at glancing
angles. It has not been tested over varied real desktop backgrounds
against reference imagery (per the design doc's success criterion #11)
— only against the black/empty Godot-scene background used for FPS/
screenshot validation in the investigation doc.

### STATE PRESENTATION
Current: this is the strongest part of the implementation. All 8
requested states (plus `speaking`) are present, each independently
tuned across 12 parameters in one central, well-commented table, closely
matching the design document's intent (§13) — e.g. `error` is fast,
irregular, bright, distorted; `offline` is barely-there; `thinking` is
irregular/energetic; `completed` gets a one-shot brightness pop. This
already substantially meets the brief and does not need to be a
priority.

---

## 4. Prioritized visual gaps

| Element | Current implementation | Reference target | Gap | Priority |
|---|---|---|---|---|
| Central core / symbol | Plain unshaded emissive `SphereMesh`; color + uniform-scale pulse are the only variables; no emblem, no housing | Dark inner housing, sharp diamond/star Jairus emblem, concentrated brightness, layered internal depth | No symbol exists; the core is literally "a glowing sphere" — the exact thing the brief opens by rejecting | **HIGH** |
| Orbital/structural geometry | 2 complete `TorusMesh` rings + 4 complete ellipsoid shells; only transform (tilt/roll/scale) varies between them, never the geometry | Segmented/partial-arc rings, angular glass plates, dark mechanical components, gaps, varied thickness, irregular structure | Every structural piece is a smooth, mathematically complete surface of revolution — this *is* the "nested glowing spheres" pattern named and rejected in the brief | **HIGH** |
| Energy ribbons | 2 short (7-vertex), thin, binary-flicker ribbons | Continuously-flowing, organic-reading energy circulating around/through the core | Right concept, wrong scale/motion — too sparse and too discrete to read as "alive" | **HIGH** |
| Bloom/emission hierarchy | Verified inversion: arc baseline (4.0, up to 7.2) > core (3.5) > rings (2.1) | Core strongest → ribbons → Fresnel edges → particles | A specific, numeric, easily-fixed bug — arcs currently out-bloom the "source of the orb's energy" | **MEDIUM** *(small engineering cost, outsized visual payoff — do this alongside the core rework)* |
| Materials (glass vs. metal contrast) | Fresnel glass technique is real and validated; but zero dark/restrained/metal material exists anywhere in the scene | Glass *and* dark mechanical components used deliberately against each other | The glass half of the material language works; the metal half is entirely absent, so nothing in the scene ever reads as "constructed object" rather than "effect" | **MEDIUM** |
| Particles | Only the "ambient" role exists (220 slow-drifting dust motes); reasonably well-tuned for what it is | 4 distinct roles: core sparks, orbital, energy-ribbon, ambient | 3 of 4 requested behaviors are simply missing; what exists is not bad | **MEDIUM-LOW** |
| Composition/camera/depth | Static, dead-on camera; near-circular silhouette from every angle since nothing but round primitives exists; untested over real desktop backgrounds | Depth layering, parallax cues, silhouette that reads as an asymmetric device | Largely a downstream symptom of the structure gap — fixing structure will do most of the work here; camera itself is a separate, smaller fix | **LOW** *(revisit after structure/core)* |
| State-driven behavior | 9 states × 12 tuned parameters, centralized, matches brief's intent closely | States differ by more than color | Already substantially meets the brief | **Already good — no action needed** |
| Transparency/bloom infrastructure, glass technique validation | Real OS-composited transparency confirmed; Fresnel rim-lighting confirmed via real screenshots; AABB sorting risk understood and mitigated via `render_priority` | Bloom emphasizes geometry rather than replacing it | Infrastructure and technique are sound — but honestly, currently amplifying plain primitives, which is why it doesn't yet look like the target despite being technically correct | **Infra: no action. Visible result: downstream of Core/Structure gaps above.** |

**Named explicitly, since the brief asked for brutal honesty**: the 4-shell
Fresnel glass pass is a case of **technically impressive work with currently
limited visual payoff** — the implementation itself already diagnoses this
in its own code comments (`orb_controller.gd` lines ~118–130): "4 equally
bright concentric shells inherently read as 4 equally-visible nested rings,
not glass depth... an intrinsic property of the technique on a static front
view, not a tunable bug." That is a precise, self-aware description of
exactly the failure mode this document is naming at the whole-scene level.
The fix in both cases is the same: stop adding more smooth concentric
layers, and start giving the *existing* layers actual designed geometry.

---

## 5. Recommended implementation sequence

This follows, and slightly refines, the design document's own §18 pass
structure, reordered by leverage (visual impact ÷ engineering cost) rather
than by number:

1. **Pass A1 — Core redesign** (smallest, highest-leverage, fully
   self-contained). Dark inner housing + a real emblem mesh + rebalanced
   emission hierarchy (fix the arc/core bloom inversion in the same pass,
   since it's touching the same numbers). See §8 for exact scope.
2. **Pass A2 — Segmented/asymmetric structural geometry.** Replace at
   least one complete `TorusMesh` with a genuinely segmented/gapped ring
   (partial-arc geometry, not a full torus with a transparent gap texture
   hack), and introduce 1–2 angular "plate" elements with a dark,
   low-emission material. This is where the "nested spheres" problem
   actually gets solved structurally.
3. **Pass B — Energy ribbons, take 2.** Longer, more continuous-reading
   arcs (more points, continuous brightness modulation instead of binary
   flicker, optionally particle trails riding the same path) — reuses
   the existing `_build_arc_mesh()` approach, just extended.
4. **Pass C — Material contrast pass.** Add the dark/metal material
   family (a second `StandardMaterial3D` recipe: shaded or low-emission,
   higher opacity, sharper specular/no bloom contribution) and apply it
   to the new Pass A2 plate elements plus perhaps a literal dark housing
   ring/frame around the core.
5. **Pass E — Particle roles.** Add "core sparks" (small, high-velocity,
   short-lifetime emitter hugging the core) and "orbital" particles
   (constrained to a ring path) as two new, separate `GPUParticles3D`
   nodes; defer "energy-ribbon" particles until the ribbons themselves
   are reworked in Pass B, since they should ride the ribbon path.
6. **Pass G — Composition.** Revisit camera (subtle idle drift/parallax?
   framing?) and re-verify readability over real, varied desktop
   backgrounds with real OS screenshots (not Godot-internal captures),
   once the geometry underneath is worth framing.
7. **Pass F — State polish.** Only after the above, re-tune
   `STATE_PROFILES` against the new geometry (new fields will likely be
   needed once segmented rings/plates/new particle roles exist to
   modulate).

Do not attempt A1 and A2 as a single commit — they are independently
testable per the project's own discipline (§18 of the design doc, and
this project's git history, which already shows every prior visual
change landing as its own small, screenshot-verified commit).

---

## 6. Technical feasibility of each major improvement

- **Core emblem + dark housing** — **Low engineering cost.** A flat or
  slightly-extruded emblem can be built the same way `_build_arc_mesh()`
  already builds procedural geometry (`SurfaceTool`, no external
  assets), or as a small hand-authored `.obj`/`.tres` mesh imported once.
  A dark housing is just a second, larger, low-emission
  `StandardMaterial3D` sphere/capsule drawn behind the emblem with
  `render_priority` below the emissive core. No shader work required.
  Rebalancing `EMISSION_ENERGY`/`ARC_EMISSION_ENERGY`/ring multiplier
  constants is a one-line-per-constant change. **Highest leverage-to-cost
  ratio of anything in this document.**
- **Segmented/partial-arc rings** — **Low-medium cost.** A partial torus
  is buildable procedurally (same `SurfaceTool` technique used for the
  arcs, generalized to a wider ribbon following a torus-like path, or by
  generating a standard `TorusMesh` and clipping/discarding a UV range in
  a small custom shader). Multiple short segments with gaps, at
  independent tilts/speeds, is straightforward given the rotation
  machinery already in `_process()`. Angular "plate" elements are just
  `BoxMesh`/`PrismMesh`/custom low-poly meshes with the new dark
  material — no new engine features needed.
- **Continuous-flowing energy ribbons** — **Low-medium cost.** Extending
  `ARC_POINT_COUNT`, replacing the binary `sin() > threshold` visibility
  toggle with a continuous brightness/alpha modulation along the ribbon
  (e.g. a per-vertex color/UV gradient sampled in a small custom
  shader, or simpler: animate `emission_energy_multiplier` continuously
  instead of a hard visible/invisible cut), is incremental work on an
  already-proven technique.
- **Dark/metal material family** — **Low cost.** A second
  `StandardMaterial3D` recipe (shaded, or unshaded-but-dim, low/no
  `emission_energy_multiplier`, higher albedo saturation, possibly a
  simple specular/roughness pass since it doesn't need to be
  bloom-driven) is a small, additive addition next to
  `_make_translucent_material()`.
- **Additional particle roles** — **Low cost per role.** Each is just
  another `GPUParticles3D` node + `ParticleProcessMaterial` with
  different `emission_shape`/`direction`/`spread`/velocity/lifetime
  values, following the exact pattern `AmbientParticles` already
  establishes. "Orbital" particles specifically may want
  `emission_shape = RING` or a curve-constrained process material —
  worth a small spike to confirm Godot 4.x's exact `ParticleProcessMaterial`
  options support a clean ring-path emission (very likely, but not yet
  verified in this project the way transparency/bloom already were).
- **Camera/composition changes** — **Low cost technically** (Godot
  camera animation is trivial), but **must be re-verified with real OS
  screenshots over a real desktop background** per this project's own
  established discipline — this is a testing-process cost, not an
  engineering one.
- **Performance** — every item above uses techniques already measured in
  this codebase at >1600 FPS uncapped for a scene doing comparable or
  more work than any single addition here. Per the investigation
  document's own numbers, there is no realistic path by which this
  roadmap threatens the 60 FPS target on the validated hardware. No item
  in this roadmap should be scoped down for GPU-cost reasons; scope
  decisions should be made purely on visual-payoff grounds.

---

## 7. Risks / tradeoffs

- **Transparency sorting risk grows, not shrinks, with more geometry.**
  Every new opaque/transparent element (new plates, new segmented rings,
  new particle emitters) adds to the same AABB-based sorting problem the
  glass-shell investigation already had to work around via
  `render_priority`. Each new pass needs its own `render_priority`
  slotting, not an assumption that Godot will "figure it out."
- **A core emblem risks becoming unreadable if bloom is re-tuned
  carelessly.** The design doc is explicit (§4, §10): "the Jairus symbol
  should remain recognizable rather than being destroyed by bloom." Once
  the core's `emission_energy_multiplier` is raised to actually dominate
  the hierarchy (per §4 above), the emblem's own alpha/silhouette needs
  to survive that increase — this should be checked with a real
  screenshot specifically for emblem legibility, not just "bloom looks
  good."
- **Segmented geometry raises visual-complexity risk** ("visually
  complex without becoming messy" is an explicit design goal, §1). Each
  new angular/segmented element should be screenshot-reviewed
  individually before the next is added, exactly per this project's
  existing "don't blindly combine many visual changes into one
  untraceable rewrite" discipline.
- **New particle roles increase total particle count**, which the brief
  explicitly warns against optimizing for its own sake (§9: "not
  particle spam"). Each new emitter should be tuned for *behavior*, not
  volume, and checked that it doesn't start obscuring the now-more-
  detailed structure underneath it.
- **Nothing here touches architecture**, but it's worth stating plainly:
  none of this roadmap requires new IPC fields, new `AssistantState`
  vocabulary, or backend changes — `STATE_PROFILES` may eventually grow
  new *tuning fields* (e.g. an emblem-brightness multiplier, a plate
  rotation speed) but that is purely additive to an existing table
  already living entirely inside the Godot project, matching the
  "renderer remains a presentation layer" constraint.

---

## 8. Smallest first visual prototype

**Core redesign only — nothing else touched.** Concretely:

1. Add a second, larger, low-emission sphere/capsule behind the existing
   `Core` node (`render_priority` below it) using a new "dark housing"
   material — first instance anywhere in the scene of a non-emissive
   material.
2. Replace (or overlay on) the current plain-sphere emissive draw with a
   small procedurally-built emblem mesh (diamond/star silhouette — same
   `SurfaceTool` technique already proven in `_build_arc_mesh()`),
   material unshaded+emissive as today, but now the *only* thing in the
   core that's bright, rather than the whole sphere.
3. Fix the emission-hierarchy inversion found in §3/§4: raise the core's
   effective multiplier (or lower the arcs'/rings') so the core is
   verifiably the brightest bloom source in every state, not just at
   `completed`'s transient pop.
4. Verify with a real OS-level desktop screenshot (per this project's
   own established rule — no claims from in-engine capture) that: the
   emblem is recognizable, the dark housing reads as depth/contrast
   rather than a black hole, and the core now visually dominates the
   rings/shells/arcs around it the way §3's hierarchy diagram requires.

This is deliberately scoped to touch only `Core`-adjacent code
(`_ready()`'s core material setup, a new small mesh-building function,
and the existing emission constants) — zero risk to the already-working
rings/arcs/glass-shell/particle systems, independently revertable, and
directly answers the single biggest, most specifically-named gap in this
document ("should NOT read as an ordinary glowing sphere").

---

## 9. Recommended next implementation phase

**Build the Core redesign prototype (§8) as its own standalone,
screenshot-verified visual pass — not bundled with structural/ribbon/
material/particle work.**

Once that lands and is verified against a real desktop background,
proceed to Pass A2 (segmented/asymmetric structural geometry, §5 item 2)
as the next pass, since between them Core + Structure are the two gaps
explicitly called the biggest priorities by the design document itself,
and every other category in this analysis (materials, lighting
hierarchy, particles, composition) is either a smaller/cheaper fix or a
downstream beneficiary of getting those two right first.

---

# Summary

**What's already good**: the underlying architecture (Godot subprocess,
WebSocket bridge, transparent OS compositing) is validated and solid; the
Fresnel glass technique is real, well-tested, and correctly reasoned about
its own limits; and the state-driven behavior system (`STATE_PROFILES`,
9 states × 12 parameters, centrally tuned) already substantially meets the
design brief. None of that needs rework.

**What's holding the orb back visually**: every visible element in the
scene — core, rings, glass shells, particles — is a smooth, complete,
mathematically perfect sphere/torus/ellipsoid, differentiated from each
other only by size, tilt, and color. There is no emblem, no dark
material, no segmented or angular geometry anywhere. This is, close to
literally, the "nested glowing spheres" pattern the design document opens
by naming and rejecting. On top of that, a specific, fixable bug means the
energy arcs currently out-bloom the core itself, inverting the intended
"core is the source of the orb's energy" hierarchy.

**The #1 thing to build next**: a redesigned core — dark inner housing +
a real Jairus emblem mesh + a corrected emission hierarchy so the core is
verifiably the brightest thing in the scene.

**Why that should be next**: it is the single most specifically-named gap
in the design document (§4 calls the core "one of the most important
elements" and explicitly rejects "an ordinary glowing sphere" — which is
exactly what exists today), it is the smallest, cheapest, most
self-contained change in this entire roadmap (one node, no new shader,
no risk to existing rings/arcs/glass/particles), and it is the first
thing a viewer's eye lands on per the design document's own visual
hierarchy diagram (§3) — so it has the highest visual-impact-per-
engineering-cost ratio of anything identified in this analysis.
