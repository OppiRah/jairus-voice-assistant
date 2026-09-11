# Jairus — Phase 4: Task Manager

**Migration step:** Phase 4 of `JAIRUS_ARCHITECTURE.md` (Part 14.6), implementing
the Task Manager from Part 9, with in-memory state kept deliberately simple per
Part 52 ("V1 memory should remain simple").

**One-sentence summary:** every command now also gets a `Task`, linked to it
by `command_id`, that tracks `RECEIVED -> EXECUTING -> COMPLETED` / `FAILED`
alongside the command's own lifecycle — the `Command` dataclass and
`handle_command()` are both untouched.

---

## What was built

### New: `src/jairus/application/tasks/task_manager.py`

```python
def create_task(command_id: str) -> Task
def update_task_status(task_id: str, status: TaskStatus) -> None
def get_task(task_id: str) -> Task | None
def get_task_by_command(command_id: str) -> Task | None
```

What it does:

1. `create_task` builds a `Task` (Phase 2 domain model) with a fresh
   `task_id` (`str(uuid.uuid4())`), the given `command_id`,
   `status=TaskStatus.RECEIVED`, and `created_at=datetime.now(timezone.utc)`.
   Prints `[task] task {id} received (command {command_id})`.
2. `update_task_status` looks the task up, sets its `status`, and — if the
   new status is terminal (`COMPLETED`, `FAILED`, `CANCELLED`,
   `INTERRUPTED`) — stamps `completed_at`. Prints `[task] task {id} -> {status}`.
   Raises `KeyError` for an unknown `task_id`.
3. `get_task` / `get_task_by_command` are plain lookups, returning `None`
   when nothing matches instead of raising.

**Storage:** two module-level dicts — `_TASKS` (`task_id -> Task`) and
`_TASK_ID_BY_COMMAND` (`command_id -> task_id`) — matching the in-memory
style already used elsewhere in the codebase (e.g. `player_action.py`'s
module-level playback state). No SQLite, no repository interface yet.

### New: `src/jairus/application/tasks/__init__.py`

Re-exports `create_task`, `update_task_status`, `get_task`, `get_task_by_command`.

### Changed: `src/jairus/application/commands/command_gateway.py`

`submit_command()` now also drives a `Task`, at the points that are actually
observable today:

1. Right after the `Command` is constructed → `create_task(command.command_id)`.
   The task starts at `TaskStatus.RECEIVED`.
2. Right before calling `handle_command()` → `update_task_status(task.task_id,
   TaskStatus.EXECUTING)`.
3. After `handle_command()` returns or raises → the task is moved to
   `TaskStatus.COMPLETED` or `TaskStatus.FAILED`, mirroring whatever the
   `Command`'s own status ends up as.

No `PLANNING`, `WAITING_CONFIRMATION`, or `OBSERVING` transitions are driven
— there is no real planning, confirmation, or observation step until the
Agent Core and Policy Engine exist (later phases), so those states are not
faked here.

`handle_command()` itself, and the `Command` dataclass, are unchanged from
Phase 3.

---

## What was explicitly NOT touched

- **`handle_command()`'s internals.** Still byte-for-byte identical to
  Phase 3.
- **The `Command` dataclass** (`domain/commands/command.py`). Tasks link to
  commands by `command_id` only — no new field was added to `Command`.
- **The user-facing behaviour.** Run `python main.py`, say "hey jairus",
  give a command — it behaves exactly as before. The only visible
  difference is a few extra `[task] …` lines in the terminal per command,
  alongside the existing `[gateway] …` lines.

## What Phase 4 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Persistence for tasks (SQLite/database, survives restart) | Part 52, later |
| Agent Core / planner / decision loop | Part 14.10–14.12 (later) |
| Tool Registry, Tool Executor, tool schemas | Part 14.7 (later) |
| Policy Engine, confirmation flow → `WAITING_CONFIRMATION` | later hardening |
| Real `PLANNING` / `OBSERVING` transitions | once the Agent Core exists |
| Verification / result checking of a task's own outcome | later |
| Android transport, WebSocket gateway, auth | Part 14.15+ (later) |
| Structured logging / audit traces | Part 18 hardening |

The Task Manager currently does the one thing that's meaningful without an
Agent Core: give each command a **tracked execution record**, keyed so it
can be looked up either by its own id or by the command it belongs to.
Planning, verification, and durability are stubs-for-later by design.

---

## Verification performed

`python -m compileall` is clean on the new and changed files. A test (`venv`
interpreter) that stubs out `handle_command` confirmed:

- `import assistant_loop` still succeeds — no new circular import.
- Happy path: `submit_command` returns a `Command` with `status ==
  COMPLETED`; `get_task_by_command(command.command_id)` returns a `Task`
  with `status == COMPLETED`, a non-`None` `completed_at`, and
  `task.command_id == command.command_id`.
- Failure path: when `handle_command` raises, the returned `Command` has
  `status == FAILED`, no exception propagates, and the linked `Task` also
  has `status == FAILED` with `completed_at` set.
- Terminal output for one command is the existing three `[gateway] …` lines
  plus three new `[task] …` lines (`received`, `-> executing`, and the
  terminal transition).
- `get_task` and `get_task_by_command` return `None` for unknown ids instead
  of raising; `update_task_status` raises `KeyError` for an unknown
  `task_id`.
