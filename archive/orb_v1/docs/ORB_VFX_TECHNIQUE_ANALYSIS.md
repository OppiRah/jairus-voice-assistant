# Orb VFX Technique Analysis

## Status: Investigation only — the live orb scene was not touched

Same discipline as `ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md` before it:
`JAIRUS_ORB_VFX_TECHNIQUE_REFERENCE.md` was read in full first. This
document maps which of its named techniques are already present in the
real code, builds standalone PoCs for the genuinely missing ones, and
produces one recommended next step — not a menu. `orb_scene.tscn` and
`orb_controller.gd` were not modified; `git status` at the end of this
investigation shows only new, standalone PoC files, same as every prior
orb investigation.

**What this is not:** an attempt to reproduce the reference video's
fantasy-magic appearance. Every technique below is evaluated only as a
*construction method* for Jairus's own engineered/high-tech identity,
per the reference doc's own framing.

---

## 1. Technique-by-technique mapping (real code inspected, not assumed)

| Technique | Status | Evidence |
|---|---|---|
| **Billboard VFX** | **Genuinely missing** | `grep -rn "billboard_mode\|BILLBOARD"` across every file in `godot_project/` returned zero matches. Every visible element (core, housing, rings, plates, arcs, particles) is real 3D geometry; `GPUParticles3D`'s own draw-pass meshes are literal 3D `SphereMesh`es, not camera-facing quads (`_make_translucent_material()` never sets a billboard mode, so it stays at `StandardMaterial3D`'s default `BILLBOARD_DISABLED`). |
| **Procedural noise** (`NoiseTexture2D`/`FastNoiseLite`) | **Genuinely missing** | Same grep for `NoiseTexture2D\|FastNoiseLite` returned zero matches. All existing "organic" motion (the arc ribbon's brightness wave, the breathing pulse, plate rotation) is analytic (`sin()`-based), never texture-driven. |
| **Fresnel** | **Extensively present, correctly scoped** | `orb_glass_shell.gdshader` is reused, as-designed, by the 4 outer glass shells and `CoreHousing` (inverted intent). The plates' own Fresnel question is already decided (native `rim_enabled`, not this shader) per the prior investigation — not re-litigated here. |
| **Layered VFX philosophy** | **Present and followed consistently** | Confirmed by reading the full controller: Core / CoreHousing / CoreEmblem / AmbientParticles / CoreSparks / OrbitalParticles / RingA+segments / RingB+segments / ArcA+ArcB / Plate1-3 / GlassShell1-4 are 16 independently-instantiated nodes, each with its own material instance and its own `_update_*()` function, each reacting to `STATE_PROFILES` through its own named fields. No shared "god shader" or "god function" exists anywhere in `_process()`. |
| **Energy wisps/mist** | **Genuinely missing** | No soft, camera-facing, elongated translucent-glow element exists anywhere. The closest things — the arc ribbons (rigid, precise, UV-tagged brightness wave) and the particle systems (small discrete points) — are both explicitly *not* wisps by the reference doc's own definition (a wisp is a soft, extended, atmospheric glow layer, not a point or a ribbon). |

**Two techniques are genuinely, completely absent** (billboard VFX,
procedural noise) — not partially present, not represented in spirit by
something else. Both were built as standalone PoCs and screenshot-tested,
below.

---

## 2. What was built to test this

One new standalone scene, same precedent as `glass_poc_test.*`,
`silhouette_poc_test.*`, `facet_poc_test.*`:

- **`vfx_technique_poc_test.tscn` / `.gd`** + **`noise_core_poc.gdshader`**
  + **`billboard_wisp_poc.gdshader`** — four objects side by side under
  one shared environment (the real orb's own glow settings, copied
  verbatim: `glow_bloom=0.55`, `glow_hdr_threshold=0.65`,
  `glow_hdr_scale=2.0`):
  - **A** — a flat, uniformly emissive sphere: the real orb's current
    core recipe exactly. Control.
  - **B** — the same sphere, `noise_core_poc.gdshader`: a real
    `FastNoiseLite`-generated `NoiseTexture2D` modulating brightness.
  - **C** — a camera-facing billboard quad, `billboard_wisp_poc.gdshader`,
    plain procedural radial falloff (no image asset), no noise.
  - **D** — the same billboard quad with `use_noise=1`: a real
    `NoiseTexture2D` breaking the plain falloff into an irregular shape.

Zero coupling to the real scene — if this folder's PoC files were
deleted tomorrow, nothing about the real running app would change.

---

## 3. Findings

### Billboard VFX — works, and is the more important discovery

Godot 4's spatial-shader `render_mode` has **no `billboard` keyword** —
that keyword exists only for `shader_type particles`. Getting a custom
`ShaderMaterial` billboard-facing required a manual `vertex()` override
rebuilding `MODELVIEW_MATRIX` from `INV_VIEW_MATRIX` (the same trick
`StandardMaterial3D.billboard_mode` wraps internally). This is a real,
non-obvious implementation detail worth recording so a future pass
doesn't waste time on the wrong API.

Once built, the technique itself is unambiguously good, confirmed by
real screenshot: variant C (plain radial falloff) reads as a convincing
soft, additive glow with **no visible sprite edge at any zoom level
tested** — exactly the "soft halo/transient burst" the reference doc
asks billboards for. Variant D (the same quad, `use_noise=1`) breaks
the perfect circular symmetry into a visibly irregular, non-uniform
"wisp" shape — a real, legible difference from C, not a subtle one.
This directly and cheaply answers the reference doc's "energy
wisps/mist" item too: billboard + noise together, not either alone, is
what produces a convincing restrained-plasma wisp rather than a plain
glow dot or a flat sprite.

**Cost:** one small shader, one `QuadMesh`, no image asset, no coupling
to any existing system. Godot's own particle billboard machinery is
also available for a multi-instance version later if a *field* of wisps
is ever wanted, but a single hand-placed wisp (or a small fixed number,
per the reference doc's "deliberately positioned, not randomly
floating" instruction) needs nothing beyond what was just built.

### Procedural noise on the core — works, but only after real debugging, and the payoff is subtle

This is the most important methodological finding in this document.
**The naive implementation looked completely broken for six consecutive
real-screenshot iterations, and every one of the three root causes was
a genuine bug — not a tuning-taste question:**

1. The shader modulated only `EMISSION`, leaving `ALBEDO` a flat
   constant. On an `unshaded` material the flat `ALBEDO` alone already
   dominates the visible pixel, masking whatever `EMISSION` was doing
   underneath. **Fix: modulate both.**
2. `noise_tex` had no `repeat_enable` hint. Godot's default sampler wrap
   is clamp-to-edge; any `noise_scale` pushing the sampled UV outside
   `[0,1]` (needed to get more than one "blob" of pattern visible on a
   sphere's limited front-facing UV range) clamps to a single edge
   texel across nearly the whole surface. **Fix: add the hint.**
3. `FastNoiseLite.frequency` has to be matched to how much of the noise
   texture the visible UV range actually covers. Too low, and the
   visible sliver of UV never leaves one smooth "blob" (looks flat too
   low-frequency to show). Too high, and the per-texel noise gets
   blurred to a uniform gray by ordinary texture minification (looks
   flat too high-frequency to survive being shrunk on screen). Neither
   failure mode is rare or exotic — both are the default outcome unless
   frequency is deliberately matched to the object's approximate
   on-screen size. **Fix, found empirically:** `frequency=0.15`,
   `noise_scale=2.0` is the specific combination confirmed by real
   screenshot (including a two-shot, several-seconds-apart comparison
   proving the grain genuinely animates, not a static artifact) to
   produce visible, moving texture on this sphere at this camera
   distance — not a value to copy uncritically onto a differently-sized
   object.

**With all three fixed, the effect is real and — critically — was
re-verified at the core's actual production emission energy
(`CORE_GLOW_EMISSION_ENERGY=6.0`, not a convenient low PoC value) with
the real orb's actual bloom settings enabled.** At that real intensity,
variant B shows a clearly visible, fine, animating grain texture across
the sphere's surface, distinctly different from variant A's perfectly
smooth glow. The bloom softens the grain somewhat (as expected — bloom
is a blur, and blur reduces contrast in fine detail) but does not erase
it at this tuning.

**Honest characterization of the payoff:** what this produces is a
subtle, fine, "static-like" shimmer — a genuine improvement over a
perfectly flat glow, and a direct answer to design-doc §4's still-open
"subtle internal motion" ask, but it is not a dramatic "churning
plasma" effect. Anyone expecting the latter from this technique alone
would be disappointed; it is a polish-tier improvement, not a
structural one.

### Fresnel — no further extension warranted

Every translucent/emissive element that could plausibly benefit already
has it (4 glass shells, `CoreHousing`); the one open question (plates)
is already decided against, per this task's own explicit instruction
not to re-litigate it. Checking the remaining elements for a legitimate
gap: the core glow sphere and emblem are meant to read as concentrated,
opaque-feeling light sources, not glass — adding a rim effect there
would blur exactly the "core vs. energy vs. glass vs. metal" material
distinctions the project has deliberately built up across four passes.
Ring segments and arcs are thin ribbons, mostly edge-on to the camera —
a Fresnel rim on an already-thin ribbon has little surface area to act
on and would be visually redundant with the ribbon's own brightness
wave. Particles are a few pixels across on screen; a per-pixel Fresnel
term is not perceptible at that size. **Verdict: REJECT further Fresnel
expansion.** The project's own existing scope is already the correct
scope.

### Layered VFX philosophy — no action needed

Confirmed by reading the full controller end to end: 16 independently-
instantiated visual systems, each with its own material and its own
`_update_*()` function, each driven by its own named `STATE_PROFILES`
fields, with no shared "do everything" shader or function anywhere.
This is already exactly what the reference doc's biggest lesson asks
for. Nothing to change.

---

## 4. Priority ranking

| Technique | Priority | Reasoning |
|---|---|---|
| **Billboard energy wisp(s)** (radial falloff + optional noise) | **HIGH** | Fills the one completely empty category (a soft, atmospheric energy-phenomena layer) at near-zero cost, is purely additive (touches nothing human-confirmed-working), and is already validated by real screenshot in both a plain and a noise-driven form. Lowest risk, clearest gap, cheapest to build. |
| **Core noise-modulated internal motion** | **MEDIUM** | Real, validated, answers a specifically-named design-doc gap — but the payoff is subtle (fine shimmer, not dramatic churn), the naive implementation is genuinely easy to get wrong in three specific ways documented above, and it modifies the single most scrutinized, hierarchy-critical element in the scene (`core_wins` must continue to hold in every state after any change here). Worth doing, but after the risk-free win above, and with its own dedicated per-state tuning/verification pass. |
| **Fresnel extension to any other element** | **REJECT** | No remaining element would clearly benefit; the project's Fresnel scope is already correct. |
| **Noise as an additive layer on the energy ribbons** | **LOW / not recommended now** | Explicitly allowed as additive-only per the reference doc, but the ribbon system is human-confirmed "feels as intended, no follow-up needed" with no named problem to solve — this would be polish-chasing an already-approved element, not fixing anything. |
| **Noise on the glass shells or ambient particle field** | **LOW / not recommended** | No specifically-named problem exists for either; real risk of the reference doc's own named failure mode ("does it add distracting visual noise") with no clear counterbalancing gain. |
| **Layered VFX philosophy changes** | **N/A** | Already followed consistently; nothing to prioritize. |

---

## 5. Recommended next implementation step (singular)

**Build one billboard-based energy wisp element, combining the
validated radial-falloff shader with the validated `FastNoiseLite`
irregularity (`billboard_wisp_poc.gdshader`'s `use_noise=1` path),
deliberately positioned and animated around the existing ring/arc
structure — not randomly floating, per the reference doc's own
constraint.** This is additive only: it introduces one new, small,
independently-tunable layer (its own `STATE_PROFILES` fields, same
pattern as every existing system) without touching the core, housing,
plates, rings, arcs, or particle systems that are already
human-confirmed working. It directly answers two of the reference doc's
five investigation items at once (billboard VFX, energy wisps) with a
technique already proven end-to-end in this investigation, at
essentially zero measured GPU cost given this project's existing
>1600 FPS headroom.

The core noise-modulation finding is real and worth pursuing, but as a
**separate, second follow-up** — it earned a place on the roadmap, not
a spot in the same implementation pass as a first-time, higher-risk
touch to the core's material.
