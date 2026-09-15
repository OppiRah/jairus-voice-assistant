# JAIRUS UI RESET AUDIT

Audit performed ahead of removing the orb visual implementation and
starting Jairus's visual identity design from zero. Audit only — no code
changes are described as already done in this document; see the
cleanup/archival commit that follows this one for what was actually
changed.

## 1. Current renderer architecture

```
AssistantState (status/level/activity/history/health)  ← single source of truth
        │ read-only, poll-based
        ├──────────────────────────────┐
        ▼                              ▼
orb_widget.py: OrbWindow (Qt shell)    src/jairus/interfaces/renderer/bridge.py
  Sidebar / HomePage / History /         (WebSocket server, port 8767, pushes
  Tools / Settings / HealthIndicator      {"state","level","activity"} JSON on
        │                                 change — generic, orb-agnostic)
        ▼                                       │
  HomePage's visual slot:                       ▼
   - OrbWidget (QPainter rings/core)     external renderer process
     if renderer_mode == "qt_orb"          (currently: Godot project at
   - GodotModeNotice (placeholder text)     src/jairus/interfaces/renderer/
     if renderer_mode == "godot"            godot_project/)
```

`main.py` picks the mode via `jairus.configuration.settings.get("renderer_mode")`
(`"qt_orb"` default, or `"godot"`), optionally launches the Godot `.exe` as
a supervised subprocess (`_try_launch_godot()`), and starts `bridge.py`'s
WebSocket thread only if that launch succeeds. `AssistantState` never
knows a renderer exists; both consumption paths are pure readers.

## 2. Orb-specific files

| File | What's orb-specific |
|---|---|
| `orb_renderer_poc/` (whole folder: `README.md`, `test_driver.py`, `godot_project/*`) | Explicitly self-declared "zero connection to the real Jairus application" — standalone throwaway PoC. 100% orb. |
| `src/jairus/interfaces/renderer/godot_project/*` (`orb_scene.tscn`, `orb_controller.gd` [101 KB], `orb_arc_ribbon.gdshader`, `orb_energy_wisp.gdshader`, `orb_glass_shell.gdshader`, plus untracked `billboard_wisp_poc.gdshader`, `facet_fake_normal.gdshader`, `facet_poc_test.gd/.tscn`, `glass_poc_*.gd/.tscn/.gdshader`, `noise_core_poc.gdshader`, `silhouette_poc_test.gd/.tscn`, `vfx_technique_poc_test.gd/.tscn`, plus `project.godot`/`.gitignore` scaffolding for this specific scene) | Every scene/script/shader here renders rings, plates, core, ribbons, particles, glass shells. 100% orb visual content. |
| `orb_widget.py` — only the `OrbWidget` class (QPainter rings/core/highlight drawing) and `GodotModeNotice` (orb/Godot-flavored placeholder text) | Orb-specific. The rest of this file is not — see section 3. |
| `theme.py` — only the `ORB_COLORS` dict (status→RGB mapping consumed solely by `OrbWidget`) | Orb-specific by consumer, not by concept. |
| Docs: `ORB_RENDERER_INVESTIGATION.md`, `JAIRUS_ORB_VFX_TECHNIQUE_REFERENCE.md`, `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md`, `ORB_CONCEPT_GAP_ANALYSIS.md`, `ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md`, `ORB_V2_DESIGN.md`, `ORB_VFX_TECHNIQUE_ANALYSIS.md`, `orb_renderer_poc/README.md` | Pure orb visual investigation/design docs. |

`ORB_RENDERER_INVESTIGATION.md` is the one partial exception: sections 1,
2, and 6 contain real, reusable reasoning about the renderer boundary/IPC
contract (not orb-specific), mixed in with sections 3–5 and 7–9 which are
pure orb visual/material investigation. The reusable parts were extracted
into a new `RENDERER_BRIDGE.md` before this document was archived.

## 3. Reusable renderer infrastructure

- `src/jairus/interfaces/renderer/bridge.py` — fully generic; pushes
  whatever `AssistantState` currently says, names no visual concept.
- `assistant_state.py` (`AssistantState`) — 4-value status enum + level +
  activity/history + health. Not orb-specific; one comment mentions
  "drives how much the orb pulses" (cosmetic wording only).
- `orb_widget.py`'s shell: `OrbWindow`, `Sidebar`, `HomePage` (as a layout
  container), `HistoryPage`, `ToolsPage`, `SettingsPage`,
  `HealthIndicator`, `ActivityPanel`, `run_orb()`. This is the actual Qt
  application (sidebar nav, History, Tools catalog, Settings, health
  indicator) — it merely hosts the orb widget in one region of
  `HomePage`'s layout. None of it draws or assumes an orb.
- `theme.py` minus `ORB_COLORS` — shared colors/spacing/icons/stylesheet.
- `main.py`'s `renderer_mode` config switch + `_try_launch_godot()`'s
  subprocess-supervision pattern (launch → poll-check → clean
  terminate/kill) — generic "launch an external renderer process"
  infrastructure, not tied to what that process actually renders.
- `jairus_config.json` settings keys `renderer_mode` /
  `godot_executable_path` (in `src/jairus/configuration/settings.py`) —
  config plumbing, not visual content.

## 4. Backend dependencies

None. Verified: Agent Core, Policy Engine, Tool Registry/Executor,
Command Gateway, Task Manager, Android Gateway never import or reference
`orb_widget.py`, `theme.py`, or the renderer bridge. The only files that
import `orb_widget`/launch the Godot process/start the bridge are
`main.py` itself. `command_gateway.py`, `settings.py`, and
`gateway_server.py` each contain one passing comment mentioning "orb" —
informational, not a real dependency.

## 5. Tests affected

There is no pytest/test-runner configuration anywhere in this repo (no
`pyproject.toml`, `conftest.py`, or CI config found). The only files
matching `*test*` are:
- `orb_renderer_poc/test_driver.py` — a throwaway manual PoC driver
  script (not an automated test), goes with the PoC folder.
- `src/jairus/interfaces/renderer/godot_project/glass_poc_test.gd/.tscn`
  — a manual Godot POC scene, not an automated test, goes with the
  godot_project cleanup.
- `scripts/test_gateway_client.py` — unrelated (Android Gateway),
  untouched.

No automated test suite is broken by this change.

## 6. Documentation affected

- The 7 dedicated orb docs + `orb_renderer_poc/README.md` (section 2) —
  archived.
- `ORB_RENDERER_INVESTIGATION.md` — archived after extracting sections
  1/2/6's reusable renderer-boundary reasoning into `RENDERER_BRIDGE.md`.
- `UI_UX_CONTEXT.md` — not orb-specific (covers Android, error/
  connection/cancellation UX, accessibility — all reusable), but its
  "Windows Desktop" section asserted "the existing reactive orb is
  Jairus' product identity — preserve it," which is now false and was
  corrected to state the visual is being redesigned from zero, without
  asserting any new direction.
- `README.md` — had a short "New: a visual companion (the orb)" section
  describing current user-facing behavior that would become inaccurate
  once `OrbWidget` was removed; corrected to describe the neutral
  placeholder honestly.
- `RECONNAISSANCE.md` — mentions the orb extensively, but it's already
  describing a pre-migration, already-deleted `orb_ui.py` (pygame) as
  historical record of Phase-1-era architecture. Out of scope: it
  documents something already gone, unrelated to this cleanup. Left
  untouched.

## 7. Safe deletion plan

1. `git mv` the following into a new `archive/orb_v1/` directory
   (preserves history, satisfies "archive valuable R&D" rather than
   hard-deleting):
   - `orb_renderer_poc/` → `archive/orb_v1/orb_renderer_poc/`
   - `src/jairus/interfaces/renderer/godot_project/` (entire directory)
     → `archive/orb_v1/godot_project/`
   - `ORB_RENDERER_INVESTIGATION.md`, `JAIRUS_ORB_VFX_TECHNIQUE_REFERENCE.md`,
     `JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md`, `ORB_CONCEPT_GAP_ANALYSIS.md`,
     `ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md`, `ORB_V2_DESIGN.md`,
     `ORB_VFX_TECHNIQUE_ANALYSIS.md` → `archive/orb_v1/docs/`
2. Extracted a new `RENDERER_BRIDGE.md` capturing only the reusable,
   orb-agnostic parts of `ORB_RENDERER_INVESTIGATION.md` before archiving
   it.
3. In `orb_widget.py`: deleted the `OrbWidget` class and `GodotModeNotice`
   class; replaced `HomePage`'s visual slot with one honest, neutral
   `VisualPlaceholder` widget (no orb/Godot framing) — same fixed
   footprint, so the rest of the layout is untouched.
4. In `theme.py`: deleted the `ORB_COLORS` dict and its comment block
   (orphaned once `OrbWidget` was gone), and the now-unused
   `AssistantStatus` import.
5. Updated wording only (no logic changes) in `main.py`, `bridge.py`'s
   docstring, `settings.py`'s comment, `README.md`, and `UI_UX_CONTEXT.md`
   where they asserted or described the orb as current/target behavior,
   and fixed doc-path references to the now-archived investigation doc.
6. Left `main.py`'s `renderer_mode`/subprocess-launch mechanism and
   `bridge.py` completely untouched — they are the renderer boundary
   being preserved.

## 8. Minimal renderer contract to preserve

- `AssistantState.get_snapshot()` → `(status, level)`,
  `get_activity_snapshot()` → `(activity, history)`, `get_health_status()`.
- `bridge.py`'s JSON shape: `{"state": str, "level": float, "activity": str}`,
  pushed over WebSocket on port 8767 on change.
- `main.py`'s `renderer_mode` (`"qt_orb"` vs `"godot"` naming stays as-is
  for now — renaming it is a design decision for later, not part of this
  cleanup) config switch, subprocess launch/poll/terminate pattern.
- `orb_widget.py`'s `OrbWindow` shell (`Sidebar`, `HomePage`,
  `HistoryPage`, `ToolsPage`, `SettingsPage`, `HealthIndicator`,
  `ActivityPanel`, `run_orb()`).
- `theme.py`'s color/spacing/icon/stylesheet system (minus `ORB_COLORS`).

## 9. Recommended clean starting point

After cleanup: `HomePage`'s visual slot shows one honest "no visual yet"
placeholder regardless of `renderer_mode`; the external-process
launch/bridge machinery stays wired up and functional but dormant
(nothing currently lives at the Godot project path unless/until a new
design chooses to use Godot at all — that choice hasn't been made); no
`.tscn`/`.gd`/shader files exist anywhere outside `archive/`; no doc in
the live tree describes or assumes an orb. The next visual design
investigation starts against a real, working, tested app shell with a
genuinely empty presentation slot.
