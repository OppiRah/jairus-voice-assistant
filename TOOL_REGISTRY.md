# Jairus — Phase 5: Tool Registry

**Migration step:** Phase 5 of `JAIRUS_ARCHITECTURE.md` (Part 14.7),
implementing the Tool Registry from Part 15 (tool properties) and Part 17
(naming convention), populated with the assistant's EXISTING media
capabilities as data.

**One-sentence summary:** the assistant's nine media actions now each have a
`ToolDefinition` (name, description, input schema, permission level) sitting
in a queryable registry — nothing executes through it yet.

---

## What was built

### New: `src/jairus/tools/registry.py`

```python
def register_tool(definition: ToolDefinition) -> None
def get_tool(name: str) -> ToolDefinition | None
def list_tools() -> list[ToolDefinition]
```

A plain lookup table, backed by one module-level dict (`_TOOLS: dict[str,
ToolDefinition]`), matching the in-memory style already used by
`task_manager.py`. `register_tool` registers or replaces by `name`;
`get_tool` and `list_tools` never raise — an unknown name gets `None`.

### New: `src/jairus/tools/media_tools.py`

Defines `MEDIA_TOOLS: list[ToolDefinition]` — one entry per action
`handle_command()` (`assistant_loop.py`) already dispatches, matching the
actions `intent_parser.py`'s `SYSTEM_PROMPT` can produce:

| Tool name | Mirrors action | permission_level | requires_confirmation |
|---|---|---|---|
| `media.play` | `play` | `HARMLESS` | `False` |
| `media.queue` | `queue` | `HARMLESS` | `False` |
| `media.pause` | `pause` | `HARMLESS` | `False` |
| `media.resume` | `resume` | `HARMLESS` | `False` |
| `media.skip` | `skip` | `HARMLESS` | `False` |
| `media.correct` | `correct` | `HARMLESS` | `False` |
| `media.volume_up` | `volume_up` | `HARMLESS` | `False` |
| `media.volume_down` | `volume_down` | `HARMLESS` | `False` |
| `media.now_playing` | `whats_playing` | `HARMLESS` | `False` |

All nine are `PermissionLevel.HARMLESS` — media control is one of the Level
0 examples given in Part 25 itself. `media.play` and `media.queue` carry a
minimal `input_schema` (title/artist, and a list of song dicts,
respectively); the other seven take no arguments so their `input_schema` is
`{}`.

**Registration is explicit, not an import-time side effect.** Importing
`media_tools` registers nothing by itself — you must call
`register_media_tools()`. Today, the only caller of `register_media_tools()`
is the Phase 5 verification test; nothing in the running assistant calls it.

### New: `src/jairus/tools/__init__.py`

Re-exports `register_tool`, `get_tool`, `list_tools`, `MEDIA_TOOLS`,
`register_media_tools`.

---

## What was explicitly NOT touched

- **`command_gateway.py`, `task_manager.py`.** Untouched from Phase 4.
- **`handle_command()`'s internals.** The if/elif action dispatch is still
  byte-for-byte identical to Phase 3/4 — it does not look at the registry.
- **`ToolDefinition`** (`domain/tools/tool_definition.py`, Phase 2). Used
  as-is; no fields added or changed.
- **No Tool Executor.** Nothing invokes a tool's underlying implementation
  (`play_song`, `pause_music`, etc.) through the registry — the registry
  only holds metadata.
- **No Policy Engine.** `permission_level` and `requires_confirmation` are
  recorded on each definition but nothing reads them to gate anything yet.

## What Phase 5 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Anything actually routing through `get_tool()`/`list_tools()` outside tests | Part 14.10+ (Tool Executor / Agent Core) |
| Tool Executor (calling a tool's real implementation) | later phase |
| Policy Engine enforcing `permission_level` / confirmation | later hardening |
| Non-media tools (filesystem, browser, apps, Windows UI, etc.) | Part 14.8–14.9, 14.16–14.17 |
| Output schema, retry/cancellation/idempotency/reversibility, verifier | remaining Part 15 properties, later |
| Persistence of the registry | not applicable — registry is process-local, rebuilt from code each run |

Per Part 14.7's own sequencing, the registry existing and being queryable
comes before anything routes through it — that wiring is Phase 10. This
phase is data only: nine `ToolDefinition`s that accurately describe
capabilities the assistant already has, expressed in the "domain.action"
form the rest of the architecture expects.

---

## Verification performed

`python -m compileall` is clean on the new files. A test (`venv`
interpreter) confirmed:

- `register_media_tools()` populates the registry with exactly the nine
  tools listed above; `list_tools()` returns all nine `ToolDefinition`
  objects.
- `get_tool("media.pause")` (and each of the other eight names) returns the
  matching `ToolDefinition` with the expected `name`, non-empty
  `description`, `permission_level == PermissionLevel.HARMLESS`, and
  `requires_confirmation is False`.
- `get_tool("media.does_not_exist")` returns `None` — no exception.
- Importing `jairus.tools.media_tools` alone (without calling
  `register_media_tools()`) leaves `list_tools()` empty, confirming
  registration is not an import-time side effect.
