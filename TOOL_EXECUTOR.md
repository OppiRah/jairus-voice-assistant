# Jairus — Phase 6: Tool Executor

**Migration step:** Phase 6 of `JAIRUS_ARCHITECTURE.md` (Part 14.8), giving
the Phase 5 Tool Registry an executor that can actually run a tool by name.

**One-sentence summary:** `execute_tool("media.pause", {})` (and the other
eight `media.*` names) now really pauses/resumes/plays/etc. by calling the
matching EXISTING `player_action.py` function — but nothing in the live
assistant calls `execute_tool()` yet.

---

## What was built

### New: `src/jairus/tools/executor.py`

```python
def execute_tool(tool_name: str, arguments: dict) -> ToolResult
```

What it does, in order:

1. Prints `[executor] running {tool_name}`.
2. Looks `tool_name` up via Phase 5's `get_tool()`. Not registered →
   returns `ToolResult(success=False, error=..., failure_category=FailureCategory.NOT_FOUND)`
   immediately, nothing is run. (This also means the registry must already
   be populated — e.g. by calling `register_media_tools()` — before any
   call can succeed; this module doesn't register anything itself.)
3. Otherwise dispatches to the matching `player_action.py` function:

   | Tool name | Calls | Arguments used |
   |---|---|---|
   | `media.play` | `play_song(arguments)` | `arguments` passed straight through — it's already `{"title":..., "artist":...}`, exactly the shape `play_song(intent)` expects |
   | `media.queue` | `start_queue(arguments.get("songs", []))` | `songs` list |
   | `media.pause` | `pause_music()` | none |
   | `media.resume` | `resume_music()` | none |
   | `media.skip` | `skip_music()` | none |
   | `media.correct` | `correct_song()` | none — return value (`bool`) becomes `data={"switched": ...}` |
   | `media.volume_up` | `adjust_volume("up")` | none |
   | `media.volume_down` | `adjust_volume("down")` | none |
   | `media.now_playing` | `get_now_playing()` | none — return value becomes `data={"now_playing": ...}` |

4. The call is wrapped in `try/except`: success →
   `ToolResult(success=True, data=...)`; an exception is caught (not
   propagated) → `ToolResult(success=False, error=str(exc),
   failure_category=FailureCategory.EXECUTION_ERROR)`, plus an
   `[executor] {tool_name} failed: {exc}` print.

`player_action` is imported lazily, inside the function that builds the
handler map — not at module load — so importing `jairus.tools` never
requires `player_action.py`'s own imports (Playwright, pygame, ctypes) to
succeed first. Same reasoning `command_gateway.py` used for its lazy
`handle_command` import in Phase 3.

None of `player_action.py`'s eight functions (`play_song`, `start_queue`,
`pause_music`, `resume_music`, `skip_music`, `correct_song`,
`adjust_volume`, `get_now_playing`) were modified — they're imported and
called, exactly as `handle_command()` already does.

### Changed: `src/jairus/tools/__init__.py`

Now also re-exports `execute_tool`.

---

## What was explicitly NOT touched

- **`handle_command()`, `intent_parser.py`, `command_gateway.py`,
  `task_manager.py`.** Byte-for-byte identical to Phase 5. `git diff` on
  `handle_command()`'s file and `command_gateway.py` is empty.
- **`player_action.py`.** Not modified — its eight functions are called by
  the executor exactly as they already were by `handle_command()`.
- **No Agent Core, no LLM-driven tool selection.** Nothing decides *which*
  tool to call from a natural-language request; `execute_tool()` only runs
  the tool it's told to run, by name. Per the architecture's own
  sequencing, that decision-making is Part 14.10 ("Introduce the Real
  Agent Loop"), which comes after this phase.
- **The user-facing behaviour.** Run `python main.py`, say "hey jairus",
  give a command — it behaves exactly as before, because nothing calls
  `execute_tool()` outside of tests. This is the same "built but unused"
  posture Phase 5 gave the registry itself.

## What Phase 6 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Wiring `execute_tool()` into `handle_command()`'s or any live dispatch | Part 14.10–14.13 (Agent Core, then legacy-routing removal) |
| Input-schema validation of `arguments` before calling a handler | Policy Engine / later hardening |
| Timeout enforcement (`ToolDefinition.timeout_seconds` is recorded but not read here) | Tool Executor hardening, later |
| Retry behaviour per `FailureCategory` | Part 33, later |
| Non-media tool handlers | once non-media tools exist (Part 14.16–14.17 etc.) |

---

## Verification performed

`python -m compileall` is clean on the new and changed files. A test
(`venv` interpreter) that monkeypatches the eight `player_action.py`
functions (so no real browser/audio backend is touched — the same
mock-the-hardware-edge approach used to stub `handle_command` in earlier
phases) confirmed, after calling `register_media_tools()`:

- Each of the nine `media.*` tools reaches the correct monkeypatched
  `player_action` function, with the arguments the executor is documented
  above to pass, and `ToolResult.success is True`.
- `media.correct` and `media.now_playing`'s return values come back in
  `ToolResult.data` (`{"switched": ...}` / `{"now_playing": ...}`).
- A monkeypatched function that raises produces
  `ToolResult(success=False, failure_category=FailureCategory.EXECUTION_ERROR)`
  with `error` set to the exception's message, and does not raise.
- `execute_tool("media.does_not_exist", {})` returns
  `ToolResult(success=False, failure_category=FailureCategory.NOT_FOUND)`
  without touching `player_action` at all.
- `git diff` on `assistant_loop.py` (where `handle_command()` lives) and
  `src/jairus/application/commands/command_gateway.py` is empty — confirmed
  after this phase's changes.
