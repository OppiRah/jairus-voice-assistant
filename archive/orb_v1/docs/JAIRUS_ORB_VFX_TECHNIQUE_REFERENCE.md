# Jairus Orb — VFX Technique Reference

## Purpose

This document introduces a new reference for the **orb renderer's VFX
construction techniques** — not a new visual target. It supplements,
never replaces, `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md` (the actual
visual target) and the existing investigation docs.

**The reference:** "Godot Magic Orb VFX | Showcase" by Binbun3D —
https://youtu.be/es0SUzHH8V8

**The instruction, stated as plainly as possible:** study *how* that
reference constructs its effects — the techniques — not *what it looks
like*. Do not reproduce its appearance, its assets, its exact geometry,
or its fantasy/magic visual character. Jairus is "a futuristic,
high-tech energy artifact that happens to be Jairus's interface," not a
wizard's orb, a fireball, or a generic fantasy pickup. This distinction
matters more than any single technique below.

---

## Current state (do not assume you're starting from zero)

The orb already has substantial, human-confirmed-working visual
systems. Read the existing orb progress handoff and investigation docs
for full detail — do not duplicate that work or second-guess anything
already confirmed working. In summary, already implemented and
confirmed:

- Core: dark housing, procedural emblem, verified core-vs-energy
  emission hierarchy (`core_wins`, checked at runtime every state
  transition).
- Structure: segmented rings, independently-rotating segments, 3
  asymmetric dark mechanical plates (silhouette/material fix pending as
  a separate, already-scoped implementation — see the separate prompt
  for that).
- Energy: continuous traveling-brightness-wave ribbons (human-confirmed
  "feels as intended, no follow-up needed" — do not replace or
  significantly alter this system).
- Particles: three distinct roles (ambient, core sparks, orbital) —
  human-confirmed distinct and correct.
- Materials: Fresnel-based glass shells and core housing, real-lit dark
  metal for plates, bloom.
- Architecture: Godot 4.x, separate process, transparent/borderless/
  always-on-top over the REAL desktop, WebSocket bridge to the real
  Jairus runtime, `mobile`/Vulkan renderer (validated, do not revisit),
  Qt orb fallback preserved.

**The 9 real states in the actual enum** (for any state-behavior
investigation or testing): `IDLE`, `LISTENING`, `THINKING`, `SPEAKING`,
`EXECUTING`, `COMPLETED`, `ERROR`, `OFFLINE`, `WAITING_CONFIRMATION`.
Note `SPEAKING` specifically — it's easy to omit since it predates the
richer state model and isn't in the design-direction doc's own list,
but it's a real, currently-firing state (drives TTS-time behavior) and
must be included in any per-state investigation/testing.

---

## What to investigate (techniques, not appearance)

For each of the following, investigate **whether and how** it could
serve Jairus's actual visual hierarchy — not whether it's possible to
add:

1. **Billboard VFX** — camera-facing layers for energy phenomena
   specifically (wisps, soft halos, transient bursts) — never as a
   replacement for existing structural 3D geometry (core housing,
   plates, ring segments must stay real geometry).
2. **Procedural noise** (`NoiseTexture2D`/`FastNoiseLite`) — only where
   it solves a specific, named visual problem (e.g. breaking up
   too-perfect surfaces, subtle internal motion). For every candidate
   use, answer explicitly: what problem does this solve, which existing
   component would receive it, is the result actually better than
   current, does it add distracting visual noise, does it meaningfully
   increase shader complexity for the benefit gained.
3. **Fresnel — where it's already doing real work, and where it could
   help without flattening material distinctions.** The project already
   uses Fresnel extensively (glass shells, core housing). Do not default
   to "add more Fresnel" — investigate specifically whether it could
   extend to a component that currently lacks it (per the existing
   silhouette/material investigation's own finding: the plates
   specifically should use native `rim_enabled`, NOT a new custom
   Fresnel shader, since that shader is unshaded and would erase the
   dark/metal contrast that's the plates' whole purpose — do not
   re-litigate this, it's already decided).
4. **Layered VFX as a construction philosophy** — the reference's
   biggest lesson is composing many small, clear-responsibility layers
   rather than one complex shader. The project already does this well
   (core / housing / segments / plates / ribbons / particles are all
   separate, independently-tunable systems) — investigate whether this
   philosophy is being followed consistently, not whether to introduce
   it.
5. **Energy wisps/mist** — a restrained, controlled version only, read
   as "electromagnetic field / plasma / holographic energy," explicitly
   NOT smoke, fire, or magical fog. If pursued, wisps should be
   deliberately positioned/animated around the existing structure, not
   randomly floating.

## Explicitly out of scope for this investigation

- Do NOT replace the existing energy ribbon system (human-confirmed
  working) — noise could only ever be an ADDITIVE, independently-
  testable layer on top of it, never a replacement.
- Do NOT reproduce the reference video's exact appearance, assets, or
  fantasy-magic character.
- Do NOT reopen genuine desktop refraction (confirmed technically
  impossible in this architecture) or the plates' Fresnel-shader
  question (already decided against).
- Do NOT implement the pending silhouette-containment/plate-geometry/
  plate-material/camera-tilt fixes as part of this task — that's a
  separate, already-scoped implementation prompt, sent separately.
- Do NOT touch any Python-side file, or any non-orb Jairus system
  (Agent Core, command gateway, tool registry/executor, Android
  app/gateway, voice pipeline).

## Decision criteria for every technique considered

1. Does it improve the visual target (the design-direction doc's actual
   goal), not just add visual complexity?
2. Does it preserve Jairus's identity (engineered/high-tech, not
   fantasy-magic)?
3. Does it improve depth/material/energy readability specifically?
4. Does it preserve the existing visual hierarchy (core remains
   brightest/dominant — `core_wins` must continue to hold)?
5. Is it appropriate for a transparent desktop overlay specifically
   (not a technique that assumes an opaque background or a controlled
   lighting environment)?
6. Can it stay modular and state-driven through `STATE_PROFILES`,
   consistent with every existing system?
7. Is the engineering/performance cost justified by the visual gain
   (the project has real GPU headroom — ~1600+ FPS baseline — so this
   is about leverage, not minimum GPU usage)?
8. Does REAL OS-level screenshot testing (not in-engine capture)
   actually confirm the improvement, not just "should look better in
   theory"?

If the answer to #8 is no for a given technique, it is not validated,
regardless of how sound the reasoning was.

## Discipline, unchanged from every prior orb investigation

- Build small, standalone, isolated PoCs for anything uncertain (e.g.
  `billboard_poc_test.*`, `noise_vfx_poc_test.*`) — same precedent as
  `glass_poc_test.*`, `silhouette_poc_test.*`, `facet_poc_test.*`. These
  are historical evidence, never wired into the production scene.
- Real OS-level desktop screenshots (`System.Drawing.Graphics.
  CopyFromScreen` or equivalent) are the only trustworthy visual
  evidence for anything involving transparency, bloom, or desktop
  compositing. In-engine offscreen capture has already been proven
  unreliable for this in this exact project.
- Explicitly separate what's objectively/programmatically verified
  (geometry exists, parameters differ per state, FPS measured) from
  what requires human visual judgment (does it look cohesive, does it
  read as crystal, does it feel like Jairus) — never claim the second
  category based on the first.
- This is an INVESTIGATION task. Produce a recommendation document with
  evidence. Do not implement anything into the production orb scene in
  this task, and do not commit changes beyond new standalone PoC files
  and the investigation document itself.
