# Jairus UI Reset — Verification

Verification pass after removing the orb visual implementation
(`JAIRUS_UI_RESET_AUDIT.md` → cleanup commit). No design/implementation
work was done in this pass — checks only.

## Tests

No pytest/test-runner configuration exists in this repo (confirmed in the
audit, section 5). Nothing to run.

## Static checks

- `grep`'d the whole repo for `OrbWidget`, `ORB_COLORS`, `GodotModeNotice`
  (the three symbols deleted from `orb_widget.py`/`theme.py`): zero
  remaining references anywhere.
- `python -m py_compile` over every tracked `.py` file in the repo: all
  compile cleanly (one pre-existing, unrelated `SyntaxWarning` in
  `player_action.py` about a Windows path escape sequence — not touched by
  this change, not new).

## Import / construction checks (real PySide6, real Qt objects, no event loop)

- `theme.py` imports cleanly; `ORB_COLORS` confirmed absent.
- `orb_widget.py` imports cleanly; `OrbWidget`/`GodotModeNotice` confirmed
  absent, `VisualPlaceholder` confirmed present.
- Constructed a real `AssistantState` and a real `orb_widget.OrbWindow` in
  **both** renderer modes (`godot_mode=False` and `godot_mode=True`) —
  both build the full widget tree (sidebar, stack, all four pages, health
  indicator) with no exceptions. This is the actual window `main.py`
  shows; it was not just imported, it was instantiated.
- `src/jairus/interfaces/renderer/bridge.py` imports cleanly.
- `main.py` imports cleanly (which transitively imports `assistant_loop.py`,
  `assistant_state.py`, `tts.py`, etc. — the whole real startup chain
  compiles and loads without error).

## Renderer fallback behavior (real hardware, not simulated)

This machine has a real Godot executable configured in the local,
gitignored `jairus_config.json` (`godot_executable_path`). Calling
`main._try_launch_godot()` directly launched that real Godot binary
pointed at `src/jairus/interfaces/renderer/godot_project` — which no
longer exists (archived to `archive/orb_v1/godot_project/` in the cleanup
commit). Observed behavior:

```
[main] Godot exited immediately (code 1); falling back to the built-in Qt window
```

`_try_launch_godot()` returned `None`, exactly the documented fallback
contract in `RENDERER_BRIDGE.md` — no crash, no hang, no exception
propagated. Checked `tasklist` immediately afterward: no orphaned Godot
process left running. This confirms the exact scenario the audit flagged
as now-dormant (`renderer_mode = "godot"` with no project at the expected
path) degrades safely rather than crashing Jairus.

## Full runtime start (`python main.py`)

Not run end-to-end in this pass. `main()` starts the real voice pipeline
(wake-word model load, mic stream, Ollama connection) on a background
thread, which is out of scope for a UI-boundary verification and
inappropriate to launch unattended. Everything upstream of that — every
module `main()` depends on, including the entire desktop window it builds
— was independently import-checked and construction-checked above, which
is the part this cleanup actually touched.

## Remaining orb-specific dependencies in the live tree

None found. Every orb-specific file lives under `archive/orb_v1/`. The
only remaining "orb" wording left in the live tree is:
- `RECONNAISSANCE.md`, which documents the already-deleted, pre-migration
  `orb_ui.py` (pygame) as historical record — out of scope, flagged and
  left alone per the audit.
- `assistant_state.py`, one comment: `# 0.0-1.0, drives how much the orb
  pulses` — cosmetic wording on a field (`level`) that remains genuinely
  generic (any future visual will still want a 0–1 intensity value); not
  functionally tied to the orb. Left as a very minor, low-value wording
  cleanup rather than touched, since editing it would mean modifying
  `assistant_state.py` for a change with zero functional purpose.

## Conclusion

The orb visual implementation is fully removed from the live tree and
archived. The renderer boundary (`AssistantState` → `bridge.py` →
WebSocket → external process, and the in-window Qt shell) is intact,
tested at the construction level, and degrades safely when pointed at a
renderer that no longer exists. No replacement visual was implemented.
Stopping here per the task boundary.
