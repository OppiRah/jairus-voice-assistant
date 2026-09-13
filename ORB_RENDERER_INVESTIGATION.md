# Orb Renderer Investigation

Technical investigation into building the most visually impressive,
GPU-accelerated, real-time version of the Jairus orb that is realistically
achievable for a personal-use project, without disrupting the existing
Jairus architecture (Agent Core, Policy Engine, Tool Registry/Executor,
command/task lifecycle) or the UI work already built in Phases 1-8
(sidebar navigation, History, Tools catalog, Settings). Documentation
only — no code changed as part of this investigation.

The goal is explicitly **not** "make the current orb a little prettier."
The cinematic concept image is treated as a design-language reference, not
a literal spec: the question this document answers is what technology and
architecture could actually deliver that *class* of visual result in real
time, on a personal Windows machine, while keeping Jairus's runtime
authoritative and the renderer a swappable presentation layer.

---

## 1. Current UI architecture

**Where the orb actually lives today**: `orb_widget.py`'s `OrbWidget`
(`QWidget` subclass) — a `paintEvent()` using plain `QPainter` calls
(`drawEllipse`, alpha-blended `QColor` fills, `CompositionMode_Plus` for
additive ring glow) inside a 480×480 fixed-size widget, redrawn on a
60 FPS `QTimer`. No OpenGL, no shaders, no particles — every visual
element is a flat-colored circle drawn with 2D vector primitives. This
traces back to a literal, behavior-preserving PySide6 port (UI Phase 1) of
the original pygame implementation (`orb_ui.py`, now deleted) — the
`_draw_orb()` math (breathing sine wave, layered alpha rings, additive
blend) is unchanged since the very first version of this project's UI.

**How state reaches the orb**: `assistant_state.py`'s `AssistantState` is
a thread-safe, in-memory object shared between `assistant_loop.py`'s
background thread (the real voice/command logic) and the Qt UI on the
main thread. It exposes exactly two fields the orb reads every frame:
`status` (`"idle" | "listening" | "thinking" | "speaking"`, a 4-value
enum) and `level` (a 0.0–1.0 float driving pulse intensity, fed from live
mic RMS while idle and from `record_until_silence()`'s level callback
while recording). `OrbWidget.paintEvent()` calls `state.get_snapshot()`
every repaint and looks up a per-state RGB tuple from `theme.ORB_COLORS`.
This is a clean, minimal, **poll-based** read-only contract — the orb has
zero write access to `AssistantState` and the assistant thread has zero
awareness the UI exists at all.

**The rest of the desktop app**, built across UI Phases 1-8, sits around
that orb inside the same `QMainWindow` (`orb_widget.OrbWindow`):

- A persistent left `Sidebar` (`QListWidget`) with Home/History/Tools/
  Settings, each a real page in a `QStackedWidget`.
- `HomePage` = the orb (`OrbWidget`) + `ActivityPanel` (current-activity
  label + a small card-styled recent-commands list), side by side.
- `HistoryPage` = the same bounded history data, full-size.
- `ToolsPage` = a read-only catalog of every tool ever registered across
  the backend's capability phases, grouped by category, with permission-
  level badges (Harmless/Disruptive/Destructive/Dangerous) — pure display,
  no execution path.
- `SettingsPage` = a real, config-file-backed settings form (wake-word
  sensitivity, Whisper model size, music library path, Android pairing
  code), each field honestly labeled live-vs-restart-required.
- A `HealthIndicator` permanently in the status bar (Ollama reachability,
  model/mic readiness) — global, not per-page.
- `theme.py` — a single shared module of named colors (semantic status
  colors `SUCCESS`/`WARNING`/`DESTRUCTIVE`/`ERROR`, neutral chrome colors,
  a spacing scale) and icon mappings (`qtawesome`/Font Awesome, chosen
  after empirically finding Qt's own `QStyle.standardIcon()` rendered
  several needed icons as blank and the rest as non-themeable colorful
  Windows-native glyphs), applied once via a global `QApplication`-level
  QSS stylesheet.

**What can be preserved, unconditionally**: Sidebar navigation, History,
Tools, Settings, the health indicator, `theme.py`'s color/spacing/icon
system, and the entire `AssistantState`/`assistant_loop.py` contract.
None of that needs to change for a better orb — it's already a working,
tested, cohesively-styled application built around a `QWidget` that
happens to sit in `HomePage`'s layout. **The only thing this investigation
is actually about is what that one widget's content looks like and how
its data gets to it.**

**A real gap worth naming now, independent of rendering technology**:
`AssistantState` only ever expresses 4 states. `UI_UX_CONTEXT.md` already
documents an 11-state target model
(`IDLE → LISTENING → UNDERSTANDING → PLANNING → WAITING_CONFIRMATION →
EXECUTING → OBSERVING → RECOVERING → COMPLETED / FAILED / CANCELLED →
OFFLINE`), and this request asks for at least 8
(`IDLE/LISTENING/THINKING/EXECUTING/WAITING_CONFIRMATION/COMPLETED/ERROR/
OFFLINE`). **No renderer, however capable, can visually distinguish
EXECUTING from WAITING_CONFIRMATION from COMPLETED if `AssistantState`
never expresses those states in the first place.** Expanding the state
model is a small, additive, backend-side prerequisite — the same narrow
pattern already used for `action_type` in Phase 8 (a mechanical addition
at existing `handle_command()` call sites, no decision-logic change) — and
is out of scope for *this* document, but it is a real dependency of the
"state behavior" section below, not a rendering concern.

---

## 2. Target visual architecture

Regardless of which rendering technology is chosen, the architectural
shape requested is the same, and is a good one — it's the standard
"thin presentation layer" pattern already used everywhere else in this
project (UI is a client of `AssistantState`, never the other way around):

```
Jairus Runtime (assistant_loop.py, AssistantState, Agent Core, tools)
        │
        │  state changes (status, task label, progress, confirmation prompts)
        ▼
Presentation interface  (a narrow, versioned, JSON-shaped contract —
                          "here is the current state," nothing more)
        │
        ▼
Renderer (owns all animation/effects/camera/particle decisions)
```

The renderer **never** calls into the Agent Core, Tool Registry, or
`handle_command()` — it only ever receives state and decides how to show
it, exactly like `OrbWidget` does today. This holds whether the renderer
is a `QWidget` in-process or a separate executable out-of-process; the
only thing that changes across the options below is *how* state crosses
that boundary (a Python function call vs. a message over a socket).

---

## 3. Technology comparison

Evaluated against: visual ceiling, GPU/VRAM cost, implementation
complexity, integration difficulty, transparency/borderless support,
animation/particle/shader/bloom/lighting capability, state-reactivity,
IPC with Python, startup/shutdown behavior, reliability, debugging,
packaging, and maintainability — for *this* project, at *this* stage.

### A. Qt + `QOpenGLWidget` + hand-written GLSL (stay fully in-process)

- **Visual ceiling**: Real, but bounded by how much rendering-engine
  machinery you're willing to hand-write. Custom GLSL can absolutely do
  glow/bloom/rings — but Qt gives you a GL context and draw calls, not a
  scene graph, particle system, or post-processing pipeline. Bloom means
  hand-building an FBO ping-pong Gaussian blur pass yourself; particles
  mean hand-building instanced point-sprite rendering yourself. This is
  "write a small custom rendering engine," not "use one."
- **GPU/VRAM**: Lean by construction — you only render what you write.
- **Complexity**: **High** for a genuinely good result (you are the
  engine), **low** for integration (it's still just a `QWidget`).
- **Transparency**: Documented as achievable
  (`Qt.WA_TranslucentBackground` + `Qt.FramelessWindowHint` +
  `QSurfaceFormat.setAlphaBufferSize(8)`), but has real historical rough
  edges around composition on Windows — not a slam-dunk, needs its own
  spike to de-risk.
- **Integration**: **Best of every option** — same process, same event
  loop, zero IPC, zero second executable, zero window-sync problem.
  `AssistantState` stays exactly as authoritative as it is today.
- **Debugging/maintainability**: Single codebase, single language
  (Python + a little GLSL), no new toolchain, no new packaged binary.

### B. Godot 4.x, separate transparent/borderless overlay process

- **Visual ceiling**: **High**, and — critically — with a fraction of the
  hand-rolled effort of option A. Godot ships a real scene graph, a real
  particle system (`GPUParticles2D/3D`, fully shader-customizable), a
  *built-in* glow/bloom pass (`WorldEnvironment.glow_enabled` — a
  property, not something you implement), a proper shading language,
  an `AnimationPlayer`/`AnimationTree` for state-transition choreography,
  and — unlike raw OpenGL — a live editor where you compose and preview
  the scene visually instead of recompiling blind.
- **GPU/VRAM**: A real-time engine's baseline cost, but a small, mostly-
  static scene (one orb, a handful of particle emitters, no complex
  level geometry) on modern GPU/driver stacks should sit low; this needs
  measuring in the PoC, not assumed.
- **Complexity**: Complexity shifts from "hand-build a renderer" (option
  A) to "learn Godot, define an IPC contract, manage a second process" —
  a different kind of work, and for the specific effects list requested
  (bloom, particles, rings, lighting, materials), meaningfully *less*
  total engineering than hand-rolling the same in raw GL.
- **Transparency**: Native, first-class, project-settings-level feature
  (Borderless + Transparent + Per-pixel Transparency + Always On Top are
  literal checkboxes), with a real, current precedent: a "Desktop Pet"
  project built exactly this way (transparent, borderless, always-on-top
  window, an animated character blended into the desktop) was found
  during research. Known caveat: Godot 4.5 on Windows 11 + Vulkan has an
  open bug where a transparent window at *maximized/screen* size goes
  black when focused — this project's orb window is small and fixed-size,
  not maximized, so the specific bug class likely doesn't apply, but it's
  worth re-checking against whatever Godot version is current when the
  PoC is built.
- **IPC with Python**: WebSocket, via Godot's built-in `WebSocketPeer` on
  the Godot side and Python's `websockets` package on the Python side —
  **already a dependency of this exact project** (Phase 13's Android
  Gateway), with an already-working, already-tested local WebSocket
  server pattern (`gateway_server.py`) to model the renderer bridge on.
  This is the single strongest integration-risk-reducer of any non-Qt
  option: the Python-side code for this is close to a copy of something
  already proven to work in this codebase.
- **Startup/shutdown**: A subprocess Python launches and must supervise
  (start with `main.py`, terminate cleanly on window close) — new
  surface area that doesn't exist today, but a well-understood pattern
  (`subprocess.Popen` + `terminate()`/`kill()` on shutdown).
- **Reliability**: A second process is a second thing that can crash,
  hang, or fail to bind its window — needs explicit supervision to avoid
  "the orb silently disappeared" as a failure mode.
- **Debugging**: Two runtimes, two languages (Python + GDScript), a real
  IPC boundary to reason about — objectively harder than option A.
- **Packaging**: A Godot project export produces one additional
  standalone `.exe` to build and ship alongside the Python app. For a
  single personal machine, this is a one-time build step, not an ongoing
  cross-platform packaging burden.
- **Maintainability**: Two codebases going forward, but with a narrow,
  versioned JSON contract between them — the same decoupling discipline
  already used for `AssistantState`.

### C. Web tech (Three.js/WebGL) in its own transparent window (`pywebview`), separate process

- **Visual ceiling**: **High**, comparable to Godot. Three.js has mature,
  drop-in bloom/post-processing (`UnrealBloomPass`), particle systems,
  and PBR materials. **Directly relevant, current precedent**: ElevenLabs'
  own official UI library ships an "Orb" component — a WebGL/Three.js,
  audio-reactive, state-driven 3D orb built for exactly the "AI agent
  status visualization" use case this project needs. The broader
  Shadertoy/Three.js ecosystem is, empirically, the single largest source
  of ready-to-adapt "glowing energy orb" shader code on the internet —
  likely the easiest place of any option here to find a head start.
- **GPU/VRAM**: WebGL rendering cost is comparable to Godot's for similar
  scene complexity, but the *process* (a Chromium-based WebView2 host) has
  a heavier baseline memory footprint than a native Godot export, even if
  render-time GPU load is similar.
- **Complexity**: Comparable to Godot overall — no drag-and-drop scene
  editor (more manual JS/Three.js scene-graph code than Godot's node
  tree), but very fast iteration via browser devtools, and — per the
  point above — probably the fastest path to a first "this already looks
  cool" result by directly adapting existing shader work.
- **Transparency**: This is the one place research surfaced a **specific,
  documented reliability risk** — but only for one particular embedding
  method. `QWebEngineView` (Qt's own Chromium widget, composited *inside*
  the existing Qt window) has an open, reproducible bug report of
  transparent-background rendering corrupting roughly half the time,
  requiring a relaunch, on current Qt 6.9.x. That risk is specific to
  compositing a browser view inside a Qt widget tree. A **separate
  top-level `pywebview` window** (its own native OS window, transparency
  handled by the OS compositor directly, the same architectural shape as
  Godot's own top-level transparent window) was not the subject of that
  bug report and is architecturally the same *kind* of approach the
  Godot precedent already proves works — but this is inference, not a
  verified pywebview-specific transparency success report, and should be
  the very first thing validated in a PoC if this path is chosen.
- **IPC with Python**: A local WebSocket server (same `websockets`
  package) with a plain browser-native `WebSocket` client in the page —
  arguably even simpler on the JS side than Godot's `WebSocketPeer`.
- **Packaging**: Relies on the Windows-installed WebView2 runtime, which
  ships with Windows 10/11 by default — for a single personal machine,
  zero packaging burden at all (no export step, no second binary to
  build).
- **Debugging/maintainability**: Browser devtools are excellent for
  shader/JS iteration; still two languages/runtimes to maintain, same
  general shape as Godot.

### D. Unreal Engine (dedicated renderer)

- **Visual ceiling**: **Highest of every option** — genuine AAA lighting,
  reflections, volumetrics, and Niagara particles; the closest realistic
  path to literally reproducing the cinematic concept image.
- **GPU/VRAM**: **Heavy**, categorically more than Godot or a WebGL
  scene, even for a deliberately simple orb-only scene — a real,
  persistent cost for something meant to idle in the background all day
  on a personal machine that's also used for other GPU-hungry work.
- **Complexity/packaging**: **Very high** — a multi-GB engine install,
  long cook/package times, a packaged build that is disproportionately
  large for "one orb widget," and a steep learning curve if Unreal isn't
  already a known tool. Confirmed technically *possible* (transparent,
  click-through, always-on-top desktop windows exist as a supported
  pattern via community plugins), but only in **packaged, not
  editor-mode**, builds — meaning every visual iteration requires a full
  package-and-relaunch cycle, not a live-reload.
- **Verdict**: Explicitly not recommended. The visual ceiling is real, but
  the engineering cost, GPU footprint, and iteration-speed penalty are
  wildly disproportionate to "a persistent desktop companion orb,"
  even accounting for this being a personal project willing to accept
  real complexity.

### E. Unity

Roughly comparable to Godot in raw visual ceiling for this specific need
(particles, shaders, post-processing all present), but: a heavier
editor/runtime footprint than Godot, less directly-documented/precedented
support for transparent desktop-overlay windows specifically (Godot has
literal project-setting checkboxes for this; Unity support was found to
lean more on manual native-plugin work), and no licensing advantage for a
non-commercial personal project that Godot's fully-open-source, zero-cost
model doesn't already match. Given comparable visual ceiling and a
meaningfully lighter footprint plus more direct precedent, Godot is the
better pick between the two for this specific need.

### Comparison at a glance

| | Qt+GLSL | Godot | Web/Three.js | Unreal | Unity |
|---|---|---|---|---|---|
| Visual ceiling | Medium | High | High | Highest | High |
| Built-in bloom/particles | No (hand-built) | Yes | Yes (libs) | Yes | Yes |
| GPU/VRAM cost | Low | Low-Med | Med | High | Med-High |
| New process/IPC | No | Yes (WS) | Yes (WS) | Yes (WS) | Yes (WS) |
| Transparency precedent | Rough edges | Proven ("desktop pet") | Risky embed / plausible standalone | Proven (plugins) | Weaker |
| Editor for live iteration | No | Yes | No (devtools) | Yes | Yes |
| Packaging burden | None | One export | None (WebView2 built in) | Very high | High |
| Engineering cost for target effects | High | Medium | Medium | Very high | Medium-high |

---

## 4. Recommended approach

**Godot 4.x, running as a separate transparent/borderless/always-on-top
window, driven by the existing Jairus Python runtime over a local
WebSocket — the same IPC pattern (and the same `websockets` dependency)
already proven in this project's Phase 13 Android Gateway.**

Why this over the equally strong Three.js/`pywebview` alternative:

1. **Most concrete, most directly-applicable transparency precedent.**
   Research surfaced an actual "transparent, borderless, always-on-top
   Godot window used as a desktop companion character" project — the
   exact shape of what's being built here. The web-tech path's strongest
   precedent (ElevenLabs' Orb) is for the *orb itself*, not specifically
   for "this exact tech embedded in a transparent always-on-top Windows
   overlay" — that half is closer to inferred than verified.
2. **Least hand-rolled code for the most requested effects.** Bloom,
   particle systems, and animation-driven state transitions are built-in,
   editor-configurable Godot features, not libraries to integrate or
   effects to hand-write.
3. **A live visual editor.** For a personal project where "what does the
   best version of this actually look like" is explicitly the open
   question, being able to drag sliders and see bloom/particles/lighting
   update live is a meaningfully faster path to a good result than
   iterating via code-reload in either alternative.
4. **Lighter, self-contained runtime.** A native Godot export has no
   browser-engine dependency and a smaller footprint than a
   Chromium-hosting process, which matters for something meant to run
   continuously in the background.

This is not a claim that Three.js/`pywebview` is a bad choice — it is the
clear fallback if the Godot PoC's transparency behavior (given the open
Windows 11 + Vulkan bug reports) proves troublesome on this specific
machine.

**Qt + `QOpenGLWidget`** is explicitly not the primary recommendation
despite its unmatched integration simplicity: the amount of hand-rolled
rendering-engine code required to reach the requested visual bar (bloom,
particles, layered materials, lighting) is large enough that a real
engine's built-in tooling wins on "reasonable engineering cost" even after
accounting for the new process/IPC overhead.

**Unreal Engine** is explicitly not recommended: highest visual ceiling,
but a disproportionate GPU/VRAM/packaging/iteration-speed cost for a
persistent background widget, even under this project's explicit
tolerance for added complexity.

### Floating UI: hybrid, with a clear ownership boundary

- **Durable, data-shaped UI stays in Qt**: History list, Tools catalog,
  Settings forms. These are inherently list/form/text-input UI that Qt
  already does well (and already has built, tested, and themed across
  Phases 2-8) — a game engine is a poor tool for scrollable data tables
  and file-picker dialogs, and there is no visual-quality reason to move
  them.
- **Transient, orb-anchored overlays move to the renderer**: the
  `EXECUTING` step checklist, the `Confirm/Cancel` prompt, the "task
  complete" toast. These are tightly coupled to the orb's moment-to-
  moment state and benefit from sharing the *same* animation/transition
  language as the orb itself (fading, sliding, and appearing in sync with
  a state change) — treating them as part of the orb's presentation
  rather than the sidebar's job. Godot renders these as its own
  screen-space UI (Godot's `Control` node system), positioned relative to
  the orb window.
- Both surfaces read from the same underlying `AssistantState`/task data;
  neither one is a second source of truth.

---

## 5. Proof of concept

Smallest experiment that validates the recommendation, **fully decoupled
from the real Jairus runtime** (no changes to `assistant_loop.py`,
`AssistantState`, or any protected file — this is throwaway/standalone
code in its own folder, e.g. `orb_renderer_poc/`):

1. **A minimal Godot 4.x project**, window settings: fixed size (match
   today's 480×480), Borderless, Transparent, Per-pixel Transparency
   Allowed, Always On Top.
2. **One scene**: a `WorldEnvironment` node with `glow_enabled = true`; one
   emissive circle/sphere as the "core"; one `GPUParticles2D` emitter for
   ambient particles; a shader parameter (or modulate color) driving core
   color and pulse scale.
3. **A `WebSocketPeer` client** in a script, connecting to
   `ws://localhost:8766` (an arbitrary local port distinct from Phase
   13's Gateway port), parsing JSON messages shaped like
   `{"state": "listening", "level": 0.4}` and driving the core
   color/pulse/particle emission rate from them.
4. **A standalone Python test script** (not part of the real app) running
   a bare `websockets` server that cycles through a few hardcoded state
   messages (`idle → listening → thinking → speaking`) every few seconds,
   purely to drive the PoC — modeled directly on `gateway_server.py`'s
   existing minimal server pattern.

**Success criteria** (directly against what was asked for):

- [ ] Window renders transparently over the real desktop (no black box,
      no visible window chrome).
- [ ] Animation runs smoothly in real time (target: comfortably ≥60 FPS
      given how simple this scene is).
- [ ] Bloom/glow is visibly GPU-accelerated post-processing, not a flat
      fill.
- [ ] The window is borderless and stays always-on-top.
- [ ] The scene visibly changes (color, pulse, particle behavior) within
      a perceptible delay of a state message arriving over the socket.
- [ ] The Godot process launches and exits cleanly from a Python
      `subprocess.Popen()` call, with no orphaned process left behind.

If every box above is checked, the recommendation is validated and real
integration work (section 6) can begin. If transparency specifically
fails or looks unreliable on this machine's GPU/driver/Windows build, the
same PoC script structure (a state-driven WebSocket client) is directly
portable to the Three.js/`pywebview` fallback with minimal rework, since
the IPC contract and test harness don't depend on which renderer consumes
them.

---

## 6. Migration strategy

1. **Build and validate the PoC** (section 5) with zero changes to the
   real Jairus codebase.
2. **Add a small, additive `renderer_bridge` module** to the real
   codebase: a local WebSocket server (reusing the existing `websockets`
   dependency) that `assistant_loop.py`/`AssistantState` can be hooked up
   to push state changes into — mirroring, not duplicating, the existing
   `gateway_server.py` pattern. This is new code, not a rewrite of
   anything: `AssistantState` keeps its exact current read API for the
   existing Qt `OrbWidget`, and gains a small notification hook (or a
   poll-based bridge thread reading `get_snapshot()`/`get_activity_snapshot()`
   on a timer, avoiding any change to `AssistantState`'s writers at all)
   that also forwards the same data over the socket.
3. **Expand `AssistantState`'s state vocabulary** (the gap flagged in
   section 1) as its own small, separate, mechanical change — same
   pattern as Phase 8's `action_type` — so there is something meaningful
   for the richer renderer to actually display. This can and should
   happen independently of the rendering-technology work.
4. **Launch the Godot renderer as a subprocess from `main.py`**,
   positioned to replace `OrbWidget`'s visual role while the surrounding
   `QMainWindow` (sidebar, History, Tools, Settings, health indicator)
   is preserved exactly as-is. `main.py`'s current
   `run_orb(state)` call is the natural seam: it can grow a mode that
   launches the Godot subprocess (and manages its lifecycle) instead of
   (or ahead of) constructing `OrbWidget`.
5. **Keep the existing `QPainter`-based `OrbWidget` as an explicit
   fallback path**, selected if the Godot subprocess fails to launch, if
   no capable GPU is present, or via a config flag — this directly serves
   "the orb should be replaceable without modifying the core agent
   architecture," in both directions.
6. **Iterate on visual richness entirely inside the Godot project** from
   this point on (rings, energy arcs, camera movement, per-state
   transition choreography) — once the JSON state contract is stable, no
   further Python decision-logic changes are needed to keep improving the
   visual result.

At every step, `AssistantState` remains the single source of truth and
the Agent Core/Tool Registry/Policy Engine are never touched — this is
purely a new consumer of state that already exists, plus a small,
additive expansion of that state's vocabulary.

---

## 7. Risks

Stated plainly, not softened:

- **GPU/VRAM**: a second GPU-accelerated process running continuously in
  the background is nonzero cost, even if lean by design — real on a
  machine also used for gaming or other GPU-heavy work, and needs
  measuring in the PoC rather than assumed away.
- **Process reliability**: a second executable Python must launch and
  supervise is a new failure class that doesn't exist in the current
  single-process design (crash, hang, fails to bind its window, gets
  orphaned if Jairus itself crashes) — needs explicit supervision logic
  (health-check, restart-on-crash, guaranteed-kill-on-shutdown), none of
  which exists yet.
- **Window-management**: keeping a separate, independently-owned OS
  window (the Godot renderer) visually in sync with the Qt window (e.g.
  if the user drags the Qt window, or if they're meant to look like one
  cohesive app) requires new plumbing — polling/pushing window geometry
  between the two processes — that has no equivalent today.
- **Transparency limitations**: the specific open Godot 4.5 + Windows 11
  + Vulkan bug (transparent window at maximized/screen size goes black
  when focused) is a real, currently-tracked upstream issue; low risk for
  a small fixed-size window but worth re-verifying against whatever Godot
  version is current at PoC time, and monitoring across future Godot
  updates.
- **Packaging**: one additional exported executable to build and keep in
  sync with the rest of the app — small for a single personal machine,
  but real, ongoing overhead compared to today's single Python process.
- **Debugging**: a real cross-process, cross-language boundary (Python ⇄
  GDScript over WebSocket) is objectively harder to reason about than a
  single-process Qt/Python bug — a defect could live in either side or in
  the contract between them.
- **Performance of the IPC channel itself**: JSON-over-WebSocket is fine
  for state changes that happen a handful of times per interaction
  (exactly what's proposed here). It would **not** be an appropriate
  channel for very high-frequency data (e.g. streaming raw mic amplitude
  at audio-callback rate to drive per-frame shader input) — if live audio
  reactivity beyond the existing coarse `level` value is ever wanted, that
  specific data path would need its own lighter-weight channel (e.g.
  shared memory), not more JSON messages.
- **Maintenance**: two codebases and two skillsets (Python + GDScript)
  going forward, versus one today — a real, ongoing cost that this
  project is explicitly willing to accept for the visual result, but
  should not be understated.

---

## 8. Explicit recommendation

> ## RECOMMENDED PATH
>
> **Godot 4.x as a separate transparent/borderless/always-on-top renderer
> process for the orb specifically, communicating with the existing
> Jairus Python runtime over a local WebSocket (reusing the
> already-proven `websockets` + Phase-13-style server pattern), while the
> entire existing Qt sidebar/History/Tools/Settings/health-indicator UI
> from Phases 1-8 is preserved unchanged.** Transient, orb-anchored
> overlays (execution checklists, confirmation prompts, completion
> toasts) move into the Godot renderer alongside the orb; durable,
> data-shaped UI (History, Tools, Settings) stays in Qt.
>
> **Exact next implementation step**: build the standalone proof of
> concept from section 5 — a bare Godot project with a transparent
> always-on-top window, a glow-enabled emissive core, one particle
> emitter, and a `WebSocketPeer` client — driven by a throwaway Python
> script that sends a few hardcoded state messages over a local
> WebSocket. Nothing in the real Jairus codebase changes until every box
> in section 5's success criteria is checked on this actual machine.

---

## Research sources

Findings above on Qt/PySide6 transparency, Godot's transparent-window
support and known issues, Unreal Engine's transparent-window plugin
ecosystem, and the ElevenLabs Orb / Three.js precedent were gathered via
web search on 2026-09-13:

- [PySide6.QtOpenGLWidgets.QOpenGLWidget — Qt for Python](https://doc.qt.io/qtforpython-6/PySide6/QtOpenGLWidgets/QOpenGLWidget.html)
- [Window set with transparent background... makes it borderless — godotengine/godot#103658](https://github.com/godotengine/godot/issues/103658)
- [Vulkan transparent window stopped working on Windows 11 — godotengine/godot#111513](https://github.com/godotengine/godot/issues/111513)
- [Per Pixel Transparency misbehaving/broken in 3.2.2-stable on Windows — godotengine/godot#39914](https://github.com/godotengine/godot/issues/39914)
- [Escape the box: Godot as an overlay over desktop environment — godot-proposals#5388](https://github.com/godotengine/godot-proposals/discussions/5388)
- [Desktop Pet project (DigiKey Maker.io)](https://www.digikey.com/en/maker/projects/desktop-pet/994f9b5997fa4d6899c022c9b23724a6)
- [Orb | ElevenLabs UI](https://ui.elevenlabs.io/docs/components/orb)
- [Giving an AI a Body: Building a Desktop Companion Avatar for macOS](https://dev.to/xadenai/giving-an-ai-a-body-building-a-desktop-companion-avatar-for-macos-5el9)
- [KiloSnow desktop AI assistant (GitHub)](https://github.com/PDYAM/KiloSnow)
- [Easy Desktop Transparency System — Fab (Unreal)](https://www.fab.com/listings/0e0eb059-9caa-468d-87ed-066251bda955?lang=en)
- [Request: Per-pixel transparent, click-configurable Slate window in standalone/shipping — Epic Dev Community](https://forums.unrealengine.com/t/request-per-pixel-transparent-click-configurable-slate-window-in-standalone-shipping-desktop-overlays/2671911)
- [historia-Inc/WindowTransparency — UE5 plugin (GitHub)](https://github.com/historia-Inc/WindowTransparency)
- [Changing CSS to achieve a transparent background breaks rendering — Qt Forum](https://forum.qt.io/topic/162799/changing-css-to-achieve-a-transparent-background-breaks-rendering)
- [QWebEngineView with transparent bg always on top — Qt Forum](https://forum.qt.io/topic/118488/qwebengineview-with-transparent-bg-always-on-top)
- [Using WebSockets — Godot Engine documentation](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html)
- [Seamless Inter-Process Communication with Godot's execute_with_pipe](https://dev.to/jeankouss/seamless-inter-process-communication-with-godots-executewithpipe-537i)
- [Glow Shader in Shadertoy — inspirnathan.com](https://inspirnathan.com/posts/65-glow-shader-in-shadertoy/)
- [Bloom (shader effect) — Wikipedia](https://en.wikipedia.org/wiki/Bloom_(shader_effect))
