# Orb V2 — Visual Architecture Design

## Status: Design/investigation only — zero code, shaders, or scene files changed

This document answers the 14 questions posed for Orb V2 and proposes an
implementation sequence. **Nothing in `src/jairus/interfaces/renderer/
godot_project/` or anywhere in the Python codebase was touched to produce
this document.** It is grounded in:

- `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md` (the visual target),
- `ORB_RENDERER_INVESTIGATION.md` (architecture decision, Fresnel-not-
  refraction finding, transparency-sorting risk, performance headroom),
- `ORB_CONCEPT_GAP_ANALYSIS.md` (V1's original state and the reasoning
  that produced Pass A1),
- `ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md` and `ORB_VFX_TECHNIQUE_
  ANALYSIS.md` (the plate/crystal and billboard/noise technique work),
- direct inspection of every PoC folder's real code and the shaders they
  produced (`glass_poc_*`, `silhouette_poc_test.*`, `facet_poc_test.*`,
  `vfx_technique_poc_test.*`, `orb_glass_shell.gdshader`,
  `orb_arc_ribbon.gdshader`, `orb_energy_wisp.gdshader`),
- and — critically — **my own hands-on, real-screenshot-verified findings
  from the three most recent implementation passes** (plate silhouette/
  material/facet tuning, camera tilt, billboard wisps), which surfaced
  several concrete problems no prior document had named. Those findings
  drive several of the calls below more than the documents do, and are
  cited by pass name where relevant.

The reframe is taken at face value: V1's *visual* scene is treated as a
reference prototype, not a floor. Every "keep as-is" call below is made
because the evidence supports it, not because rebuilding is out of
scope — and every "discard" call is made because the evidence (often the
project's own prior self-diagnosis) supports that too.

---

## Before the design: what the evidence actually says about V1

This matters because the brief explicitly asks this document to be
willing to make hard calls, not default to "keep everything." Three
sources of evidence, weighed together:

1. **The original gap analysis** named the core problem precisely: every
   visible element in V1-at-that-time was "a smooth, complete,
   mathematically perfect sphere/torus/ellipsoid, differentiated from
   each other only by size, tilt, and color" — the literal "nested
   glowing spheres" anti-pattern the design doc opens by rejecting.
2. **Passes A1/A2/B/E fixed real, specific instances of that problem**
   (a dark housing + emblem where there was only a sphere; segmented
   rings where there was only a smooth torus; a continuous ribbon wave
   where there was only a binary flicker; three particle roles where
   there was only one). These are genuine, verified wins — human-
   confirmed for the ribbon, regression-tested every pass since for the
   core hierarchy.
3. **But the underlying organizing principle never actually changed.**
   Every one of those fixes made an existing concentric band *less
   uniform* — it did not stop the scene from being organized as "several
   independent bands at different radii around one shared center."
   RingA and RingB never interact with each other's geometry. The 4
   glass shells never interact with the plates. The plates never
   interact with the rings. Nothing in V1, at any point in its history,
   was ever positioned *relative to* anything other than the shared
   origin. This is the one gap no prior pass named explicitly, and it is
   the central thesis of this design's Q3 answer.

Additionally, my own three most recent passes surfaced problems no
document had caught before, because they involved pixel-level
verification the earlier passes didn't do:

- **Two of three plates are steeply angled relative to the current
  camera and read as washed-out/invisible specifically in high-bloom
  states** (confirmed by direct pixel sampling at their exact screen
  position, present even in the already-committed prior pass — not a
  regression I introduced, a pre-existing interaction between Pass B's
  `rotation_deg` values and the later camera-tilt pass that nobody had
  checked at the pixel level before).
- **The billboard energy wisps, even after fixing a real noise-frequency
  bug, read as "soft light patch" more than "electromagnetic field" at
  normal viewing scale** — a partial, not decisive, win, honestly
  reported at the time.
- **`NoiseTexture2D` frequency has to be retuned per object screen-size**
  — a general lesson (confirmed twice now, once for the core noise PoC,
  once for the wisp shader) that any future noise use must re-verify
  empirically, never copy a "validated" frequency value across a
  different object size.

Every answer below is written with this actual, evidenced state of V1
in mind — not the aspirational one from prior planning docs.

---

## 1. Distinct visual layers and physical hierarchy

Seven layers, source-to-atmosphere, each with a stated reason to exist:

```
                 JAIRUS EMBLEM            (identity — the one thing that must
                       │                   always be legible, always brightest)
                       ▼
                  CORE ENERGY             (the light source)
                       │
                       ▼
                 CORE HOUSING             (containment — dark, real edge)
                       │
                       ▼
      ┌────────────────┴────────────────┐
      ▼                                  ▼
STRUCTURAL ASSEMBLY  ◄──interlocked──►  ENERGY CONDUITS
(rings/struts/plates,                   (ribbons anchored to
 dark metal + accent                    structural points, not
 glass, mixed depth)                    an independent orbit)
      │                                  │
      └────────────────┬────────────────┘
                        ▼
              PARTICLE ATMOSPHERE        (core sparks close-in →
                        │                 orbital riding the structure →
                        ▼                 ambient dust, outermost)
          BILLBOARD ENERGY PHENOMENA     (sparse, anchored to specific
                                          structural junctions, not
                                          freely orbiting)
```

The key departure from V1's own diagram (which was a straight nested
list: outer field → orbital → glass → core → symbol) is that
**Structural Assembly and Energy Conduits are drawn as one interlocked
unit, not sequential layers** — this is deliberate, and is the answer to
Q3 below. Nothing here is a strict onion; a strut can sit in front of
the housing at one point and behind a ring at another, exactly as a real
assembled object would.

---

## 2. What IS the core

**Preserved from V1's Pass A1, verbatim, plus one scheduled addition.**

- `CoreEmblem`: the procedural 4-point star (`SurfaceTool`, opaque,
  unshaded + emissive), positioned just outside the glow sphere's own
  surface (`EMBLEM_Z_OFFSET`) so the opaque glow sphere can never
  geometrically occlude it. Always the single brightest constant in the
  scene (`CORE_EMBLEM_EMISSION_ENERGY`), always brightened toward white
  relative to the raw state color (`CORE_EMBLEM_BRIGHTEN`) so it reads as
  a distinct mark rather than "more glow."
- `Core`: the glow sphere behind it, second-brightest, pure state color,
  unshaded + emissive, the thing that pulses with breathing/level.
- `CoreHousing`: a dark Fresnel shell (`orb_glass_shell.gdshader`,
  inverted intent — opaque-reading at the rim, transparent at center)
  around both, giving the pair a real, contained silhouette rather than
  a bare glowing ball floating in space.

**Why this triad is not being redesigned**: it is the most specifically-
named requirement in the original design doc (§4), it was the highest-
leverage single fix in V1's entire history (per the gap analysis's own
ranking), and it has survived four independent subsequent passes
(silhouette, material, facets, wisps) with its `core_wins` emission-
hierarchy invariant re-verified and holding every single time, including
by me, personally, three times in a row. There is no evidence anywhere
that this triad has a problem. Touching it without a named reason would
be exactly the "complexity for its own sake" this brief rejects, applied
in reverse.

**One addition, scheduled but not yet built**: `ORB_VFX_TECHNIQUE_
ANALYSIS.md` validated a noise-modulated emission technique for the core
glow sphere (a real `FastNoiseLite` texture animating fine brightness
grain across the surface, confirmed to survive at the core's actual
production emission energy and bloom settings) and explicitly ranked it
**Medium priority — a real, deferred follow-up**, not bundled into the
pass that validated it. V2 is where it finally gets built (see Q7 and
the implementation sequence). Two hard lessons from that investigation
and my own subsequent noise work carry forward as binding constraints on
this addition:
1. Modulate both `ALBEDO` and `EMISSION` — an unshaded material's flat
   `ALBEDO` alone will mask an `EMISSION`-only modulation.
2. **Re-derive the noise frequency empirically for the core's actual
   on-screen size at build time — do not reuse the PoC's `frequency=0.15`
   uncritically.** I found this exact mistake twice already (the wisp
   shader inherited the same "validated" value and it silently failed
   until I dumped the actual baked texture to disk and looked at it).
   The fix each time was the same: bake the texture, look at it directly,
   don't trust a number that was "validated" on a different-sized object.

---

## 3. What surrounds the core, and how it interlocks

This is the central structural redesign, and directly answers the gap
named at the top of this document.

**The rule V1 never broke**: every structural element's position was
parameterized *only* by its own radius/angle/height around the shared
origin. Two elements could differ in tilt or size, but neither was ever
positioned *relative to the other*. That is why, no matter how
segmented or angular any individual band became, the assembly as a whole
never stopped reading as "several independent orbits."

**V2's rule**: at least some structural elements must be positioned
relative to *each other*, not only to the origin, so the assembly reads
as one interlocked machine rather than N independent layers sharing a
center. Concretely, three moves:

1. **Compound, non-shared ring tilts.** V1's `RingA`/`RingB` both use
   the same `RING_TILT_DEG` (only `RingB` gets an extra roll on top).
   V2 gives each ring genuinely independent tilt *axes*, chosen
   specifically so their projected paths visually **cross** one another
   from the camera's view — one ring passing in front of the other at
   one point on screen, behind it at another. This is a real depth-
   crossing read (two rings that look like they're actually
   intersecting, the way two gears or two orbital rings on a real
   mechanical device would), not just "two ellipses of different tilt."
2. **Struts, not free-floating plates.** V1's three plates are each
   parameterized purely by their own `angle_deg`/`radius`/`height` — no
   relationship to the rings at all. V2 replaces this with 2–3 "strut"
   elements (reusing the exact same crystal-shard geometry + real-lit
   rim material technique the plates already validated) that are
   explicitly positioned to *touch or nearly touch* a specific ring
   segment's endpoint at one end, and extend toward the housing at the
   other — a visible physical bridge from the core outward to the
   orbital structure, not debris that happens to share a center. This
   also directly resolves a real problem I found in my own tuning pass:
   two of the three current plates are steeply edge-on to the camera at
   their current independently-chosen angles. Positioning struts
   *relative to* a ring segment's actual endpoint, rather than picking
   an arbitrary angle, removes that failure mode by construction — the
   strut's orientation is now derived from a real anchor point, not a
   third independently-guessed number.
3. **A ring segment allowed to pass in front of a strut at one point
   and behind it at another.** This is the actual "interlocking" read —
   achieved for free once (1) and (2) are true, since compound tilts and
   anchored struts naturally produce crossing depth relationships; it
   does not need a fourth new technique.

**What does NOT change**: the segmented-ring *technique* itself (partial
arcs with gaps, independent per-segment rotation via `speed_factor` and
`segment_spread`) is exactly right and stays. Only the *placement*
relationship between rings and struts changes.

---

## 4. Silhouette test — does it hold with bloom/particles/secondary effects reduced?

**Explicit rule for V2, applied to every element before it ships, not
just asserted afterward**: an element's silhouette must be defined by
either (a) a genuinely opaque material, or (b) a translucent material
with base alpha high enough to read *without* emission/bloom. Never by
bloom alone.

This matters because V1 already has one element that fails this test
today and has never been checked against it: the 4 glass shells use
`GLASS_CORE_ALPHA = 0.06` — a deliberately near-invisible body, by the
scene's own existing code comments, that exists *only* to carry a
Fresnel rim brightened by emission. Turn bloom off, and that rim mostly
disappears too, since `EMISSION = base_color * fresnel * 2.0` is the
only thing making the rim visible in the first place — there is no
meaningful non-emissive alpha silhouette left. This is a real, testable
prediction, not a guess, and it is one of the concrete reasons Q14
recommends discarding the 4-shell system rather than tuning it further.

**What passes this test in V1 today**: the housing (opaque-reading rim,
real geometry), the plates (fully opaque `StandardMaterial3D`), the
segmented rings (translucent but with real alpha independent of
emission — `ring_opacity` floors around 0.1–0.6 depending on state, not
near-zero). These carry forward as the silhouette-defining elements in
V2; the new struts (Q3) and any new glass/crystal accents (Q14) are
required to pass the same test before they ship — checked the same way
V1 checked `PLATE_CONFIGS`' worst-case reach: a real screenshot with
`glow_intensity`/`glow_strength` and particle `amount_ratio` temporarily
forced to near-zero, confirming the assembly still reads as a coherent
shape.

---

## 5. Real 3D depth (not glow alone)

Four concrete mechanisms, in order of how much V1 is currently missing
each one:

1. **Genuine occlusion (largely missing in V1).** Almost nothing in V1
   is opaque and large enough to occlude anything else — the housing
   occludes the emblem's back, and that's essentially it. V2's struts
   (Q3), being real opaque geometry anchored near ring segments, will by
   construction occlude parts of rings/other struts from many camera
   angles. This is checked visually, not assumed: at least one screenshot
   angle must show a strut's silhouette actually cutting into a ring's
   visible arc.
2. **Varied scale at varied apparent depth (missing in V1).** V1's
   plates/shells are all roughly the same order of magnitude regardless
   of radius. V2's struts and glass accents should vary in *scale*, not
   just position — an element nearer the camera's side of the assembly
   should be noticeably larger than one further around, reinforcing
   depth the way real perspective does, rather than every element being
   sized only for its own local prominence.
3. **Real camera parallax (completely missing in V1).** V1's camera has
   never moved, in any state, in the project's entire history — the
   recent tilt pass added one *static* off-axis angle, which helps rings
   read as elliptical but produces zero parallax over time. V2 adds a
   slow, continuous, small-amplitude idle drift (a few degrees of
   oscillating yaw/pitch, long period, same `rotate_x`/`rotate_y`
   primitives already used everywhere in this codebase — no new
   technique). This is cheap, and it is the one depth mechanism the
   *original* design doc asked for (§11, "parallax where appropriate")
   that V1 never actually built.
4. **Fresnel self-brightening (already present, kept as secondary).**
   The glass/housing rim-brightening-at-grazing-angles effect is real and
   worth keeping, but per Q4 it must never be the *only* depth or
   silhouette cue for an element — it's reinforcement, not foundation.

---

## 6. What provides "energy," and how it interacts with structure

**Two conduits, deliberately different in character, one of them now
relational instead of independent** — this preserves the original
design doc's own structural-vs-energy contrast (§6) while fixing the
"orbits around, never through" gap:

- **Conduit A (structure-anchored)**: reuses `orb_arc_ribbon.gdshader`
  verbatim (the traveling-brightness-wave technique is human-confirmed
  working and needs no change), but its path's two endpoints are now
  derived from two of the new struts' actual anchor points rather than
  a free-floating `ARC_RADIUS` constant. This is what makes energy read
  as "flowing between the machine's own components" instead of "a
  ribbon that happens to share the core's center."
- **Conduit B (circulating)**: keeps V1's existing independent orbital
  arc largely as-is, for contrast — not everything needs to be anchored,
  and a purely circulating ribbon is a legitimate, different visual
  statement ("ambient energy moving around the whole assembly") next to
  a structural one ("energy flowing through a specific joint").
- **Billboard energy phenomena** (see Q11/Q14): repositioned from V1's
  freely-orbiting radius band to specific structural junctions — a ring
  segment's gap, or a strut's connection point — read as energy leaking
  or arcing at a mechanical seam, not a decorative halo drifting past
  the structure. This directly answers a real problem I found in my own
  most recent pass: the wisps' generic "soft glow patch" read was partly
  a consequence of them not being tied to anything specific to look
  like they belong to.

---

## 7. Micro-detail at close range without normal-range clutter

Two candidates, ranked by confidence:

1. **Core surface noise-modulation (high confidence — already
   validated, just deferred).** Per Q2: a fine, animating brightness
   grain on the core's own surface, invisible as "extra clutter" at
   normal viewing distance (it reads as texture on an existing bright
   surface, not a new shape) but genuinely present under close
   inspection or in a larger capture. This is the primary Q7 answer.
2. **A subtle housing panel-line/edge-highlight detail (lower
   confidence, explicitly optional).** A cheap, low-contrast procedural
   detail on `CoreHousing`'s surface that would only be perceptible at
   close range. I am flagging this honestly as a "nice if time permits"
   item, not a committed V2 deliverable — unlike the core noise, nothing
   has validated this specific idea yet, and per this brief's own
   standing rule, every layer needs a *stated, evidenced* reason to
   exist, not a plausible-sounding one. If pursued, it should get its
   own small PoC and real-screenshot check before landing, same
   discipline as everything else in this project's history.

**Explicitly not pursued for Q7**: increasing plate/strut facet count
beyond what the facet-scale investigation already established. That
investigation directly measured the perceptibility floor for the
plates' current on-screen size and found the existing facet count is
already near that floor — adding more, finer facets for "close-up
detail" would only reintroduce the exact problem that investigation
existed to fix (facets too small to read), for a viewing distance this
renderer's actual 480×480 desktop-overlay window doesn't naturally
invite anyone to use.

---

## 8. Material palette

**Preserve V1's three-family system as the organizing principle** — this
is one of the genuine, hard-won wins of the silhouette/material passes,
and it already achieves exactly what this question asks (materials that
stay distinct rather than converging to "one glowing blue material"):

| Family | Shading | Members (V1 today) | Members (V2 additions) |
|---|---|---|---|
| **Energy** (unshaded, emissive, flat) | `SHADING_MODE_UNSHADED` + `emission_enabled` | Core, CoreEmblem, rings, arcs, particles | New struts' energy conduit endpoints (the conduit itself, not the strut) |
| **Glass/Fresnel** (unshaded, view-angle-driven) | `orb_glass_shell.gdshader` | CoreHousing, 4 glass shells | 1–2 replacement glass/crystal accents (Q14) |
| **Dark metal** (real-lit, shaded) | `StandardMaterial3D`, metallic/roughness/rim, real light response | 3 plates | New struts (same technique, new positions) |

**Binding rule for V2**: any new element is assigned to one of these
three existing families based on its intended character. A fourth
material family is only introduced if a new element genuinely cannot be
served by any of the three — and per the VFX reference doc's own
explicit "reject further Fresnel expansion" precedent, the default
answer to "should this get a new material recipe" is no.

---

## 9. Color hierarchy

Not just "the state color," but a deliberate brightness/saturation
gradient across layers, preserved and extended from V1's existing
(correct) pattern:

1. **Emblem**: state color lerped toward white (`CORE_EMBLEM_BRIGHTEN`)
   — the single most saturated-toward-white, brightest point, always,
   regardless of state. This is deliberate: identity must read the same
   way in every state, not just "whatever color is loudest."
2. **Core glow**: full state-hue saturation, highest brightness among
   the actually-colored (non-white) elements.
3. **Energy conduits + core sparks**: state hue, moderately dimmer than
   the core (structural constraint: must never out-bloom it — see Q10).
4. **Orbital/ambient particles**: state hue, dimmer again, tiered by
   role exactly as V1 already does (`CORE_SPARK_EMISSION_ENERGY` >
   `ORBITAL_EMISSION_ENERGY` > ambient's `EMISSION_ENERGY`).
5. **Housing/glass accents**: only a *faint* tint of state color over a
   fixed dark/pale base (V1's `CORE_HOUSING_BASE_COLOR.lerp(_current_
   color, 0.15)` — 15% is the right order of magnitude and carries
   forward), reinforcing "this is glass/metal, not energy."
6. **Struts/plates**: **never tinted by state color at all** — this is
   an existing, explicit V1 rule (`_update_plates()`'s own comment: "a
   genuinely neutral dark metal that doesn't participate in the energy
   color story") and it is exactly right. It stays a hard rule, not a
   default that happens to be true today.

---

## 10. Bloom hierarchy

Ranked list, brightest to dimmest, **at baseline multiplier, before any
per-state scaling** — this is the thing that must be checked
numerically every time a new element is added, the same way V1's
`core_wins` check already works:

1. `CoreEmblem` — always the brightest single constant in the scene.
2. `Core` (glow sphere).
3. Core sparks (particle role).
4. Energy conduits (both arcs, including the new structure-anchored one).
5. Orbital particles.
6. Billboard energy phenomena (wisps/flares) — deliberately subordinate;
   V1's own wisp pass already established and verified this numerically
   (`WISP_EMISSION_ENERGY` kept low enough that `core_glow`/`core_emblem`
   exceed `wisp_peak` in every state) and the same check must be re-run
   for their new, structure-anchored positions.
7. Glass/Fresnel rim brightening (housing + accents).
8. Ambient particles — dimmest emissive element in the scene.
9. **Struts/plates are not part of this list at all.** They should
   almost never cross `glow_hdr_threshold`; their only legitimate bright
   moment is a real-lit specular glint (a property of the scene's
   `OmniLight3D`, not their own `emission_energy_multiplier`, which they
   don't have).

**Binding process rule**: every new element gets a print-based numeric
hierarchy check (structural pattern already established:
`core_glow_emission > new_element_peak` and `core_emblem_emission >
new_element_peak`, computed and logged on every state transition,
exactly like the existing check already does for arcs and wisps) before
it's considered done — never just "looked fine in one screenshot."

---

## 11. Construction technique per element, and why

| Element | Technique | Why this, not something else |
|---|---|---|
| Emblem | Procedural `SurfaceTool` mesh, opaque, unshaded+emissive | A flat 2D-read symbol needs no material complexity; must stay geometrically simple and unambiguous |
| Core glow | `SphereMesh` + unshaded emissive (+ noise-modulation shader, Q2/Q7) | Needs to be a real rigid body (pulse-scales, gets occluded correctly by the housing) |
| Housing | `SphereMesh` + Fresnel shader (`orb_glass_shell.gdshader`, inverted) | A "rim-only visible" material cannot be built any other way without real refraction/subsurface rendering, which is architecturally unavailable in this transparent-window context (confirmed, not assumed, by the renderer investigation's own empirical refraction test) |
| Rings/segments | Procedural `SurfaceTool` ribbon meshes | Need real, occludable, depth-sortable 3D geometry — a shader trick or billboard cannot produce correct mutual occlusion with the new struts |
| Struts | Crystal-shard mesh (`_build_crystal_shard()`, reused verbatim) + real-lit `StandardMaterial3D` with rim | "Dark metal that responds to a real light source" needs genuine shaded lighting, unlike every other unshaded/Fresnel element in the scene; flat per-facet normals need real separate geometry — a fake-normal shader was tested and confirmed **not** to work at this object's scale (`facet_fake_normal.gdshader`'s own PoC finding) |
| Energy conduits | Procedural ribbon + custom unshaded shader (`orb_arc_ribbon.gdshader`, reused) | The traveling-brightness-wave "flow" character needs per-vertex UV-driven animation a flat material can't produce; already human-confirmed working |
| Glass/crystal accents | Ellipsoid or crystal-shard mesh + Fresnel shader | Same reasoning as housing; crystal-shard geometry (reused from the plate technique) gives an accent genuine faceted depth instead of another smooth shell |
| Particles (3 roles) | `GPUParticles3D` × 3 | Genuinely many small, short-lived, independently-varying instances — hand-built static geometry would be wasteful and would lose per-instance variation entirely |
| Billboard energy phenomena | Camera-facing quad + manual vertex-override shader (validated PoC technique, `orb_energy_wisp.gdshader`) | The only technique in this engine that gives a soft, always-camera-facing atmospheric glow without real volumetric rendering; reserved specifically for diffuse/energetic phenomena, now anchored per Q6 rather than freely orbiting |

---

## 12. All 9 states, genuine behavioral differences

`STATE_PROFILES` (table-driven, one row per state, zero special-cased
`if state ==` logic anywhere in `_process()`) is preserved as the
mechanism — it is one of V1's clearest successes and needs no rework,
only new fields for the new elements. `SPEAKING` is explicitly included
below since the brief specifically flags it as easy to omit (it predates
the richer state model and isn't in the original design-direction doc's
own state list, but it is a real, currently-firing state).

| State | Structural interlock motion | Energy conduits | Billboard phenomena | Core micro-detail |
|---|---|---|---|---|
| IDLE | Near-static, slow shared drift | Slow, calm flow | Minimal, rare flares | Slow, barely-perceptible shimmer |
| LISTENING | Slightly more responsive | Slightly brighter/faster | Occasional, gentle | Slightly livelier |
| THINKING | Irregular, searching motion | Turbulent, energetic | Frequent, restless | Fast, agitated shimmer |
| SPEAKING | Rhythmic, tied to `level` | Moderate, steady pulse | Occasional, in sync with pulse | Moderate |
| EXECUTING | Directional, purposeful | Strong, fast flow | Most active — reads as "working" | Fast |
| COMPLETED | Brief settle-then-calm | Brief bright pop, then settle | Brief flare, then quiet | Settling |
| ERROR | Fast, irregular, "controlled disruption" (motion communicates instability, not raw brightness) | Fast, unstable | Fast/erratic motion, restrained brightness (never exceeds EXECUTING's peak — see Q10) | Agitated |
| OFFLINE | Nearly frozen | Near-zero | Off/negligible | Negligible |
| WAITING_CONFIRMATION | Distinct but calm — a held, attentive posture, not urgent | Steady, present | Sparse, deliberate | Calm |

This is a design table, not a numeric spec — exact multipliers get
tuned during implementation, screenshot-verified per state exactly as
every prior pass in this project's history has done. The pattern to
preserve is V1's own: "structural constant + per-state multiplier,"
never a hardcoded per-state special case.

---

## 13. Readability against an arbitrary real desktop background

Three concrete rules, one of them an honest correction to this
project's own recent practice:

1. **The silhouette test (Q4) is the primary tool.** An element that
   only reads via bloom against a *black* test background will not
   reliably read against a bright, busy real desktop — bloom blooms
   relative to what's already there, and a transparent window has no
   guaranteed-dark backdrop to bloom against.
2. **Never let a translucent accent be the only visible edge of a
   shape.** Every translucent glass/energy element that matters to the
   overall silhouette should have at least one opaque structural
   neighbor (a strut, the housing) nearby, so the assembly keeps a
   legible edge against both light and dark real content behind it.
3. **Honest correction, stated plainly**: the original renderer
   investigation already flagged that composition "has not been tested
   over varied real desktop backgrounds... only against the black/empty
   Godot-scene background used for FPS/screenshot validation." My own
   three most recent passes mostly tested the same way — against a
   harness's default transparent/black backdrop, using in-engine
   `get_viewport().get_texture()` capture, not real OS-level desktop
   compositing. That was a reasonable simplification for verifying
   geometry/material/motion in isolation, but it means **V2's
   implementation sequence must include a real, OS-level, varied-
   wallpaper screenshot test before it's considered done** — this
   project already has the tool for this (`System.Drawing.Graphics.
   CopyFromScreen`, used successfully in the original glass-shell
   investigation) and V2 should not skip back to the easier in-engine
   capture for this specific check.
4. **Contingency, not a committed feature**: if that real-background test
   shows the emblem struggling against a bright desktop background, the
   fallback is a very subtle, state-independent, low-opacity darkening
   immediately behind the core only (never a fake room/environment) —
   flagged here only so it's not a surprise mid-implementation, not
   committed to unless the test actually shows a problem.

---

## 14. Keep, rework, or discard — explicit calls

### Keep as-is (evidenced, not assumed)

- **CoreHousing + Core + CoreEmblem triad**, including the `core_wins`
  emission-hierarchy check — the most specifically-named requirement in
  the original brief, the highest-leverage V1 fix, regression-tested
  clean across four subsequent passes.
- **The three-material-family palette** as an organizing principle.
- **`orb_arc_ribbon.gdshader`'s traveling-wave technique** — human-
  confirmed "feels as intended, no follow-up needed."
- **Three particle roles**, `GPUParticles3D`-based, tuning largely as-is.
- **`STATE_PROFILES`, table-driven, "structural constant + per-state
  multiplier"** as the state-behavior pattern.
- **Crystal-shard geometry + real-lit rim material** (`_build_crystal_
  shard()`, `rim_enabled`) as a technique — reused for the new struts.
- **Billboard vertex-override + radial-falloff + noise shader** as a
  technique — reused for repositioned energy phenomena.
- **Godot subprocess / transparent window / WebSocket bridge**
  infrastructure — out of scope to touch, restated here as preserved.

### Rework substantially (technique kept, application changed)

- **Segmented rings**: keep the partial-arc/independent-segment
  technique; redesign tilts/placement so they interlock with struts and
  cross each other in projection (Q3), instead of being two independent
  concentric bands.
- **Plates → struts**: keep the geometry/material technique; redesign
  positions to anchor to ring-segment endpoints rather than independent
  angles — this also resolves the edge-on-camera problem I found in my
  own tuning pass, by construction rather than by further guessing.
- **Camera**: from one static tilt to slow continuous idle parallax.
- **Billboard energy phenomena**: keep the shader technique; discard the
  freely-orbiting placement in favor of structure-anchored junctions.
- **Bloom hierarchy**: not broken today, but must be explicitly
  re-verified (numeric check, Q10) as every new element lands, not
  assumed to keep holding.

### Discard entirely

- **The 4-shell uniform-concentric glass system, as currently built.**
  The project's own existing code comments already self-diagnose this
  exact failure ("4 equally bright concentric shells inherently read as
  4 equally-visible nested rings, not glass depth... an intrinsic
  property of the technique on a static front view, not a tunable bug"),
  and Q4's silhouette test predicts it fails outright without bloom
  (near-zero base alpha, `GLASS_CORE_ALPHA = 0.06`). Replaced by 1–2
  asymmetric glass/crystal accents at genuinely different depths/scales
  (Q5), reusing the *shader* (Fresnel is kept, per Q8/Q11) but discarding
  the "4 uniform concentric shells" application entirely.

---

## Proposed implementation sequence

Same discipline as every prior pass in this project's history: one
system per pass, real-screenshot-verified before the next begins, never
bundled.

1. **Pass V2-1 — Structural re-architecture.** Compound ring tilts +
   2–3 anchored struts, replacing independent placement. Highest risk,
   most novel, goes first since every later pass's positioning depends
   on it. **Test**: the silhouette test (Q4) with bloom/particles
   reduced, plus a real screenshot confirming at least one genuine
   crossing/occlusion depth relationship.
2. **Pass V2-2 — Glass/crystal accent consolidation.** Discard the 4
   uniform shells; build 1–2 asymmetric accents at the new structure's
   varied depths/scales. **Test**: real screenshot confirming the
   accents read as distinct depth layers, not nested rings.
3. **Pass V2-3 — Energy conduit rework.** One struct-anchored arc + one
   circulating arc, reusing the existing shader unmodified. **Test**:
   screenshot confirming a visible connection to specific structural
   points, not just "another ribbon near the core."
4. **Pass V2-4 — Billboard energy phenomena repositioning.** Reuse the
   existing shader/technique; move to structural junctions. **Test**:
   the same "controlled energy vs. smoke/mist" check my own wisp pass
   established (zoomed + normal-scale screenshot), re-applied at the new
   positions.
5. **Pass V2-5 — Camera parallax.** Replace the static tilt with slow
   idle drift. **Test**: a real screenshot sequence over time showing
   genuine parallax; re-verify the silhouette test still holds under
   drift (worst-case reach can change with camera angle, exactly as it
   did for the original tilt pass).
6. **Pass V2-6 — Core micro-detail.** Finally build the deferred noise-
   modulated core glow. **Test**: `core_wins` and emblem legibility
   re-verified; noise dumped to disk and visually confirmed *before*
   trusting it in the shader (the lesson from two prior failures on this
   exact technique).
7. **Pass V2-7 — Bloom/material hierarchy re-verification.** A single
   pass whose only job is the numeric print-based check (Q10) across
   every old and new element, all 9 states. **Test**: console log,
   `core_glow`/`core_emblem` exceeding every other element's peak, every
   state, no exceptions.
8. **Pass V2-8 — State-profile re-tuning.** Extend `STATE_PROFILES` for
   any new fields the reworked elements need (Q12's table). **Test**:
   cycle all 9 states including `SPEAKING`, one screenshot each.
9. **Pass V2-9 — Desktop-background legibility.** Real OS-level
   screenshots (not in-engine capture) over at least one light and one
   dark real desktop background. **Test**: emblem/core/silhouette
   legible against both; contingency vignette (Q13) only if this fails.
10. **Pass V2-10 — Performance re-measurement.** Combined-scene FPS,
    same methodology as every prior pass, **using a real-elapsed-time
    settle wait, not a frame-count wait** — the specific timing bug I
    found and fixed two passes ago, restated here so it isn't
    reintroduced by whoever implements this.

Each pass is independently revertable and independently screenshot-
verified, exactly matching this project's own established discipline —
and per the task that produced this document, **none of this is
implemented yet.** This document is the input to a separate,
subsequent implementation prompt.
