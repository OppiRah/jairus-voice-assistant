# Orb Renderer PoC

Standalone, throwaway proof of concept validating
[`ORB_RENDERER_INVESTIGATION.md`](../ORB_RENDERER_INVESTIGATION.md)
section 5's recommendation (Godot 4.x as a separate transparent overlay
process, driven by the real Jairus runtime over a local WebSocket).

**This folder has zero connection to the real Jairus application.** It
does not import `assistant_loop.py`, `assistant_state.py`,
`orb_widget.py`, `main.py`, or anything under `src/jairus/`, and nothing
in the real app imports from here. If this folder is deleted tomorrow,
nothing about the real running app changes.

It uses port **8766** — deliberately different from **8765**, the real
Jairus Android Gateway's port (Phase 13). The two must never collide.

## What's here

- `godot_project/` — a minimal Godot 4.x project: a transparent,
  borderless, always-on-top 480×480 window showing one emissive/glowing
  "core" sphere with bloom, ambient particles, and a breathing pulse
  animation. `orb_controller.gd` connects to `ws://localhost:8766` and
  updates the core's color/pulse/particle intensity from whatever JSON
  state message it last received.
- `test_driver.py` — a bare Python WebSocket server (same `websockets`
  package the real project already depends on) that sends a hardcoded
  `idle → listening → thinking → speaking → idle` sequence every few
  seconds, forever, so you can watch the orb visibly react.

## Running it

1. **Start the driver first** (it needs to be listening before Godot
   tries to connect):

   ```
   cd orb_renderer_poc
   python test_driver.py
   ```

   You should see `[test_driver] listening on ws://localhost:8766`.

2. **Launch the Godot project.** Either:

   - Open Godot, "Import" this project (`orb_renderer_poc/godot_project/`),
     and press Play (F5) in the editor, **or**
   - From the command line, if your Godot executable is on `PATH` or you
     have its full path:

     ```
     godot --path orb_renderer_poc/godot_project
     ```

3. A small transparent window should appear with a glowing, pulsing orb.
   Every few seconds it should change color and pulse intensity as
   `test_driver.py` cycles through states:

   | state | color |
   |---|---|
   | idle | blue |
   | listening | green |
   | thinking | violet |
   | speaking | gold |

4. Close the Godot window, then `Ctrl+C` in the `test_driver.py` terminal
   to stop it.

## What this does and doesn't prove

This validates the specific yes/no questions in
`ORB_RENDERER_INVESTIGATION.md` section 5 — whether Godot can render a
transparent GPU-accelerated orb in real time and react to state pushed
over a local WebSocket from Python. It is **not** a preview of the final
visual design (no rings, energy arcs, or floating UI cards yet), and it
makes no changes to, and has no effect on, the real Jairus app.
