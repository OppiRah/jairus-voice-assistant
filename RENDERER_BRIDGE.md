# Renderer Bridge — Architecture

The reusable, visual-agnostic part of what was originally investigated in
`archive/orb_v1/docs/ORB_RENDERER_INVESTIGATION.md`. That document's full
technology comparison and orb-specific findings are archived; this page
keeps only the part of the architecture that still applies regardless of
what Jairus's visual identity ends up being.

## The presentation boundary

```
Jairus Runtime (assistant_loop.py, AssistantState, Agent Core, tools)
        │
        │  state changes (status, level, current-activity, history, health)
        ▼
AssistantState.get_snapshot() / get_activity_snapshot() / get_health_status()
        │
        ├── read directly, in-process ──────────────► orb_widget.py's Qt shell
        │                                              (Sidebar/HomePage/History/
        │                                               Tools/Settings/health
        │                                               indicator)
        │
        └── read on a poll loop, pushed over a ──────► an external renderer
            local WebSocket (bridge.py, port 8767)       process (out-of-process,
                                                           its own window)
```

Whatever renders Jairus's visual identity — in-process or out-of-process —
is a **read-only client** of `AssistantState`. It never calls into the
Agent Core, Tool Registry, Policy Engine, or `handle_command()`. This
holds regardless of rendering technology; only *how* state crosses the
process boundary changes.

## The bridge contract

`src/jairus/interfaces/renderer/bridge.py` runs a local WebSocket server
(`localhost:8767`) that polls `AssistantState` every 150ms and sends a
message only when it actually changed:

```json
{"state": "listening", "level": 0.42, "activity": "Searching YouTube…"}
```

`start_bridge_thread(state)` starts this on its own daemon thread; it is
started by `main.py` only when an external renderer process has actually
launched (see below) — there's no reason to run a WebSocket server for a
renderer that isn't there.

## Renderer selection & process supervision (`main.py`)

`jairus.configuration.settings.get("renderer_mode")` selects between:

- `"qt_orb"` (default): no external process. The Qt shell's own visual
  slot (`orb_widget.HomePage` → `VisualPlaceholder`, or whatever real
  visual eventually replaces it) is what the user sees.
- `"godot"`: `main.py`'s `_try_launch_godot()` launches
  `settings.get("godot_executable_path")` as a subprocess pointed at
  `src/jairus/interfaces/renderer/godot_project/`, waits
  `_LAUNCH_CHECK_DELAY_SECONDS`, and checks `proc.poll()` to confirm it's
  genuinely still running (not just that `Popen()` didn't raise) before
  treating the launch as successful. Any failure — missing/invalid
  executable, `OSError`, or an immediate exit — falls back to `"qt_orb"`
  automatically. On window close, `run_orb()` sends `terminate()`, then
  escalates to `kill()` if the process doesn't exit within 5 seconds, so
  closing the app never leaves an orphaned renderer process behind.

This launch/supervise pattern is generic: it doesn't assume Godot
specifically beyond the config keys' current naming, and nothing about it
assumes what the launched process actually renders. There is currently no
project at `src/jairus/interfaces/renderer/godot_project/` — `"godot"`
mode is dormant until a real renderer is built there.

## What's still true regardless of what Jairus looks like

- `AssistantState` remains the single source of truth; nothing here ever
  writes to it.
- The Agent Core, Tool Registry, Policy Engine, and command/task lifecycle
  are never imported by, or reachable from, any renderer.
- A renderer can be swapped, replaced, or run in-process vs.
  out-of-process without any change to `AssistantState`, the Agent Core,
  or the tool system.
