# JAIRUS Orb — Visual Design Direction & Concept Target

## Purpose

This document defines what the **Jairus desktop orb is supposed to look and feel like**.

It is a visual target and design direction, not a literal requirement that every pixel of the AI-generated concept image be reproduced.

The goal is to move the current Godot renderer toward the **visual identity and visual hierarchy** of the reference concept while keeping Jairus a real, transparent desktop overlay.

The current renderer is already GPU-accelerated and integrated with Jairus through a separate Godot process and local WebSocket bridge. This document therefore focuses on **visual direction**, not replacing the established architecture.

---

# 1. The Core Design Goal

The target is NOT:

> A glowing sphere with some rings and particles.

The target is:

> **A futuristic, high-tech energy artifact that happens to be the visual interface of Jairus.**

It should feel like a small digital machine/entity floating over the user's desktop.

The visual impression should be:

- intelligent
- powerful
- precise
- alive
- technological
- premium
- slightly mysterious
- visually complex without becoming messy

The reference concept uses cinematic 3D-render language: luminous energy, layered glass/crystal structures, mechanical-looking components, orbital geometry, bloom, particles, depth, and a distinctive central core.

We should reproduce the **spirit and visual hierarchy**, not fake a photographed room.

---

# 2. Important Desktop Constraint

Jairus is a transparent, borderless desktop overlay.

Therefore:

- The user's actual desktop must remain visible through transparent areas.
- No fake room/table/environment should be rendered around the orb.
- No assumption that the orb physically sits on a desk.
- The visual design must work when isolated against arbitrary desktop backgrounds.

The concept image contains a photographed environment and physical presentation base. Those elements are reference imagery only.

The orb itself is the target.

---

# 3. Visual Hierarchy

The orb should have a clear hierarchy:

```text
                 OUTER ENERGY FIELD
                         ↓
              ORBITAL STRUCTURES
                         ↓
              GLASS / CRYSTAL LAYERS
                         ↓
              INNER MECHANICAL CORE
                         ↓
                 JAIRUS SYMBOL
```

The viewer's eye should naturally land on the central core first, then move outward through the layers.

The outer effects should support the core rather than compete with it.

---

# 4. Central Core

The central core is one of the most important elements.

It should NOT read as an ordinary glowing sphere.

Desired characteristics:

- dark inner housing
- luminous central energy
- sharp diamond/star-like Jairus emblem
- strong silhouette
- controlled bloom
- layered depth around the emblem
- subtle internal motion
- concentrated brightness

The core should feel like the **source of the orb's energy**.

The Jairus symbol should remain recognizable rather than being destroyed by bloom.

---

# 5. Orbital / Structural Geometry

This is one of the biggest priorities.

The reference does not look like a mathematically perfect collection of concentric circles.

It contains:

- independently oriented rings
- broken/segmented structures
- translucent plates
- angular components
- floating elements
- different depths
- gaps
- asymmetry
- mechanical-looking geometry

The target should therefore move away from:

> nested glowing spheres

and toward:

> **a layered orbital machine.**

Do not simply keep adding complete torus rings.

Investigate:

- segmented rings
- partial arcs
- independently rotating sections
- angular glass plates
- offset geometry
- varied thickness
- different depth planes
- irregular orbital structures

A little controlled asymmetry is desirable.

---

# 6. Energy Ribbons / Arcs

The reference contains flowing energy around the core.

These should feel different from the rigid structural rings.

**Structural rings:** mechanical, precise, controlled, geometric.

**Energy ribbons:** fluid, energetic, organic, reactive, continuously flowing.

The energy should appear to circulate around and through the orb.

Potential implementation approaches may include:

- ribbon/trail geometry
- particle trails
- animated textures
- curved meshes
- shader-driven movement
- GPU particles

The exact implementation is an engineering decision. The visual goal is what matters.

---

# 7. Glass / Crystal Appearance

The orb should feel layered and glass-like without requiring physically impossible desktop refraction.

Desired visual cues:

- bright Fresnel edges
- transparent surfaces
- dark transparent centers
- layered depth
- soft internal haze
- selective highlights
- subtle distortion/lensing
- different opacity between layers

Avoid making every shell equally bright.

Equal-brightness nested shells create visual clutter and make the orb look like several glowing circles stacked together.

The glass should instead create **depth**.

---

# 8. Metallic / Mechanical Elements

The reference contains dark structural components that contrast with the luminous energy.

Use this contrast deliberately.

Metal-like components should generally have:

- dark body
- controlled highlights
- sharper edges
- less transparency
- restrained emission

Energy components should generally have:

- stronger emission
- softer bloom
- animated brightness
- translucent appearance

This contrast helps the orb feel like an actual constructed object rather than a collection of visual effects.

---

# 9. Particles

Particles are supporting elements.

Do NOT optimize for maximum particle count.

The goal is **interesting particle behavior**, not particle spam.

Ideally use multiple visual roles:

### Core sparks
Small particles close to the energy core.

### Orbital particles
Particles following orbital paths.

### Energy particles
Particles moving along energy ribbons/arcs.

### Ambient particles
Very subtle floating particles around the outer structure.

Avoid:

- particle soup
- diffuse fog replacing structure
- excessive screen coverage
- particles hiding the core

---

# 10. Bloom / Glow

Bloom is important, but it should be controlled.

Desired hierarchy:

```text
Core energy
    ↓ strongest

Energy ribbons
    ↓ strong

Glass/Fresnel edges
    ↓ moderate

Particles
    ↓ subtle
```

Bloom should emphasize geometry rather than hide poor geometry.

If an element only looks good because it is heavily blurred, its underlying shape probably needs improvement.

---

# 11. Depth

The orb should not look flat from the front.

Create depth through:

- multiple Z/depth layers
- different ring orientations
- foreground/background elements
- transparent overlaps
- varying scale
- parallax where appropriate
- lighting differences

The viewer should perceive that components occupy different locations in 3D space.

---

# 12. Controlled Asymmetry

Perfect symmetry makes the orb look procedural.

The concept has a designed, assembled quality.

Use controlled asymmetry:

- different ring angles
- offset components
- partial arcs
- unequal visual density
- different rotation speeds
- occasional floating elements

However, asymmetry should remain intentional. Do NOT make the orb random.

---

# 13. State-Driven Behavior

The orb is not merely decoration.

Its visual behavior represents the actual Jairus runtime state.

Minimum states:

- IDLE
- LISTENING
- THINKING
- EXECUTING
- WAITING_CONFIRMATION
- COMPLETED
- ERROR
- OFFLINE

States should change more than color.

Possible variables:

- core intensity
- ring speed
- ring direction
- energy-ribbon activity
- particle density
- particle speed
- glow intensity
- pulse irregularity
- animation speed
- temporary effects

Example direction:

**IDLE:** Calm, slow, stable.

**LISTENING:** More responsive and attentive.

**THINKING:** More internal movement and energetic activity.

**EXECUTING:** Purposeful, directional activity.

**WAITING_CONFIRMATION:** Clearly distinct but not alarming.

**COMPLETED:** Brief positive energy response.

**ERROR:** Strong but controlled red/orange instability.

**OFFLINE:** Low-energy / unavailable appearance.

All state tuning should remain centralized in the existing `STATE_PROFILES` system.

---

# 14. Floating UI

Floating task/status cards are part of the desired visual language.

They should remain real UI data, not fabricated animation.

Examples:

```text
EXECUTING

✓ Open Discord
✓ Launch Spotify
◉ Find playlist
○ Start playback
```

or:

```text
Open Discord?

[ Confirm ] [ Cancel ]
```

or:

```text
✓ Task complete

Playing Glimpse of Us
```

However:

**Do not invent task sub-steps or confirmation states that the backend does not actually provide.**

The UI must represent real Jairus state/data.

When real task-step data becomes available, it can be visually integrated into the orb presentation.

---

# 15. What We Are NOT Trying to Reproduce

We are NOT trying to reproduce:

- the photographed room
- the table
- cinematic photography
- a physical environment
- a fake reflection of the room
- impossible desktop refraction
- every pixel of the AI-generated image

The target is the **orb's visual identity**, not the entire product photograph.

---

# 16. Visual Target Summary

If someone sees the finished Jairus orb for the first time, the intended reaction is:

> "That is not just a glowing UI circle."

It should instead look like:

> **"That is some kind of futuristic energy device."**

The core should be immediately recognizable.

The surrounding structure should have depth and complexity.

The energy should feel alive.

The materials should suggest glass/crystal and dark metal.

The bloom should make luminous elements feel powerful.

The particles should add atmosphere without becoming noise.

And the entire thing should react to Jairus as it actually listens, thinks, executes, succeeds, fails, or waits.

---

# 17. Engineering Principle

**Visual ambition does not justify architectural damage.**

The renderer remains a presentation layer.

Conceptually:

```text
Jairus Runtime
      ↓
Runtime State
      ↓
Renderer Bridge
      ↓
Godot Renderer
      ↓
Orb Visuals
```

The orb must not become the Agent Core.

The orb must not directly execute tools.

The orb must not own Jairus business logic.

The renderer should remain replaceable.

---

# 18. Recommended Development Strategy

Do not perform another giant visual rewrite.

Use explicit visual passes.

### Pass A — Structure
Core + mechanical/orbital geometry + segmented elements + depth.

### Pass B — Energy
Ribbons + arcs + animated energy.

### Pass C — Materials
Glass + Fresnel + metal + controlled transparency.

### Pass D — Lighting
Bloom + glow + contrast + exposure.

### Pass E — Particles
Core/orbital/energy/ambient particles.

### Pass F — State polish
State-specific motion and transitions.

### Pass G — Composition
Scale, camera, placement, silhouette, UI relationship.

Each pass should be independently testable.

Real OS-level screenshots are the primary visual evidence for transparency, bloom and desktop composition.

---

# 19. The Reference Image

The AI-generated concept image is the **primary visual reference** for this document.

It should be treated as:

**visual inspiration + target design language**

not:

**literal technical specification.**

When making visual decisions, ask:

> "Does this move the real-time orb closer to the visual language of the reference?"

rather than:

> "Can we technically reproduce this exact photograph?"

---

# 20. Definition of Visual Success

The orb is visually successful when:

1. The central Jairus core is immediately recognizable.
2. The orb has clear 3D depth.
3. Structural geometry feels designed rather than procedural.
4. Rings/segments create an orbital-machine silhouette.
5. Energy ribbons visibly flow around the core.
6. Glass/crystal layers read as depth rather than nested glow.
7. Dark mechanical elements contrast with luminous energy.
8. Particles add life without obscuring the structure.
9. Bloom enhances rather than replaces geometry.
10. State changes are visually meaningful.
11. The orb looks convincing over an arbitrary real desktop background.
12. The overall silhouette and visual hierarchy feel substantially closer to the reference concept.

---

# 21. Current Renderer Context

At the time this document was written, the renderer already has:

- Godot 4.x
- separate renderer process
- local WebSocket communication
- Vulkan/mobile rendering
- transparent borderless always-on-top window
- state-driven profiles
- rotating ring geometry
- energy arcs
- activity overlay
- Fresnel glass shells
- distortion/lensing
- increased particle density
- bloom
- real desktop transparency
- automatic Qt-orb fallback

The next visual work should therefore focus on **closing the visual gap**, not rebuilding the renderer architecture.
