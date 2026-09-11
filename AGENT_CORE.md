# Jairus — Phase 10: Minimal Agent Core

**Migration step:** Phase 10 of `JAIRUS_ARCHITECTURE.md` (Part 14.12),
introducing the Real Agent Loop per Part 11 (LLM role), Part 12 (agent
execution model), Part 16 ("the LLM cannot invent capabilities"), Part 25
(permission model), Part 26 (confirmation model), and Parts 66-68
(incremental tool decisions, structured LLM output, output validation).

**One-sentence summary:** an LLM can now really pick one tool from a
small, hardcoded 5-tool allow-list to satisfy a plain-text goal, gated by
a Policy Engine that finally reads the `permission_level`/
`requires_confirmation` data every tool has carried since Phase 5 — with
zero caching of confirmation decisions, proven, not assumed.

---

## ⚠️ First phase where an LLM has real decision-making power

Every tool from Phase 5 through Phase 9 was pre-registered **data** —
nothing selected between the ~20 registered tools; `execute_tool()` only
ever ran whatever name a human-written test handed it directly. **This
phase is different in kind, not just in size**: for the first time, an
LLM call actually chooses which tool to run and with what arguments, from
natural language.

Treated with the caution that deserves:

- **The allow-list is deliberately small and hardcoded** (`ALLOWED_TOOLS`
  in `agent_core.py`), not derived from the full Tool Registry:
  `media.pause`, `media.resume`, `media.skip`, `apps.launch`,
  `apps.close` — exactly five. This is **not a placeholder meant to grow
  casually**. It exists specifically to prove the end-to-end mechanism
  once, cleanly, on both an unguarded path (four `HARMLESS` tools) and a
  guarded path (`apps.close`, `DISRUPTIVE`) — without exposing the other
  ~15 registered tools (including ones with real, unpredictable effects,
  like Phase 9's `windows.invoke`/`windows.type`/`windows.hotkey`) to LLM
  selection before there's any track record of this mechanism actually
  holding up.
- **The LLM cannot reach anything outside that list.** Checked twice,
  independently: against the hardcoded `ALLOWED_TOOLS` list, and against
  the actual Tool Registry (Part 16: "Tool not found → REJECT"). A tool
  that's registered but not allow-listed (e.g. `windows.invoke`) and a
  tool that's hallucinated and doesn't exist anywhere are rejected the
  same way — `NOT_FOUND`, `execute_tool()` never called. Both are tested
  deterministically (§4).
- **No caching, anywhere — tested, not assumed** (§5). Approving
  `apps.close` once does not authorize it again, even for the literal same
  goal text submitted immediately afterward in the same process.

---

## What was built

### New: `src/jairus/application/policy/policy_engine.py`

```python
def evaluate(tool_definition: ToolDefinition) -> str        # "allow" | "confirm"
def request_confirmation(tool_definition, arguments: dict) -> bool
```

`evaluate()` reads `tool_definition.requires_confirmation` — set correctly
since Phase 5 (media), Phase 7 (apps), and Phase 9 (windows) but never
read by anything until now. It doesn't recompute or override that value:
"the LLM never decides a tool's level — the tool's definition and the
Policy Engine do" (`PermissionLevel`'s own docstring).

`request_confirmation()` builds a real `Confirmation` (Phase 2's domain
model, `domain/permissions/confirmation.py` — **the first phase that
actually instantiates it**), bound to the exact tool name and argument
dict about to run (Part 26), prints a clear description, and blocks on a
terminal `input()` y/n prompt. No Command exists yet at this phase (the
Agent Core isn't wired to the Command Gateway — see "Scope" below), so
`Confirmation.command_id` is a fresh placeholder UUID per request rather
than a real Command's id; this is called out explicitly as a placeholder
in the code, not silently glossed over.

### New: `src/jairus/application/agent/agent_core.py`

```python
ALLOWED_TOOLS = ["media.pause", "media.resume", "media.skip", "apps.launch", "apps.close"]

def run_goal(goal_text: str) -> ToolResult
```

`run_goal()` follows Part 68's own validation pipeline:

1. **Parse** — call Ollama (same `requests.post` to
   `localhost:11434/api/generate` pattern `intent_parser.py` already
   uses, deliberately duplicated rather than imported, to keep this module
   decoupled) with a new, standalone system prompt (not a modification of
   `intent_parser.py`'s prompt — a different file, different purpose).
   The prompt's tool descriptions are pulled live from each allow-listed
   tool's actual registered `ToolDefinition` (`description` +
   `input_schema`) — **no duplicated tool-description text** lives in the
   prompt string itself.
2. **Schema validate** — the LLM's JSON response must be an object with a
   `type` (`"tool_call"` or `"no_match"`, a two-outcome subset of Part
   67's structured-output shape — `"ask_user"`/`"recover"` both imply a
   multi-turn loop this phase deliberately doesn't build), a `tool` name,
   and an `arguments` object. Malformed output is rejected
   (`VALIDATION_ERROR`), not guessed at.
3. **Tool exists?** — `type != "tool_call"` (the LLM said no tool fits, or
   said nothing at all) → `NOT_FOUND`, with the LLM's own stated reason as
   the error message. `tool` not in `ALLOWED_TOOLS` → `NOT_FOUND`. `tool`
   in `ALLOWED_TOOLS` but somehow not actually registered → `NOT_FOUND`.
   **None of these three paths ever call `execute_tool()`.**
4. **Policy check** — `policy_engine.evaluate(tool_definition)`.
5. **Confirmation if required** — `policy_engine.request_confirmation()`;
   declined → `ToolResult(success=False, failure_category=PERMISSION_DENIED,
   error="user declined confirmation")`, **`execute_tool()` is never
   called** for a declined action.
6. **Execute** — the **existing, unmodified** `execute_tool()` from
   Phase 6's `executor.py`. This module does not duplicate tool-calling
   logic anywhere — it only decides *whether* and *what* to call, the
   actual call goes through the same executor every other phase's tools
   already go through.

**Why `PERMISSION_DENIED` for a decline**, specifically (there's no
dedicated "user said no" category in `FailureCategory`): the user holds
authority over the permission decision the Policy Engine is gating: a
declined confirmation *is* a permission denial, functionally identical to
the OS or another authority denying it — it's the closest accurate fit in
the existing taxonomy, and it's clearly distinct in kind from
`EXECUTION_ERROR` (which would incorrectly suggest something went wrong
while running, when in fact nothing ran at all).

### Changed: nothing else

No existing file was modified. Two new packages, `application/policy/`
and `application/agent/`, each with an `__init__.py` following the
existing package style.

---

## Tool Registry / Executor reuse — confirmed, not reimplemented

- `get_tool()` (Phase 5's registry, unmodified) is what `agent_core.py`
  uses both to build its prompt's tool descriptions and to validate a
  chosen tool actually exists.
- `execute_tool()` (Phase 6's executor, unmodified) is the **only** thing
  that ever actually runs a tool. `agent_core.py` contains no
  `player_action`/`apps`/`browser`/`windows_ui` imports or calls at all —
  everything after the policy gate is one call to the existing executor.

---

## Scope — what this phase deliberately does NOT do

- **No Command, no Task.** `run_goal()` takes raw text and returns a
  `ToolResult` directly — it does not construct a `Command` (Phase 2/3) or
  a `Task` (Phase 2/4), and nothing here calls `command_gateway.submit_command()`
  or `task_manager.create_task()`. Wiring the Agent Core into the Command
  Gateway/Task Manager is a later phase.
- **Not wired into voice dispatch.** `intent_parser.py` and
  `handle_command()` are both completely unchanged (confirmed below) —
  saying anything to the live voice assistant behaves exactly as it did
  after Phase 9. `run_goal()` is only reachable by calling it directly
  with text, as the tests below do.
- **No multi-step planning, retries, or recovery.** One goal → one LLM
  decision → at most one tool call → one `ToolResult`. Part 12's full
  RECEIVE→...→OBSERVE→VERIFY→RECOVER loop, and Part 66's "choose next
  action" *loop*, are both explicitly for later — this phase implements
  exactly one iteration of that loop, once.
- **Confirmation UX is a blocking terminal prompt only.** Voice-based
  confirmation is explicitly Part 14.13+'s problem, not attempted here.

---

## Testing

All tests call `run_goal()` directly with raw text — no mic, no
`command_gateway`, no `handle_command()`.

**Media scenarios use monkeypatched `player_action` functions**, matching
Phase 6's own precedent — not because `media.pause`/`media.skip` don't
work for real (Phase 6 already proved that), but because this phase is
specifically testing the *Agent Core's routing decision*, and a real
`media.pause`/`media.skip` would affect the actual live YouTube Music
session running in this environment's browser. Verifying the Agent Core
correctly reaches the real `player_action` module reference — not a copy
of it — is what these monkeypatches confirm.

**`apps.launch`/`apps.close` scenarios are real** — against Calculator,
**not Notepad**. A live check before writing this test found the same
sensitive Notepad window discovered in Phase 9
(`*JAIRUS_HANDOFF.md - Notepad`, unsaved changes) was *still open*.
`apps.close_app()` matches every process named `notepad.exe` — it would
have force-killed that window (on Windows, `psutil.Process.terminate()` is
an unconditional `TerminateProcess()`, not a graceful "save changes?"
close) with real, unrecoverable data loss. Calculator (no user data,
already established safe in Phase 9) was used instead; confirmed
before-and-after that the Notepad window's title and unsaved-changes
asterisk were unchanged.

| Scenario | Result | What was verified |
|---|---|---|
| `"pause the music"` | **PASS** | Selected `media.pause`; monkeypatched `pause_music` was called exactly once; `input()` never invoked (`HARMLESS`, no confirmation). |
| `"skip this song"` | **PASS** | Selected `media.skip`; same. |
| `"open the calculator app"` | **PASS** | Selected `apps.launch` (real); Calculator actually launched; no confirmation prompt. |
| `"close the CalculatorApp.exe process"` — **APPROVE** | **PASS** | Prompted exactly once; approved (`y`); Calculator was actually, verifiably closed (`data={"closed": True}`, process gone). |
| Same goal — **DENY** | **PASS** | Prompted exactly once; declined (`n`); Calculator was **still running** afterward; `ToolResult(success=False, failure_category=PERMISSION_DENIED, error="user declined confirmation")` — a decline, not an execution failure. |
| No-suitable-tool: `"delete all my files"`, `"search the web for cats"` | **PASS** (both) | Real LLM call; correctly returned `type: "no_match"` with a stated reason; `NOT_FOUND`; never called `execute_tool()`. |
| Deterministic guardrail: LLM told (via monkeypatched `_call_ollama`) to pick `windows.invoke` (registered in Phase 9, **not** allow-listed) | **PASS** | Rejected with `NOT_FOUND` ("outside the allowed tool list"); `execute_tool()` confirmed never called (tracked directly). |
| Deterministic guardrail: LLM told to pick `media.teleport` (doesn't exist anywhere) | **PASS** | Same rejection path, same `NOT_FOUND`; `execute_tool()` never called. |

### The no-caching proof — actually tested

Exactly the scenario the task called out as the key test: Calculator is
closed via **approve**, then immediately (same process, same goal text,
no restart) `run_goal("close the CalculatorApp.exe process")` is called
again.

- **Prompted a second time — not skipped.** The number of times the
  confirmation prompt actually fired was counted directly (`prompt_log`);
  it was exactly **2** across the two calls, never 1.
- Both calls independently succeeded for real (Calculator was relaunched
  between them so the second close had something real to act on) —
  `run #1` and `run #2` both show `data={"closed": True}`.
- **Sharper variant, also run:** approve once (Calculator closes), relaunch,
  then **immediately deny** the exact same goal — the decline was honored
  (`success=False`, Calculator stayed running) right after an approval of
  the identical action. If any decision were cached or "remembered" for a
  repeat of the same goal, this specific sequence — approve, then
  immediately deny the same thing — would be impossible to produce
  correctly. It was produced correctly.

This is possible because `policy_engine.py` holds **zero state between
calls** — `request_confirmation()` has no memory, no session, nothing
written anywhere; every call is a fresh `Confirmation` object and a fresh
`input()` prompt. Combined with there being no persistence layer anywhere
in the codebase yet (per Part 52, unchanged since Phase 4), there was
nothing to accidentally cache against in the first place.

### Discovered, and worth documenting: an LLM argument-filling limitation

A casually-phrased goal, `"close the calculator app"`, led the LLM to fill
`process_name` as `"calc.exe"` — a reasonable guess (echoing its own prior
`apps.launch` call), but **wrong**: Calculator's real running process is
`CalculatorApp.exe` (a UWP-hosting detail also surfaced in Phase 9).
`apps.close_app()` handled this **safely**: it reported
`ToolResult(success=True, data={"closed": False})` rather than lying about
success — Part 30's "tool executed != task succeeded" held up even under
an imperfect, LLM-filled argument. This is exactly the kind of gap Part
12's OBSERVE/VERIFY step (a later phase) exists to close — this phase's
single-shot, unverified execution has no way to notice the guess was
wrong and try again. Logged as an observation during testing, not scored
as a failure — the main approve/deny/no-caching tests instead used a goal
that names the real process directly, to isolate the confirmation
mechanism's own correctness from this separate, already-safe-if-imperfect
argument-filling limitation.

---

## Live regression check

Ran `python -u main.py` for real after this phase's changes. Reached
`[ready] listening for wake word: 'hey jairus'` — full normal
initialization, identical to every prior phase's check. Process then
terminated.

## Protected files

`git diff` — all empty, confirmed after this phase's changes:

- `intent_parser.py`
- `assistant_loop.py` (`handle_command()`)
- `src/jairus/application/commands/command_gateway.py`
- `src/jairus/application/tasks/task_manager.py`
- `player_action.py`
- `src/jairus/infrastructure/automation/apps.py`
- `src/jairus/infrastructure/automation/windows_ui.py`
- `src/jairus/infrastructure/automation/browser.py`

---

## Known limitations

- Argument-filling is unverified against live system state (see the
  discovered limitation above) — a single-shot design with no
  observe/verify step, by this phase's own explicit scope.
- `request_confirmation()`'s `Confirmation.expires_at` is set (60s window)
  but never actually checked — the confirmation is always answered
  synchronously within the same blocking call, so expiry enforcement has
  no real effect yet. Left as an honest placeholder rather than removed,
  since the field is part of the domain model and a future async
  confirmation flow (voice/Android) will need it enforced for real.
- `Confirmation.command_id` is a synthetic placeholder UUID, not a real
  Command id — there is no Command this phase, by design (see Scope).
- The allow-list is a Python list literal in `agent_core.py`, not
  configurable without a code change — intentional for this phase (see
  the opening warning), not an oversight.
- No rate-limiting or loop-prevention on Ollama calls — a single goal
  makes exactly one LLM call, so this isn't reachable yet, but will matter
  once multi-step planning exists.

## Next recommended phase

Per the migration sequence, the next phase is **Phase 11 — Remove legacy
intent routing** (`intent_parser.py`/`handle_command()`'s if/elif replaced
by the Agent Core built here). **Not implemented in this phase.**
