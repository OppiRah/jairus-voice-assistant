# Jairus — Phase 13: Android Gateway

**Migration step:** Phase 13 of `JAIRUS_ARCHITECTURE.md` Part 13 (API &
Protocol Specification), Part 44 (local-network-only for V1), Part 45
(authentication vs authorization).

**One-sentence summary:** a standalone WebSocket server lets an external
client submit text commands that flow through the EXISTING, unmodified
Command Gateway using `CommandSource.ANDROID` — a value that has sat
defined and unused in the domain models since Phase 2.

---

## First networked, first async code

Every prior phase in this project has been synchronous, single-process,
and local. Phase 13 is deliberately different: it is the first code in
this codebase that

- listens on a network socket at all, and
- uses `asyncio` (an event loop, `async def`, `await`) instead of plain
  synchronous function calls or `threading.Thread`.

That combination is exactly why the scope fence for this phase is unusually
strict — see below.

---

## What was built

### New: `src/jairus/configuration/settings.py`

First real content in this package (empty since Phase 1, per Part 12's
reserved folder structure). Plain module-level constants, matching how the
rest of this codebase already keeps config next to the code that uses it
(e.g. `WAKE_WORD_MODEL` in `assistant_loop.py`):

```python
GATEWAY_HOST = "0.0.0.0"          # binds on the LAN, not just localhost
GATEWAY_PORT = 8765
ANDROID_PAIRING_CODE = "changeme-pairing-code"   # CHANGE THIS
PROTOCOL_VERSION = "1"
```

### New: `src/jairus/interfaces/android/protocol.py`

Message envelope helpers matching Part 13.3 exactly:

```python
def build_message(type: str, payload: dict) -> dict: ...
def parse_message(raw: str) -> dict | None: ...
```

Every envelope carries `protocol_version`, `message_id` (a fresh `uuid4`
per message — Part 13.4, deliberately unrelated to a `Command`'s own
`command_id`), `type`, `timestamp` (ISO format), `payload`.
`parse_message()` returns `None` on malformed JSON *or* a missing
envelope field — it validates the shape rather than assuming it, per Part
13.26 ("every message should be schema validated").

### New: `src/jairus/interfaces/android/gateway_server.py`

The async server. Per connection:

1. Expect `connection.hello`, then `connection.auth` (Part 13.5). If the
   pairing code doesn't match `settings.ANDROID_PAIRING_CODE`, send
   `connection.error` (`code: "AUTHENTICATION_FAILED"`) and close — never
   proceed silently.
2. On success, send `connection.ready`.
3. On each `command.submit`: send `command.acknowledged` immediately
   (Part 13.11 — acknowledge before doing the work, because the network
   can die mid-task), then call the **existing, unmodified**
   `command_gateway.submit_command(text, CommandSource.ANDROID, context,
   state, conversation_id)` via `loop.run_in_executor()`, since that call
   is synchronous/blocking (Ollama, intent parsing, Playwright/media
   control) and must not block the event loop.
4. Once it returns, send `task.completed` or `task.failed` with the
   `Command`'s final `command_id`, linked `task_id`, `status`, and
   `raw_input`.
5. A malformed or unrecognized message type gets `connection.error` — the
   connection is **not** dropped for this (only a failed handshake drops
   the connection).

A single shared `ConversationContext` and `conversation_id` are used for
the server's whole lifetime — no per-device context isolation yet, per
this phase's explicit scope.

### New: `run_gateway.py` (repo root)

Standalone entry point. `python run_gateway.py` prints
`[gateway] listening on 0.0.0.0:8765` and runs until Ctrl+C. Does not
touch `main.py` in any way.

### New: `scripts/test_gateway_client.py`

A real, committed dev utility (not throwaway) — connects as a bare
WebSocket client, runs the handshake, submits one `command.submit`, prints
every message. Takes the command text and pairing code as CLI args:

```
python scripts/test_gateway_client.py "pause" changeme-pairing-code
python scripts/test_gateway_client.py "pause" wrong-code-on-purpose
```

Stays useful after the real Android app exists, for testing the server in
isolation without a phone.

### Changed: `requirements.txt`

One line added: `websockets`.

---

## New dependency: `websockets`

Justified the same way `psutil`/`pywinauto` were: nothing already in this
project provides async WebSocket server *or* client support.
`sounddevice`/`playwright`/`requests`/etc. are all either synchronous I/O
or serve a completely different purpose (audio, browser automation, HTTP).
`websockets` is the standard, minimal async Python WebSocket library — no
web framework, no ASGI server, no ORM riding along with it. It is used for
exactly what Part 13.1 specifies: "Primary channel for commands, task
updates, ... connection events," nothing more.

---

## What did NOT change (confirmed via empty `git diff`)

`intent_parser.py`, `assistant_loop.py`, `command_gateway.py`,
`task_manager.py`, `player_action.py`, `apps.py`, `windows_ui.py`,
`browser.py`, `agent_core.py`, `policy_engine.py`, `voice_adapter.py`,
`main.py` — all zero lines changed, verified with
`git diff --stat -- <files>` returning empty before committing.

This phase only **adds** new files (plus the one-line `requirements.txt`
addition) and **imports** the existing `submit_command()` — it does not
reimplement or wrap any of its internals.

---

## Deliberate scope reductions (minimum viable protocol subset)

Only these Part 13 message types are implemented:

```
connection.hello
connection.auth
connection.ready
connection.error
command.submit
command.acknowledged
task.completed
task.failed
```

**Not implemented, and why not yet:**

| Not in this phase | Why |
|---|---|
| `task.started` / `task.progress` | No intermediate progress exists to report — `submit_command()` is one blocking call from the caller's point of view; Phase 4's Task Manager has no PLANNING/OBSERVING granularity to surface either (see `COMMAND_GATEWAY.md`). |
| `confirmation.request` / `confirmation.response` | Android reaches the exact same 9 `media.*` actions voice already reaches, through the same unmodified `handle_command()`. No confirmation flow exists on that live path today — the Policy Engine is still shadow-only (Phase 10/11, `AGENT_SHADOW_MODE.md`). There is nothing yet for a confirmation protocol to gate. |
| `command.cancel` / `command.status` | Cancellation and status polling need a task registry the caller can address *while* a command is still running; `submit_command()` currently only returns after the command has already finished. Meaningful only once the Gateway can track in-flight work, which needs the async integration into the main runtime that this phase explicitly defers. |
| Reconnection / state reconciliation (Part 13.19-13.20) | Same reason — nothing is actually in-flight from the caller's perspective by the time any message could be lost. |
| `tool.*` events | No Tool Executor sits on the live execution path yet (Phase 5/6's registry/executor are wired only into the *shadow* Agent Core, not the real one). |
| `system.state` | No periodic state broadcast exists anywhere in this codebase yet; would be new behavior beyond "route Android commands through the existing Gateway." |

This matches the project's established pattern (see every prior phase
doc's "what did NOT change" section): build only what the current, real
execution path actually needs, and name what's deferred rather than
scaffolding around a cutover that hasn't happened.

---

## Deviation from the brief: `state` is a real `AssistantState()`, not `None`

The task brief for this phase suggested calling
`submit_command(text, CommandSource.ANDROID, context, state=None,
conversation_id)`. In testing, a literal `None` breaks immediately:
`handle_command()` (`assistant_loop.py`, unmodified, protected) calls
`state.set_status("thinking")` unconditionally as its very first line, with
no `None`-guard. A literal `None` would make **every** Android command fail
instantly — caught by `submit_command()`'s own `try`/`except` and reported
as `task.failed` — before `handle_command()` did any real work at all. That
would defeat the actual point of this phase, which is to prove
`CommandSource.ANDROID` reaches the same real execution path as
`CommandSource.VOICE`.

`gateway_server.py` instead constructs one real `AssistantState()` (the
existing, unmodified class from `assistant_state.py` — not a protected
file, and not touched) and keeps it alive for the server's lifetime. This
costs nothing (it has no pygame/orb dependency, just a lock and two
fields) and means the real TTS speech that's part of `handle_command()`'s
existing behavior (`speak()` calls) happens for Android exactly as it does
for voice — real parity, not a stub that happens to avoid crashing.

---

## Known limitation: concurrent connections aren't synchronized

`task_manager.py`'s storage is two plain module-level `dict`s
(`_TASKS`, `_TASK_ID_BY_COMMAND`) with no lock (see `TASK_MANAGER.md`).
Today, with only ever one voice-input thread calling into it, that's safe.
This Gateway changes that: if two Android clients connect simultaneously
(or one client fires off a second `command.submit` before the first has
finished), `loop.run_in_executor(None, ...)` can run
`submit_command()`/`create_task()`/`update_task_status()` on two different
worker threads at the same time, racing on those dicts with no lock
between them.

This is **documented, not fixed**, matching this project's established
pattern of flagging known debt rather than gold-plating a V1 (see Part
11.10: "we should not allow unlimited simultaneous autonomous tasks... one
autonomous task at a time" — enforcing that for real is follow-up work,
likely alongside whatever eventually gives the Task Manager real
persistence). In practice, this phase's own test client only ever sends
one command at a time, so the race was not something this phase could
trigger or observe — it's a structural risk being named ahead of the
Android app existing, not something reproduced here.

---

## Not integrated into `main.py`

Per this phase's explicit scope, the Gateway is only ever started by
`run_gateway.py`, standalone. It is **not** a third thread/task inside
`main.py`'s existing pygame + assistant-thread process. `main.py` has zero
diff (see above). Wiring the Gateway into the main runtime — so it starts
automatically alongside the voice pipeline — is an explicit follow-up
phase, not this one.

---

## Testing performed

### Test A — wrong pairing code is refused

```
python run_gateway.py
python scripts/test_gateway_client.py "pause" totally-wrong-code
```

Client sent:

```json
{"protocol_version": "1", "message_id": "cde01056-8c07-4a0e-b12c-451e002b726d", "type": "connection.hello", "timestamp": "2026-09-11T13:44:01.275322+00:00", "payload": {"client_type": "test_script", "client_version": "0.1.0", "device_id": "test-client"}}
{"protocol_version": "1", "message_id": "54ce2a30-32d4-41b0-bdf5-952a1eae6ea6", "type": "connection.auth", "timestamp": "2026-09-11T13:44:01.275937+00:00", "payload": {"pairing_code": "totally-wrong-code"}}
```

Server sent back:

```json
{"protocol_version": "1", "message_id": "c77b9df9-39a7-4e2a-9945-c18957bba1db", "type": "connection.error", "timestamp": "2026-09-11T13:44:01.276703+00:00", "payload": {"code": "AUTHENTICATION_FAILED", "message": "Authentication failed."}}
```

...then closed the connection. The client printed
`"[client] authentication was rejected, stopping here."` and never sent
`command.submit` at all — confirmed the wrong code is refused, not
silently allowed through.

### Test B — real end-to-end through Ollama/the real execution path

Ollama (`qwen2.5:7b`, confirmed reachable at `localhost:11434`) and Brave
(debug port `9222`, confirmed reachable, multiple tabs open including a
live YouTube watch page) were both running.

**Note on the exact command used:** the task brief suggested "pause" or a
play request. In this environment, the currently-running, long-lived
Brave debug session has a pre-existing issue completely unrelated to this
phase's code: Playwright's `connect_over_cdp()` handshake against it hangs
indefinitely (confirmed by reproducing the identical hang calling
`player_action.pause_music()` **directly**, with zero Gateway/asyncio
code involved at all — see reproduction below). Since "pause" and every
play/volume/skip action route through `player_action._get_browser()`
unconditionally on a fresh process, they all hit this same pre-existing
environment hang, which would block the *voice* path identically. To
still prove the real, unmodified execution path end-to-end without that
unrelated environment issue in the way, the test command used was
`"no not that one"` — this fast-paths to the `correct` action, and
`player_action.correct_song()` returns without ever touching the browser
when nothing is already playing in YouTube mode (a fresh process
condition), which is exactly the condition here.

*Reproduction of the pre-existing Brave/CDP issue, for the record (not
part of this phase's own test):*

```python
import player_action
player_action.pause_music()   # hangs indefinitely, no Gateway code involved
```

confirmed hanging identically both as a plain function call and inside a
background `threading.Thread`, and via a direct `connect_over_cdp(...,
timeout=10000)` call, which raised `playwright._impl._errors.TimeoutError`
after connecting the control WebSocket but never getting a response —
i.e. Brave's current CDP session isn't completing the handshake, unrelated
to anything built in this phase.

**The actual test:**

```
python run_gateway.py
python scripts/test_gateway_client.py "no not that one" changeme-pairing-code
```

Client sent:

```json
{"protocol_version": "1", "message_id": "5cda9656-84da-4a2b-b861-48f7d6a14c88", "type": "connection.hello", "timestamp": "2026-09-11T13:54:10.518340+00:00", "payload": {"client_type": "test_script", "client_version": "0.1.0", "device_id": "test-client"}}
{"protocol_version": "1", "message_id": "73f2af58-516f-43e8-a27f-be17a80e828d", "type": "connection.auth", "timestamp": "2026-09-11T13:54:10.519082+00:00", "payload": {"pairing_code": "changeme-pairing-code"}}
```

Server sent:

```json
{"protocol_version": "1", "message_id": "910dcb71-7002-4ccd-8d96-2c182aa7bf2b", "type": "connection.ready", "timestamp": "2026-09-11T13:54:10.519721+00:00", "payload": {"server_version": "0.1.0", "agent_status": "ready"}}
```

Client sent:

```json
{"protocol_version": "1", "message_id": "3e672a8d-3067-403f-9e2f-8a183d920daa", "type": "command.submit", "timestamp": "2026-09-11T13:54:10.522927+00:00", "payload": {"text": "no not that one"}}
```

Server sent (immediately — well under a second):

```json
{"protocol_version": "1", "message_id": "0b38483d-b6b7-436e-bd73-3b4c49b54735", "type": "command.acknowledged", "timestamp": "2026-09-11T13:54:10.523504+00:00", "payload": {"status": "accepted"}}
```

Server-side log during the ~7 seconds of real work (the gap is real
`pyttsx3` text-to-speech actually speaking out loud, not a stall):

```
[gateway] command 1af5d7bf-618a-4b64-9e3f-469f056c0b3b received: 'no not that one'
[task] task 5a8ba9de-6405-467f-9e61-21a670f55a61 received (command 1af5d7bf-618a-4b64-9e3f-469f056c0b3b)
[gateway] command 1af5d7bf-618a-4b64-9e3f-469f056c0b3b -> understanding
[task] task 5a8ba9de-6405-467f-9e61-21a670f55a61 -> executing
[intent] fast-pathed 'no not that one' -> correct (no LLM call)
[intent] {'action': 'correct', 'title': '', 'artist': '', 'songs': []}
[player] correction only works for YouTube searches right now
[voice] That was the last option I found
[gateway] command 1af5d7bf-618a-4b64-9e3f-469f056c0b3b -> completed
[task] task 5a8ba9de-6405-467f-9e61-21a670f55a61 -> completed
```

Then the server sent back to the client:

```json
{"protocol_version": "1", "message_id": "eb3333ff-7eb9-40f5-a27e-e3337edc68ec", "type": "task.completed", "timestamp": "2026-09-11T13:54:17.947477+00:00", "payload": {"command_id": "1af5d7bf-618a-4b64-9e3f-469f056c0b3b", "task_id": "5a8ba9de-6405-467f-9e61-21a670f55a61", "status": "completed", "raw_input": "no not that one"}}
```

This is the real, unmodified `intent_parser.py` fast path, the real,
unmodified `player_action.correct_song()`, and real `pyttsx3` speech
(audibly spoken, not mocked) — driven entirely by `CommandSource.ANDROID`
through the same `command_gateway.submit_command()` voice already uses.
`command_id`/`task_id` in the final message are the real ones the
(unmodified) Command Gateway and Task Manager assigned. This is the same
evidence shape Phase 12's own testing used (a fast-path command, verified
via the real `[gateway]`/`[task]`/`[intent]`/`[player]`/`[voice]` log
lines) — here, for the first time, driven over a real network socket by
`CommandSource.ANDROID` instead of `CommandSource.VOICE`.

### Protected files

`git diff --stat` against all twelve listed protected files returned
empty immediately before committing.
