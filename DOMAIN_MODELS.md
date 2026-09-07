# Jairus — Phase 2 Domain Models

**Migration step:** Phase 2 of `JAIRUS_ARCHITECTURE.md` (Part 14.4), implementing
the domain vocabulary described in Part 12.3–12.4.

**Scope of this change:** new files only, all under `src/jairus/domain/`. No
existing file was modified. Nothing is wired into the running Aria assistant.
No application logic, no persistence, no I/O — these are plain data records and
enums that later layers will pass around.

---

## What was created

```text
src/jairus/domain/
├── __init__.py                     (unchanged — empty, from Phase 1)
├── commands/
│   ├── __init__.py                 re-exports Command, CommandSource, CommandStatus
│   ├── command.py                  Command dataclass
│   ├── command_status.py           CommandStatus enum
│   └── command_source.py           CommandSource enum
├── tasks/
│   ├── __init__.py                 re-exports Task, TaskStatus
│   ├── task.py                     Task dataclass
│   └── task_status.py              TaskStatus enum
├── tools/
│   ├── __init__.py                 re-exports ToolCall, ToolDefinition, ToolResult, FailureCategory
│   ├── tool_definition.py          ToolDefinition dataclass
│   ├── tool_call.py                ToolCall dataclass
│   └── tool_result.py              ToolResult dataclass + FailureCategory enum
├── permissions/
│   ├── __init__.py                 re-exports Confirmation, PermissionLevel
│   ├── permission_level.py         PermissionLevel enum
│   └── confirmation.py             Confirmation dataclass
└── events/
    ├── __init__.py                 re-exports EventType, TaskEvent
    └── task_events.py              TaskEvent dataclass + EventType enum
```

15 new files (5 package `__init__.py` + 10 model modules).

---

## Models

### `commands/`

| Type | Kind | Fields / members |
|---|---|---|
| `Command` | dataclass | `command_id: str`, `source: CommandSource`, `raw_input: str`, `timestamp: datetime`, `conversation_id: str`, `goal: str \| None = None`, `status: CommandStatus = RECEIVED` |
| `CommandStatus` | `str, Enum` | `RECEIVED, UNDERSTANDING, PLANNING, WAITING_CONFIRMATION, EXECUTING, OBSERVING, COMPLETED, FAILED, RECOVERING, CANCELLED, INTERRUPTED` — the lifecycle in Part 13 |
| `CommandSource` | `str, Enum` | `VOICE, ANDROID` — future input adapters (Android voice, desktop UI, API) get new members here, per Part 8.1 |

### `tasks/`

| Type | Kind | Fields / members |
|---|---|---|
| `Task` | dataclass | `task_id: str`, `command_id: str`, `status: TaskStatus`, `created_at: datetime`, `completed_at: datetime \| None = None` |
| `TaskStatus` | `str, Enum` | same eleven lifecycle states as `CommandStatus`; mirrors the protocol state machine in Part 13.24 |

### `tools/`

| Type | Kind | Fields / members |
|---|---|---|
| `ToolDefinition` | dataclass | `name: str`, `description: str`, `input_schema: dict[str, Any]`, `permission_level: PermissionLevel`, `requires_confirmation: bool`, `timeout_seconds: int` — the subset of Part 15's tool properties needed now |
| `ToolCall` | dataclass | `tool_name: str`, `arguments: dict[str, Any]`, `command_id: str` |
| `ToolResult` | dataclass | `success: bool`, `data: dict[str, Any] \| None = None`, `error: str \| None = None`, `failure_category: FailureCategory \| None = None` |
| `FailureCategory` | `str, Enum` | `VALIDATION_ERROR, PERMISSION_DENIED, CONFIRMATION_REQUIRED, NOT_FOUND, TIMEOUT, EXECUTION_ERROR, BACKEND_UNAVAILABLE, OBSERVATION_FAILED, VERIFICATION_FAILED, UNKNOWN_ERROR, CANCELLED, RECOVERING, INTERRUPTED` — the full Part 32 list |

### `permissions/`

| Type | Kind | Fields / members |
|---|---|---|
| `PermissionLevel` | `IntEnum` | `HARMLESS = 0`, `DISRUPTIVE = 1`, `DESTRUCTIVE = 2`, `DANGEROUS = 3` — Part 25's four levels, integer-valued so "Level 0..3" maps directly |
| `Confirmation` | dataclass | `confirmation_id: str`, `command_id: str`, `tool_name: str`, `arguments: dict[str, Any]`, `description: str`, `expires_at: datetime`, `decision: str \| None = None` — bound to an exact action per Part 26 |

### `events/`

| Type | Kind | Fields / members |
|---|---|---|
| `EventType` | `str, Enum` | `TASK_STARTED, TASK_PROGRESS, TASK_WAITING_CONFIRMATION, TASK_COMPLETED, TASK_FAILED, TASK_CANCELLED, TASK_INTERRUPTED, TOOL_STARTED, TOOL_COMPLETED, TOOL_FAILED` — values are the wire strings from Parts 13.12–13.13 (`"task.started"`, `"tool.completed"`, …) |
| `TaskEvent` | dataclass | `event_type: EventType`, `task_id: str`, `timestamp: datetime`, `payload: dict[str, Any]` (defaults to `{}`) |

---

## Design notes

- **String-valued enums** (`str, Enum`) for everything that will cross the
  Android protocol, so `status.value` / `event_type.value` are already the
  wire strings and need no translation layer. `PermissionLevel` is an
  `IntEnum` instead, to match the architecture's "Level 0..3" numbering.
- **`from __future__ import annotations`** in every module: annotations are not
  evaluated at runtime, which keeps `str | None` and `dict[str, Any]` cheap and
  avoids any import-time coupling.
- **Optional fields have defaults** (`goal`, `completed_at`, `decision`,
  `data`, `error`, `failure_category`, `payload`); `Command.status` defaults to
  `RECEIVED` since that is the state of a freshly created command.
- **Cross-references stay inside the domain**: `Command` → `CommandSource` /
  `CommandStatus`, `Task` → `TaskStatus`, `ToolDefinition` → `PermissionLevel`,
  `ToolResult` → `FailureCategory`, `TaskEvent` → `EventType`. No cycles.
- `src/jairus/domain/__init__.py` was **left untouched** (still the empty file
  from Phase 1), to honour "do not modify any existing file".

---

## Zero external dependencies — confirmed

Every import statement in `src/jairus/domain/` was audited. The layer uses
**only the Python standard library**:

| Module | Used for |
|---|---|
| `__future__` (`annotations`) | deferred annotation evaluation |
| `dataclasses` (`dataclass`, `field`) | the record types |
| `datetime` (`datetime`) | timestamp fields |
| `enum` (`Enum`, `IntEnum`) | the enums |
| `typing` (`Any`) | `dict[str, Any]` annotations |

Plus intra-package **relative imports** between domain modules only.

There is **no import of `ollama`, `requests`, `playwright`, `pygame`,
`sounddevice`, `faster_whisper`, `pyttsx3`, any database driver, or any other
third-party or infrastructure package** anywhere in this layer — as required by
`JAIRUS_ARCHITECTURE.md` Part 12.3 ("the domain should not know that we're
using Ollama, FastAPI, WebSockets, Oracle, SQLite, Playwright, PyAutoGUI,
faster-whisper").

### Verification performed

- `python -m compileall -q src/jairus/domain` — clean.
- Import smoke test: every public name imports from its subpackage, and a
  representative instance of each dataclass constructs, with defaults behaving
  as specified.
