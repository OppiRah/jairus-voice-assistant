# Jairus — Phase 3: Command Gateway

**Migration step:** Phase 3 of `JAIRUS_ARCHITECTURE.md` (Part 14.5), implementing
the controlled entry point from Part 9.

**One-sentence summary:** every voice command now gets a `command_id` and a
lifecycle status (`RECEIVED → UNDERSTANDING → COMPLETED` / `FAILED`), by wrapping
the existing `handle_command()` — whose internals were **not** changed.

---

## What was built

### New: `src/jairus/application/commands/command_gateway.py`

```python
def submit_command(text: str, source: CommandSource, context, state,
                   conversation_id: str) -> Command
```

What it does, in order:

1. Generates a `command_id` (`str(uuid.uuid4())`).
2. Constructs a `Command` (Phase 2 domain model) with
   `status=CommandStatus.RECEIVED`, the given `source` / `raw_input` (the
   command text) / `conversation_id`, and `timestamp=datetime.now(timezone.utc)`.
3. Prints `[gateway] command {id} received: '{text}'`.
4. Transitions `status` to `CommandStatus.UNDERSTANDING` and prints
   `[gateway] command {id} -> understanding`.
5. Calls the **existing, unmodified** `assistant_loop.handle_command(text,
   context, state)` to do the actual work. It is imported (lazily, inside the
   function, to avoid a circular import), never reimplemented.
6. If `handle_command()` returns normally → `status = CommandStatus.COMPLETED`,
   prints `-> completed`.
7. If `handle_command()` raises → the exception is **caught**, `status =
   CommandStatus.FAILED`, prints `-> failed: {error}`, and the exception is
   **not** re-raised. The voice loop stays alive and keeps listening, exactly
   as it does today (`handle_command()` already has its own internal
   try/except; this is a belt-and-braces outer guard).
8. Returns the `Command` object with its final status.

Observability stays in the codebase's existing `print("[tag] ...")` style — no
logging framework was introduced (that belongs to a later hardening phase).

### New: `src/jairus/application/commands/__init__.py`

Re-exports `submit_command`.

### Changed: `assistant_loop.py` (small — 15 lines, see the diff)

- Added a `sys.path` bootstrap so `src/` is importable when running
  `python main.py` from the repo root, then imports `submit_command` and
  `CommandSource`.
- `run_assistant()` generates one `conversation_id = str(uuid.uuid4())` per
  program run (a reasonable placeholder: `ConversationContext` already resets
  per run).
- The single line `handle_command(text, context, state)` is now
  `submit_command(text, CommandSource.VOICE, context, state, conversation_id)`.
- **Nothing else changed.** The wake-word loop, recording, transcription, and
  orb state transitions are untouched.

---

## What was explicitly NOT touched

- **`handle_command()`'s internals.** The `extract_intent()` call, the
  `if/elif` action dispatch (`play` / `queue` / `pause` / `resume` / `skip` /
  `correct` / `volume_up` / `volume_down` / `whats_playing`), the `speak()`
  calls, the `context.add_turn()` call — all byte-for-byte identical. Its
  replacement is a later phase (Part 14.13, "Replace Intent Parser
  Gradually").
- **`intent_parser.py`, `player_action.py`, `tts.py`, `context.py`,
  `quick_commands.py`, and every other existing module** — not modified.
- **The user-facing behaviour.** Run `python main.py`, say "hey jairus", give a
  command — it behaves exactly as before. The only visible difference is three
  extra `[gateway] …` lines in the terminal per command.

## What Phase 3 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Agent Core / planner / decision loop | Part 14.10–14.12 (later) |
| Tool Registry, Tool Executor, tool schemas | Part 14.7 (later) |
| Policy Engine, permission enforcement, confirmation flow | later hardening |
| Replacing the intent parser / action router | Part 14.13 (later) |
| Task Manager, `Task` records, task IDs | Part 14.6 (next phase) |
| Android transport, WebSocket gateway, auth | Part 14.15+ (later) |
| Persistence / repository / database | later |
| Structured logging / audit traces | Part 18 hardening |

The gateway currently does the two things Part 9 lists that are meaningful
without a network or multiple clients: **assign command IDs** and **normalize
requests into a `Command`**. Authentication, event publishing, cancellation, and
confirmation routing are stubs-for-later by design.

---

## Verification performed

`python -m compileall` is clean on the new and changed files. A test
(`venv` interpreter) that stubs out `handle_command` confirmed:

- `import assistant_loop` succeeds — **no circular import** (the lazy import of
  `handle_command` inside `submit_command` is what avoids it).
- Happy path: returned `Command` has `status == COMPLETED`, correct `source`,
  `raw_input`, and `conversation_id`; `handle_command` is called exactly once
  with the passed-through `(text, context, state)`.
- Failure path: when `handle_command` raises, `submit_command` returns a
  `Command` with `status == FAILED`, a fresh `command_id`, and **no exception
  propagates**.
- `assistant_loop.handle_command` and `assistant_loop.run_assistant` remain
  defined and callable.

The full voice path (mic → wake word → Whisper → Ollama → playback) was not
run here because it needs a microphone, GPU, a running Ollama, and a
debug-port Brave session; the code path from `submit_command` into the
unchanged `handle_command` is a direct, unconditional call, so it is
equivalent to today's behaviour plus the lifecycle bookkeeping.
