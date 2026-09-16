# JAIRUS ORB — VFX TECHNICAL ARCHITECTURE

Research and architecture document only. No Godot project, scene, script, or
shader was created or modified to produce this report. Nothing here has been
committed to version control. This is input for an independent review
(ChatGPT), not an implementation plan.

**Scope note on prior work:** the previous orb implementation (rings/plates/
core/ribbons, archived at `archive/orb_v1/`) is treated purely as removed R&D.
None of its geometry, shader code, or scene structure is assumed, referenced,
or reused as a constraint below. Where this document reaches a similar
technique to something in that archive (e.g. "use GPUParticles3D"), that is
because the technique is independently the right Godot answer, not because it
carries forward from the old design.

**Source-confidence key**, used throughout:
- **[DOC]** — directly confirmed against current official Godot 4.x
  documentation or the engine source/changelog during this research pass.
- **[INFER]** — a reasonable technical consequence of documented behavior,
  but not itself found stated verbatim in the docs. Flagged for prototyping.
- **[REC]** — this document's own recommendation/judgment call, not a claim
  about Godot's capabilities.

---

## 1. Executive Summary

The brief describes a compact, mostly-symmetrical spherical/orbital artifact
whose personality lives in a **geometrically alien, computationally-morphing
core**, driven by a **shared energy-parameter model** so the whole object
reads as one living system rather than several unrelated VFX glued together.
Godot 4.x has real, documented building blocks for essentially every piece of
this: `GPUParticles3D` with trail meshes and sub-emitters, `Path3D`/`Curve3D`
procedural geometry, vertex-shader noise displacement, Fresnel-style rim
shading, `CompositorEffect` for custom post-processing, `Decal`/light-projector
techniques for a "the symbol emerges from the object" reveal, and — critically
for the "one living system" requirement — **global shader uniforms**, which
let a single script push shared parameters to every material in one call
**[DOC]**.

The architecture recommended here is: one central `EnergyModel` node owns a
small set of shared parameters (intensity, activity, turbulence, coherence,
pulse, core_morph, field_strength, particle_activity, symbol_reveal), smooths
them per-state, and pushes them out as global shader uniforms; every visual
system (core, rings, wisps, particle populations, symbol) is a *consumer* of
that shared state, never an independent animator. Rendering should target the
**Forward+** renderer (the desktop-appropriate, most capable of Godot's three
renderers) **[DOC]**, and should treat layered-transparency overdraw — not
particle count — as the primary GPU risk on a 6 GB laptop GPU.

The single biggest **open technical risk** is whether a per-pixel-transparent
Godot window (the "floating desktop artifact" presentation model) can
co-exist with the heavy internal transparency/distortion techniques this
brief wants, because Godot's screen-reading shaders only see *Godot's own*
rendered frame, not the real OS desktop showing through a transparent window
**[INFER — must be verified in a throwaway prototype before committing any
scene architecture around it]**. The second biggest risk is that "alien,
geometric, morphing core" is the one requirement Godot has no turnkey feature
for — it has to be built from noise-driven vertex displacement and multiple
noise domains, and that prototype should happen before anything else, because
if it doesn't read as "alien" the rest of the architecture doesn't matter.

---

## 2. Design Interpretation

Restating the finalized direction in terms this document will build against,
without adding new design decisions:

- Silhouette: compact hybrid sphere/orbital form, symmetrical at rest;
  asymmetry is a function of *transient energy behavior*, not base geometry.
- Energy:technology ratio ≈ 70:30. No literal machinery (screws, gears,
  cables, panels, reactor hardware).
- The **core** is the primary character: geometric, alien, computationally
  "morphing," not a rotating sphere.
- The **Jairus symbol** is normally hidden and emerges from
  geometry/energy/shader behavior in specific states — not a static logo.
- **Orbital structures**: thin elegant rings/curves, not mechanical gyroscope
  rings.
- **Materials**: mixed — opaque/dense core structure, transparent energy,
  translucent atmosphere, some refraction-like distortion. Not one glass ball.
- **Energy language**: electromagnetic (primary) / computational (secondary)
  / plasma (accent). Structured, intelligent-looking, not fire/smoke/magic.
- **Seven states** (`IDLE`, `LISTENING`, `THINKING`, `EXECUTING`, `SUCCESS`,
  `ERROR`, `OFFLINE`) each have a distinct energy *profile*, not just a color
  swap; `EXECUTING` is maximum visual complexity but must never look unstable
  or dangerous — "overwhelming power under perfect control."
- **Palette**: near-white/light energy (primary), dark maroon (structural/
  depth, more visible at high energy), gold (sparse, reserved for
  "intelligence/important internal activity" — symbol reveal, success pulse,
  rare highlights).
- **Camera**: subtle drift/orbit, not a constant showcase spin; can respond
  somewhat to state.
- **Technical ambition**: push visual fidelity first on an RTX 3060 Laptop
  GPU / 6 GB VRAM, but with a "maximum useful visual complexity per GPU cost"
  filter — this document is explicitly asked to be critical about which
  techniques are worth it.
- **Reference lesson carried forward as a technique, not a look**: a
  convincing high-end orb can come from several relatively simple,
  specialized visual systems interacting through shared state, rather than
  one giant complicated object.

---

## 3. Visual System Breakdown

Proposed decomposition into independently-buildable systems, each a *consumer*
of the shared `EnergyModel`:

1. **Core** — the alien/geometric/morphing centerpiece.
2. **Structural Lattice** — thin rings/curves establishing the orbital
   silhouette.
3. **Energy Field** — the layered translucent "atmosphere" volume(s)
   immediately around the core.
4. **Wisps / Currents** — flowing electromagnetic/computational energy
   strands.
5. **Particle Populations** — several small, distinct-purpose systems (not
   one big system): micro-particles, core sparks, orbital particles,
   directional/burst particles, fragments.
6. **Symbol System** — the hidden-until-revealed Jairus identity.
7. **Camera Rig** — drift/response, separate from all visual systems so it
   can be tuned independently.
8. **Post-Processing / Compositor** — bloom/glow, and any screen-space
   distortion.
9. **Energy Model (non-visual)** — the shared parameter authority everything
   above reads from. This is the architectural spine of the whole system and
   is treated as its own component even though it draws nothing.

This list may reasonably grow (e.g. splitting "Energy Field" into an inner and
outer shell) during prototyping, but nothing here should be *cut* — each maps
to a distinct requirement in the brief.

---

## 4. Godot Technique Mapping

| System | Godot technique | Why | GPU cost | Limitation | Worth using? |
|---|---|---|---|---|---|
| Core | `MeshInstance3D` (icosphere/geodesic base) + custom `.gdshader` with vertex displacement from `FastNoiseLite`/`NoiseTexture2D`, domain-warped **[DOC]** | Only realistic way to get organic-but-geometric deformation without an external DCC modeling workflow | Low-moderate (per-vertex, small mesh) | Vertex density limits deformation detail; true topology change (holes appearing/closing) is not achievable this way | Yes — highest priority |
| Core (alt/optional) | Imported glTF mesh with authored blend shapes (morph targets) **[DOC — Godot supports blend shapes]** | Could add hand-authored "geometric state" morphs | None beyond normal skinning | Requires an external DCC tool (Blender) — brief prefers avoiding this | Low priority / optional supplement only |
| Structural Lattice | `Path3D`/`Curve3D` + a mesh generated from `Curve3D.tessellate()` (tube/ribbon), or a small hand-placed `MeshInstance3D` torus/arc set **[DOC — Curve3D tessellation is a documented API; ready-made tube-from-path is a common community pattern, not a stock node]** | Thin, elegant, curve-driven shapes read as "orbital," not mechanical | Low (few, low-poly meshes) | No stock "ribbon-along-path" node exists in core Godot; must build the mesh once (not per-frame) or use a small addon | Yes |
| Energy Field | 2-3 layered translucent shells (`MeshInstance3D` + alpha-blend shader, Fresnel-driven falloff) **[DOC — Fresnel via `dot(NORMAL, VIEW)` is a standard, well-documented shader pattern]** | Gives the "field" without true volumetrics | Alpha-blended overlapping transparency is *the* known expensive/fragile case in Godot 4 — sorted by AABB center, no order-independent transparency **[DOC]** | Only 2-3 shells, kept small and non-intersecting where possible | Yes, but shell count must stay low |
| Wisps/Currents (option A) | `GPUParticles3D` with `trail_enabled` + `RibbonTrailMesh`/`TubeTrailMesh` **[DOC]** | Built-in, cheap, good for many stochastic strands | Low per-strand | Trail *shape* control is limited to trail length/width curves, not full custom paths | Yes, for the stochastic/many-strand layer |
| Wisps/Currents (option B) | Static tube mesh along a `Curve3D`, shader-animated flow (scrolling UV + noise) | Full artistic control over a small number of "hero" currents | Very low (geometry built once, animated only in shader) | Needs the mesh built once per curve (small one-time CPU cost, not per-frame) | Yes, for a handful of deliberate "hero" currents |
| Particles — micro | `GPUParticles3D`, continuous, low count, additive billboard material | Ambient life at idle | Very low | — | Yes |
| Particles — core sparks | `GPUParticles3D` sub-emitter attached to core **[DOC — sub-emitters spawn at parent-particle positions]** | Sparks that visually originate from the core surface | Low | Sub-emitter disables the target's own independent emission — must be the intended relationship, not accidental | Yes |
| Particles — orbital | `GPUParticles3D` with a custom `ParticleProcessMaterial`/shader driving orbit motion, or particles constrained along the Structural Lattice curves | Reinforces the orbital-ring read | Low-moderate | Orbit-shaped particle motion is hand-rolled (no stock "orbit around point" emission shape) | Yes |
| Particles — directional/burst | `GPUParticles3D` with `one_shot = true`, triggered on state transition events, not continuously running **[DOC — one-shot particle emission is a documented mode]** | Matches the brief's "event-driven, not continuously max" requirement | Low (bursty, not sustained) | Needs a trigger call from the EnergyModel/state controller | Yes |
| Fragments | `MultiMeshInstance3D` for the geometry, small count (single digits to low tens), each instance's transform/animation driven by a script or shader using per-instance custom data **[DOC — MultiMesh batches many instances in one draw call, dramatically cheaper than individual `MeshInstance3D` nodes or GPU particles at any meaningful count]** | "Computational fragments," not debris — needs individual identity/behavior, which MultiMesh custom data supports | Very low at this count | MultiMesh is for repeated *simple* motion; complex per-fragment logic is easier at low counts as plain nodes instead | Yes, MultiMesh if count grows past ~15-20, otherwise plain nodes are simpler |
| Symbol | `Decal` node (projects a texture onto nearby surfaces, real-time, no mesh needed) **[DOC]**, or a `SpotLight3D`/`OmniLight3D` with `light_projector` texture **[DOC]**, combined with a reveal mask driven by a shared `symbol_reveal` uniform | "Emerges from the artifact" rather than sitting on top of it | Low | Decals project onto whatever geometry is beneath them — needs the core's surface to be a reasonable projection target | Yes — needs its own small prototype to pick Decal vs. projector-light vs. core-shader-mask |
| Camera | Plain `Camera3D` under a `Node3D` rig, script-driven sine/noise drift, no stock "cinematic drift" node | Simple and fully controllable | Negligible | — | Yes |
| Post-processing | `WorldEnvironment` (glow/bloom, tonemap — both stock, documented) **[DOC]**; custom `CompositorEffect` for anything bespoke (e.g. a screen-space distortion pass) **[DOC — CompositorEffect is a real Godot 4.3+ API hooking into `RenderingDevice` per-frame]** | Glow is essentially free value for this brief's "energy" look; CompositorEffect covers anything glow/tonemap can't | Glow: low. CompositorEffect: fully custom — cost is whatever you implement | CompositorEffect has a real learning curve (compute-shader-adjacent, `RenderingDevice` API) | Glow: yes, immediately. CompositorEffect: yes, but budget it as its own prototype, not a given |
| Volumetric fog / SDFGI | `FogVolume`/`WorldEnvironment` volumetric fog, SDFGI | Documented, and volumetric fog specifically is described as efficient even on integrated GPUs at default settings **[DOC]** | Fog: low-moderate. SDFGI: "the slower of the two GI systems," with reported real-world stability/performance complaints **[DOC]** | Both are designed for *scene-scale* environmental lighting/atmosphere, not a single small foreground object | **No** — see §20, this is scene-scale machinery for a desk-ornament-sized object; skip |

---

## 5. Proposed Rendering Architecture

Single Forward+ **[DOC]** viewport (this is a desktop-only rendering target;
Forward+ is documented as the renderer suited to desktop platforms with
newer/mid-range-and-up GPUs, which an RTX 3060 laptop is). Render order,
opaque-to-transparent:

1. **Opaque pass**: core base geometry (even though it's shader-displaced and
   emissive, it should be authored as an *opaque* material where possible —
   opaque materials can cast/receive shadows and participate in depth
   prepass, and alpha-blended materials specifically cannot cast shadows and
   are documented as significantly slower, especially when overlapping
   **[DOC]**). Structural lattice (rings/curves) as opaque or near-opaque.
2. **Transparent pass**: the 2-3 energy-field shells, wisp/current geometry,
   symbol decal/projector. Kept to a *small, fixed* number of overlapping
   transparent draws, because Godot 4's transparency sort is AABB-center-based
   and known to misorder with large/overlapping transparent surfaces **[DOC]**
   — this is a hard ceiling on "how many translucent shells," not a stylistic
   preference.
3. **Particles**: rendered additively where possible (additive blending
   sidesteps most of the sort-order problem, since additive results are
   order-independent) — recommended default for micro/spark/orbital/burst
   populations **[REC]**.
4. **Post-processing**: glow/bloom via `WorldEnvironment`, then any custom
   `CompositorEffect` distortion pass last.

No shadows are recommended from the energy/particle layers at all (alpha-
blended materials can't cast them anyway **[DOC]**); if the core needs to cast
a shadow for grounding, that's a single opaque caster, not a system-wide cost.

---

## 6. Scene / Node Architecture

```
JairusOrb (Node3D)
├── EnergyModel (Node)                # owns/smooths shared params, pushes global shader uniforms
├── Core (MeshInstance3D)             # icosphere/geodesic + core.gdshader
├── StructuralLattice (Node3D)
│   ├── RingA (MeshInstance3D)        # built once from a Curve3D tessellation
│   └── RingB (MeshInstance3D)
├── EnergyField (Node3D)
│   ├── ShellInner (MeshInstance3D)
│   └── ShellOuter (MeshInstance3D)
├── Wisps (Node3D)
│   ├── HeroCurrents (Node3D)         # small count, Curve3D-built tube meshes
│   └── StochasticWisps (GPUParticles3D)   # trail_enabled, RibbonTrailMesh
├── Particles (Node3D)
│   ├── Micro (GPUParticles3D)
│   ├── CoreSparks (GPUParticles3D)   # sub_emitter → Core-adjacent emission
│   ├── Orbital (GPUParticles3D)
│   ├── Burst (GPUParticles3D)        # one_shot, triggered on events
│   └── Fragments (MultiMeshInstance3D or plain Node3D pool if count stays low)
├── Symbol (Node3D)
│   └── SymbolDecal (Decal)           # or SpotLight3D with light_projector
├── CameraRig (Node3D)
│   └── Camera3D
└── WorldEnvironment                  # glow; CompositorEffect resource attached here or on Camera3D
```

Design intent: every branch under `JairusOrb` other than `EnergyModel` is a
*pure consumer* — it reads shared parameters and renders; it never owns state
that another branch needs. `EnergyModel` is the only node that will eventually
talk to the outside world (via the existing `bridge.py` WebSocket contract —
see §4/§8 of `RENDERER_BRIDGE.md`: `{"state": str, "level": float, "activity":
str}` on `localhost:8767`). Nothing else in this tree should ever open a
socket or know Jairus exists — that keeps the renderer boundary this repo
already established (Agent Core / Policy Engine / Tool Registry are never
reachable from here) fully intact.

This hierarchy supports the brief's requirements directly: state-driven
behavior (`EnergyModel` → global uniforms), reusable VFX (each particle/wisp
system is a self-contained node), experimentation (any branch can be swapped
without touching others), and parameter tuning (all tunable values live in
one place).

---

## 7. Shader / Material Architecture

Recommendation: several small shaders sharing common logic via `.gdshaderinc`
files, not one mega-shader.

- `include/energy_common.gdshaderinc` — Fresnel function
  (`pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
  power)` **[DOC — standard documented pattern]**), the palette gradient
  lookup (near-white → maroon → gold), and reads of the global shader
  uniforms exposed by `EnergyModel`.
- `core.gdshader` — vertex stage: domain-warped `FastNoiseLite`-driven
  displacement along the normal, magnitude driven by `turbulence`/
  `core_morph`; fragment stage: Fresnel rim + palette + emission driven by
  `intensity`/`coherence`.
- `energy_shell.gdshader` — fragment-only (or very light vertex noise),
  alpha-blended, Fresnel-heavy, driven by `field_strength`.
- `wisp_ribbon.gdshader` — UV-scroll + noise flow along the tube/ribbon
  direction, driven by `activity`.
- `particle_*.gdshader` — one small shader per particle population (micro,
  spark, orbital, burst), sharing the common include but each free to have a
  distinct look.
- `symbol_reveal.gdshader` (or a shader parameter on `Core`/`Decal`) — a mask
  blended in via `symbol_reveal`.

Rationale: this matches the brief's explicit request to avoid "one enormous
impossible-to-maintain shader," while still guaranteeing visual coherence
because every shader pulls from the same include and the same global uniform
set — coherence comes from shared *data*, not shared *code size*.

---

## 8. Particle Architecture

| Population | Technique | Continuous or event-driven | Notes |
|---|---|---|---|
| Micro | `GPUParticles3D`, low count, additive billboard | Continuous, low-intensity always | Present even at `OFFLINE`? — recommend near-zero, not literally zero, so `OFFLINE` still reads as "the object exists" (open question, see §21) |
| Core sparks | `GPUParticles3D`, `sub_emitter` targeting Core's surface | Continuous trickle + burst on `THINKING`/`EXECUTING` | Sub-emitter relationship means this population's own base emission should be disabled by design, not left as a leftover default **[DOC]** |
| Orbital | `GPUParticles3D`, custom process shader constraining motion to orbital paths (or literally following `StructuralLattice` curves via `PathFollow3D`-driven per-particle logic if per-particle path-following proves necessary) | Continuous, density scales with `activity` | Highest-effort population to get looking non-random; budget real prototyping time here |
| Burst/directional | `GPUParticles3D`, `one_shot = true`, triggered from `EnergyModel` on state-transition events (e.g. entering `SUCCESS`, entering `EXECUTING`) **[DOC]** | Event-driven only | This is the direct implementation of the brief's "should be event-driven, not continuously running at maximum" instruction |
| Fragments | `MultiMeshInstance3D` if count > ~15-20, else a small pool of plain nodes | Continuous, slow, driven by `coherence` (more coherent = more "in formation") | Do not default to GPUParticles3D here — fragments need individual, recognizable identity, which is exactly what large-scale GPU particle systems are bad at and MultiMesh/plain-nodes are good at |

Population *count* itself is deliberately small (five) and each has one job,
directly following the brief's "particles should have distinct visual jobs
rather than being one giant particle system" instruction.

---

## 9. Core Morphing Strategy

This is the highest-design-risk system in the whole document, because it's
the one place the brief has no fallback ("it should not simply be a sphere
that rotates") and Godot has no turnkey feature for "alien geometric
morphing."

Recommended approach, in order of what to build first:

1. **Base geometry**: a subdivided icosphere/geodesic (enough vertex density
   for displacement detail, not so much it's a GPU cost driver — this exact
   count needs empirical tuning, not a guess).
2. **Displacement**: vertex-shader offset along the normal, magnitude and
   frequency driven by a **domain-warped** `FastNoiseLite` sample (domain
   warp produces the "liquified"/organic-but-directed distortion rather than
   generic bumpy noise — this is a documented, real noise-warp mode, not an
   invented capability **[DOC]**).
3. **"Morph" as parameter-driven noise-field crossfade**, not literal topology
   change: drive 2-3 *different* noise configurations (different frequency/
   warp-strength/seed) and `mix()` between their displacement outputs based on
   `core_morph`. This reads as the core shifting between distinct "geometric
   states" without requiring actual mesh topology changes, which Godot cannot
   do cheaply at runtime.
4. **Blend shapes are a documented, real Godot capability** for true authored
   morph targets **[DOC]**, but require modeling them in an external DCC tool
   and importing via glTF — this conflicts with the brief's preference for
   approaches achievable without an external modeling workflow, so this
   document recommends treating blend shapes as an optional *later*
   supplement, not the primary technique.
5. Secondary high-frequency micro-displacement layer (a second, smaller-scale
   noise sample) for surface detail that reads as "computational activity"
   distinct from the primary morph — this is where `THINKING`/`EXECUTING`'s
   "complex computational activity" requirement should mostly live.

This system should be the **first thing prototyped** (see §19) because if
noise-driven displacement alone can't achieve "alien" rather than "blobby,"
that finding changes the whole document's assumptions.

---

## 10. Jairus Symbol Strategy

Three real, documented candidate techniques, not mutually exclusive:

1. **`Decal` node** — projects a texture onto nearby geometry in real time,
   no mesh required **[DOC]**. Project the symbol onto the core's surface;
   drive its visibility/opacity via `symbol_reveal`. Simplest to implement,
   most literal "projection" look.
2. **Light projector texture** on a `SpotLight3D`/`OmniLight3D`
   (`light_projector` property) **[DOC]** — makes the symbol read as *light
   the object is emitting/shaping* rather than a texture stamped on a surface,
   which may better match "emerges from the intelligence." Can even drive the
   projector from a `SubViewport` render for animated reveal patterns
   **[DOC — supported, though flagged in Godot's own issue tracker as having
   real-world performance/update-timing rough edges when the projector source
   updates dynamically]**.
3. **Core-shader emissive mask** — bake the reveal directly into
   `core.gdshader` as a masked emission boost, driven by `symbol_reveal` and
   possibly the same noise fields already driving displacement (so the symbol
   looks like it's *assembling from* the core's own geometry/energy, not
   independently overlaid).

**Recommendation [REC]**: prototype (3) first — it has zero extra nodes,
composes naturally with the "emerges from the artifact" requirement, and
reuses machinery already being built for the core. Fall back to (1)/(2) only
if the shader-mask approach can't read clearly enough at small size.

---

## 11. Energy / Wisp Strategy

Comparing the real candidates:

| Approach | Control | Cost | Best for |
|---|---|---|---|
| `GPUParticles3D` + `trail_enabled` + `RibbonTrailMesh`/`TubeTrailMesh` **[DOC]** | Stochastic, limited per-strand shaping (length/width curves only) | Low | Many small, organic, less-deliberate currents |
| Static tube mesh along `Curve3D`, shader-driven flow | Full artistic control of path shape | Very low (built once) | A small number of "hero" currents whose exact path matters |
| Procedural ribbon regenerated every frame (`SurfaceTool`/`ImmediateMesh`) | Full control, fully dynamic paths | Moderate-high (CPU geometry rebuild per frame) | Only if currents must *change path* at runtime, not just flow along a fixed path |
| Curve3D + community/addon path-mesh tools (e.g. tube-from-path patterns) **[DOC — the technique (Curve3D.tessellate) is documented; a ready node is typically an addon, not stock]** | Same as static tube above, less manual mesh-building | Low | Same as static tube, faster to iterate |

**Recommendation [REC]**: hybrid — a handful (3-6) of static, Curve3D-built
"hero" tubes with shader-driven flow for the deliberate structural currents,
plus `GPUParticles3D` trails for the stochastic secondary wisps. Avoid
per-frame procedural geometry regeneration unless a prototype proves the
paths genuinely need to change shape at runtime (not just flow/pulse), since
that's the most expensive option for a benefit ("currents" per the brief are
described as flowing along stable field lines, not reshaping every frame).

---

## 12. Shared Energy Model

Central `EnergyModel` node, single source of truth for these parameters
(names/ranges are this document's proposal, not fixed):

| Parameter | Range | Meaning | Smoothing |
|---|---|---|---|
| `intensity` | 0-1 | Overall brightness/emission level | Fast |
| `activity` | 0-1 | General energy motion speed (wisps, particles) | Medium |
| `turbulence` | 0-1 | Core displacement chaos | Medium |
| `coherence` | 0-1 | How "organized"/converged vs. loose the field looks | Slow |
| `pulse` | 0-1, cyclic | Synchronized pulse signal (e.g. `SUCCESS`) | Event-driven, not smoothed |
| `core_morph` | 0-1 | Crossfade between core noise-field configurations | Slow |
| `field_strength` | 0-1 | Energy-shell opacity/thickness | Medium |
| `particle_activity` | 0-1 | Density/speed multiplier for continuous particle populations | Medium |
| `symbol_reveal` | 0-1 | Symbol visibility | State-driven, mostly held at 0 |

**Mechanism [DOC]**: `EnergyModel` maps incoming Jairus state → a target
profile (a dictionary of target values for the table above), exponentially
smooths current values toward targets every frame at per-parameter rates, and
pushes them via `RenderingServer.global_shader_parameter_set()` to global
shader uniforms declared with the `global` keyword in each shader and
registered in Project Settings → Shader Globals. This is a real, documented
Godot 4 mechanism specifically designed for "one value, many materials" —
exactly this use case — and is why every consumer system in §6 needs no
direct reference to `EnergyModel` at all; they just declare the global
uniform and read it. One caveat confirmed during research: **global uniforms
do not support arrays** **[DOC]** — if any parameter ever needs to be an
array (e.g. a per-fragment set of values), it must be encoded into a small
texture and passed as a global sampler instead, not as a global array
uniform.

Non-shader consumers (e.g. the particle populations' emission rates, or
`CameraRig`'s response) read the same values directly off `EnergyModel`
via ordinary node references/signals, since `GPUParticles3D` process-material
parameters aren't shader uniforms in the same sense.

---

## 13. State Visual Profiles

| State | intensity | activity | turbulence | coherence | field_strength | particle_activity | symbol_reveal | Notes |
|---|---|---|---|---|---|---|---|---|
| `IDLE` | low-mid | low | low | mid | mid | low | 0 | Calm, mysterious, controlled |
| `LISTENING` | mid | mid | low-mid | rising | mid-high | mid | low (hint) | Energy becomes convergent/organized — coherence rises sharply relative to IDLE |
| `THINKING` | high | high | high | mid (structured, not chaotic) | high | high | 0-low | "Complex computational activity" — turbulence up, but coherence held mid so it stays "structured and controlled" per the brief |
| `EXECUTING` | max | max | high | high (never collapses to chaos) | max | max | context-dependent | Max visual complexity; coherence deliberately kept high even at max intensity — this parameter choice is the mechanism for "overwhelming power under perfect control" rather than "about to explode" |
| `SUCCESS` | pulse to max then settle | drops toward idle | drops | max (briefly) | mid | brief burst then settle | brief 1 (symbol reveal) | `pulse` event fired once; gold-accent channel opened briefly (see §14) |
| `ERROR` | reduced | reduced, uneven | mid (interruption, not smooth) | low (deliberately reduced) | reduced | reduced | 0 | Reduced coherence is the mechanism for "reduced coherence, interruptions, temporary asymmetry" without touching color/red-danger tropes |
| `OFFLINE` | near-zero | near-zero | 0 | n/a | near-zero | near-zero | 0 | Distinct from `IDLE`, not just "IDLE but dimmer" — recommend also disabling the CameraRig drift, not only the energy parameters, so it reads as inactive rather than idle |

Every state change is expressed as a **different target vector across
multiple parameters**, never a single color swap — directly satisfying the
brief's "avoid making state changes depend solely on color" instruction.

---

## 14. Camera Strategy

Plain `Camera3D` under a `CameraRig` `Node3D`. Drift implemented as
low-frequency noise or summed sine offsets on position/rotation — deliberately
*not* a constant orbital spin, matching "should not look like a constantly
spinning showcase object." Drift amplitude/speed reads from `activity`, so
`EXECUTING` gets slightly more camera energy than `IDLE`, but the *base*
behavior (subtle, irregular) stays present at every state, including
`OFFLINE` (at zero amplitude, effectively frozen). FOV: fixed, modest
perspective; no aggressive lens effects unless a later design pass asks for
them (out of scope here per the "no implementation ideas beyond what's needed
to explain the boundary" instruction).

---

## 15. Color / Material Strategy

- **Near-white**: primary emission channel — core's dominant energy color,
  brightest particle populations, wisp cores.
- **Maroon**: structural/depth — rim shadows, the core's non-lit facets,
  energy-shell falloff at low `field_strength`. The brief specifies maroon
  should become *more* apparent at higher energy states, which maps naturally
  to driving maroon's presence off `turbulence`/`intensity` rather than
  treating it as a static "shadow color" — i.e., more visible internal
  structure becomes exposed as the core gets more active, not less.
- **Gold**: reserved, driven almost exclusively by `symbol_reveal` and the
  `SUCCESS` `pulse` event. Implementation: a dedicated emission channel/
  uniform that stays at 0 except during those two triggers, rather than a
  blend that could accidentally bleed gold into other states.

Recommend a single shared `Gradient`/color-ramp resource (or a small baked
gradient texture passed as a global shader sampler) sampled by every shader
via the common include, so "near-white → maroon → gold" is defined in exactly
one place and every system stays in the same palette by construction, not by
convention.

---

## 16. Performance Strategy

Ranked candidate bottlenecks for a 6 GB RTX 3060 Laptop GPU target, most to
least likely:

1. **Overdraw from layered transparency** (energy shells + wisps + particles
   all overlapping in screen space) — documented as the specific case Godot 4
   handles worst (sort artifacts, no shadow casting, "significantly slower...
   especially if they overlap") **[DOC]**. This is the #1 thing to measure
   early, not late.
2. **Particle population count vs. technique choice** — the research found a
   striking documented data point: roughly 1M MultiMesh instances held ~144
   fps where 1M GPU particles ran at ~1 fps in the same comparison **[DOC]**.
   This orb's particle counts will be far smaller than either extreme, but it
   confirms the architectural choice in §8 (MultiMesh for fragments, small
   dedicated `GPUParticles3D` populations rather than one huge one) is sound
   in principle, not just stylistically tidy.
3. **CompositorEffect / custom post-processing cost** — entirely dependent on
   what gets implemented; budget it as its own measured item, not assumed
   free.
4. **Shadow cost** — recommended near-zero by design (§5), so this should be
   a non-issue if the architecture is followed.
5. **Render resolution** — since this is a small UI-scale object (not a
   full-screen scene), rendering it into a modest-resolution `SubViewport`
   sized to its actual on-screen footprint (rather than native display
   resolution) is a straightforward, high-leverage lever if overdraw proves
   costly **[REC]**.

**Recommended process**: build ambitious first, then measure with Godot's
built-in profiler/monitors and GPU-level tools (an RTX card makes NVIDIA
Nsight Graphics a real option) rather than guessing which system is
expensive — this matches the brief's own stated development philosophy.

---

## 17. Godot Technical Constraints

- **Transparent per-pixel desktop window**: real and documented — requires
  `display/window/size/transparent`, `display/window/per_pixel_transparency/
  allowed`, and `rendering/transparent_background` all enabled **[DOC]**.
  Windows draws only the per-pixel-alpha region; on Linux/macOS the
  out-of-region content is described as still drawn, an OS-level difference
  worth knowing about if this ever targets non-Windows **[DOC]**.
- **True desktop refraction is very unlikely to work**: Godot's
  screen-reading shaders (`SCREEN_TEXTURE`, used for the standard refraction/
  distortion technique) capture *what Godot itself rendered this frame*, not
  the real OS desktop compositor's output behind a transparent window. Where
  the window is transparent, there is nothing in `SCREEN_TEXTURE` to distort
  **[INFER — not found stated explicitly in Godot docs, but a direct
  consequence of how `SCREEN_TEXTURE` and OS-level window compositing work;
  treat as unconfirmed until tested in a throwaway prototype]**. What *is*
  achievable: faking refraction/distortion against Godot's own rendered
  content (other parts of the orb scene, or a solid/semi-opaque backing
  plate), which is the standard, well-documented screen-space distortion
  technique **[DOC]**.
- **Transparency sorting**: no order-independent transparency in Godot 4;
  sorting is by object AABB center, which is documented to fail for large or
  intersecting transparent surfaces **[DOC]**. Directly constrains §5's "small
  fixed number of shells" rule.
- **Alpha-blended materials cannot cast shadows and are excluded from
  screen-space reflections** **[DOC]** — already assumed in §5.
- **CompositorEffect requires `RenderingDevice`-level GDScript/C#** — real
  and documented, but a genuinely steeper API than material/shader authoring
  **[DOC]**. Treat as a scoped, separately-budgeted prototype, not something
  to reach for casually.
- **Volumetric fog / SDFGI** are scene-scale systems with their own
  documented caveats (SDFGI specifically flagged as the slower GI option with
  real reported stability issues) **[DOC]** and are architecturally the wrong
  tool for a single small foreground object regardless of performance — see
  §20.
- **Global shader uniforms do not support arrays** **[DOC]** — noted in §12,
  relevant if any future parameter needs to be array-shaped.

---

## 18. Risk Register

| Risk | Probability | Impact | Mitigation | Prototype early? |
|---|---|---|---|---|
| Transparent window + heavy internal transparency/distortion don't compose as hoped (real desktop can't be refracted; interaction with OS compositor untested) | Medium-high | High — affects the whole "floating artifact" presentation model | Build the actual transparent-window + one distorted transparent object test *before* any other visual work | **Yes — first or second prototype** |
| Noise-driven core displacement doesn't read as "alien," reads as "blobby sphere" | Medium | High — core is the brief's most important element | Time-box a dedicated core-shader prototype; be willing to try multiple noise configurations/domain-warp settings before judging | **Yes — highest priority** |
| Layered-transparency overdraw exceeds budget once shells+wisps+particles all render together | Medium | Medium-high | Measure early with even placeholder geometry; enforce the "small fixed shell count" rule from the start, not as a later fix | Yes, once basic scene exists |
| Symbol-reveal technique doesn't read as legible/recognizable at the orb's actual on-screen size | Medium | Medium | Prototype at true target window size, not a full-screen editor view | Yes |
| Wisp technique choice (particles-trail vs. Curve3D-tube) picked wrong for the desired "hero current" look | Low-medium | Low-medium (reversible) | §11's small dedicated comparison prototype before committing scene structure | Yes |
| CompositorEffect complexity balloons scope for a "nice to have" distortion pass | Medium | Low (skippable) | Treat as optional/late; ship without it if it's not converging | No — defer |
| Fragments-as-MultiMesh feels mechanical/repetitive rather than "computational" at low counts | Low | Low | Plain-node fallback already identified in §8/§20 | No — cheap to switch later |

---

## 19. Recommended Development Order

1. **Transparent-window + minimal scene smoke test.** One opaque mesh, one
   transparent mesh, confirm the presentation model (transparent per-pixel
   window, or a normal bordered window — this choice isn't made yet, see
   §21) actually works and look for the `SCREEN_TEXTURE`/desktop-refraction
   constraint from §17 directly, empirically.
2. **`EnergyModel` + global-shader-uniform pipeline**, driven by a temporary
   debug UI (sliders), *before* wiring the real `bridge.py` WebSocket client.
   Proves the state-driven architecture independent of Jairus integration.
3. **Core shader prototype** (displacement + Fresnel + emission), driven live
   by the debug sliders from step 2. Highest design risk in the whole
   project — the largest time allocation should go here.
4. **Wisp technique decision prototype** (§11): build both candidates small,
   pick one, discard the other.
5. **Structural lattice + energy-field shells**, checked immediately against
   the overdraw budget from §16/§18.
6. **Particle populations**, added one at a time in the order given in §8
   (micro → sparks → orbital → burst → fragments), each checked against the
   shared model before adding the next.
7. **Symbol-reveal prototype** (§10), at true target on-screen size.
8. **Post-processing**: glow first (cheap, likely high value), CompositorEffect
   distortion only if time/complexity budget allows.
9. **Camera drift.**
10. **Benchmark pass**: real frame-time measurement on the actual RTX 3060
    laptop target, resolution/overdraw tuning against real numbers, not
    assumptions.
11. **Wire the real `EnergyModel` ↔ `bridge.py` WebSocket client**, replacing
    the debug sliders, using the exact `{"state","level","activity"}` contract
    already documented in `RENDERER_BRIDGE.md`.

Rationale for this order: every step that carries genuine technical
uncertainty (1, 3, 4) happens before any step that's mostly "assemble known-
good pieces" (5, 6, 9). Real Jairus integration is deliberately last, since
nothing about the visual system needs it to be real until the visuals
themselves are proven.

---

## 20. High-Value vs. Experimental vs. Low-Value Techniques

**High-value** (directly and efficiently serves the brief):
- Shared `EnergyModel` + global shader uniforms — the architectural
  foundation; without it, "one living system" isn't achievable regardless of
  what else is built.
- Fresnel rim shading across core/shells — cheap, and does most of the work
  of making translucent/energy surfaces look "energetic" rather than flat.
- Noise-driven (domain-warped) core vertex displacement — the only realistic
  path to "alien/morphing" without external modeling.
- `GPUParticles3D` with trails/sub-emitters for wisps and sparks — cheap,
  documented, does a lot of visual work per unit of effort.
- `MultiMeshInstance3D` for any repeated element — dramatically cheaper than
  the naive alternative at essentially no artistic cost.
- `WorldEnvironment` glow — likely the single best fidelity-per-GPU-cost item
  available for an "energy artifact" brief.
- One-shot/event-driven particle bursts tied to state transitions — directly
  implements the brief's explicit "event-driven, not continuously max"
  instruction.

**Experimental** (worth testing because pushing Godot is an explicit goal,
but outcome genuinely uncertain):
- Symbol reveal via `Decal`/light-projector vs. shader mask — real feature,
  unclear which reads best at target size until tried.
- Domain-warped multi-noise-field core morphing — the core mechanism this
  whole design leans on, and also the least precedented piece.
- `CompositorEffect`-based custom distortion — real capability, real
  complexity cost; worth trying once the foundation is solid, not before.
- Faked (Godot-content-only) screen-space distortion for an "atmosphere"
  layer — plausible, but its visual payoff vs. its transparency-sort
  interaction (§17/§18) needs to be seen, not assumed.

**Low-value / recommend skipping**:
- **Volumetric fog / SDFGI** — architecturally scene-scale tools applied to a
  single small foreground object; even where individually "efficient," they
  solve a problem (large-scene atmospheric/global illumination) this project
  doesn't have. Skip.
- **True desktop refraction** — very likely not achievable given how
  `SCREEN_TEXTURE` and OS window compositing interact (§17); don't design
  around it.
- **Per-frame procedural ribbon geometry regeneration** — real capability,
  but the brief's "currents" read as flowing-along-stable-paths, which the
  much cheaper static-tube-plus-shader-flow technique already covers; the
  extra CPU cost buys a capability (paths that reshape every frame) nothing
  here needs.
- **Very high raw particle counts as a substitute for MultiMesh/careful
  design** — the documented 1M-particles-vs-1M-MultiMesh gap (§16) shows
  "more particles" is not a free way to add visual density; it's specifically
  the wrong tool once counts get large.
- **A single mega-shader** — explicitly against both this document's §7
  recommendation and general maintainability; the brief also asked to avoid
  this directly.

---

## 21. Open Questions / Decisions Still Needed

These are decisions for the next design phase, not answered here:

1. **Wisp technique**: Curve3D-tube vs. GPUParticles-trail for the "hero"
   currents specifically (§11) — needs a side-by-side prototype, not a
   guess.
2. **Presentation model**: is this genuinely a per-pixel-transparent overlay
   window floating on the desktop, or a normal bordered/backgrounded window
   embedded in the existing Qt shell (`orb_widget.py`'s visual slot, per
   `RENDERER_BRIDGE.md`)? This materially changes §17's refraction
   constraint and the whole "atmosphere" layer's achievable look, and should
   be settled early (it's step 1 of §19 for exactly this reason).
3. **Core base topology**: how many subdivisions on the base geodesic, and
   whether any hand-authored blend-shape geometry ever gets added as a
   supplement (§9 item 4) — an empirical/artistic call, not a research one.
4. **"Unknown intelligence inside" — does the design need actual visible
   interior structure** (something seen *through* the outer energy layers),
   which would push §5's shell-count budget harder than a purely-surface
   treatment would? Affects the overdraw budget directly.
5. **Target window/render size** — needed to size the `SubViewport`
   resolution recommendation in §16 concretely, and to judge symbol
   legibility in §10.
6. **State-transition smoothing vs. snapping**: §12 assumes smoothed
   interpolation for most parameters, but whether *state itself* should ever
   snap instantly (vs. `level`, which `bridge.py` already sends as a smooth
   float) is a design call, not fixed by this document.
7. **`OFFLINE` vs `IDLE` particle floor**: whether `OFFLINE` should be
   literally zero-activity or a near-zero "still exists, just dormant" floor
   (§8/§13 flagged this as unresolved).

---

## 22. Final Technical Recommendation

Build the **foundation** first — `EnergyModel` plus the global-shader-uniform
pipeline plus a core-shader prototype — before committing to any of the
surrounding systems, because the two highest-uncertainty items in this entire
document (whether noise-driven displacement reads as "alien," and whether the
intended transparent-window presentation model actually supports the layered-
transparency/distortion look the brief wants) both live in that foundation,
not in the particle/wisp/fragment layer that makes up most of the node count.
Everything in §4's technique table for those surrounding systems is genuinely
low-risk, documented, standard Godot 4 usage — the risk in this project is
concentrated, not spread evenly, and development order should reflect that
concentration rather than building breadth-first. Explicitly deprioritize or
skip volumetric fog/SDFGI and true desktop refraction (§20) — both are either
the wrong tool for this object's scale or unlikely to be achievable as
imagined, and neither is load-bearing for the brief's actual requirements.
