# Jairus — Phase 11: Shadow-Mode Agent Core

**Migration step:** Phase 11 of `JAIRUS_ARCHITECTURE.md` (Part 14.13,
"Replace Intent Parser Gradually" — implemented here as shadow mode rather
than a legacy-adapter translation layer; see "Approach" below), building
on Phase 10's Agent Core.

**One-sentence summary:** the live voice assistant now runs the new Agent
Core, in parallel, on every real command — but strictly in a read-only
observer role that logs what it *would* have done, while the existing,
unmodified path is still the only thing that ever actually speaks, plays,
pauses, or touches anything.

---

## ⚠️ First phase that touches the live voice pipeline

Every phase from 5 through 10 was either fully standalone (Phases 5-9) or
tested with raw text goals outside the mic pipeline (Phase 10). **This is
the first phase where new code runs automatically, unattended, during a
real voice session** — every single time someone says "hey jairus" and
gives a command, from now on, two things happen instead of one. Treated
with the extra care that deserves.

---

## The approach: shadow mode, not a cutover

```
transcribed text
        │
        ├──────────────► submit_command() / handle_command()   (REAL — unchanged)
        │                        │
        │                        └──► the actual action: plays, pauses,
        │                             skips, speaks — exactly as before
        │
        └──────────────► Agent Core, dry_run=True                (SHADOW — new)
                                 │
                                 └──► LOGS what it would have called.
                                      Never executes. Never confirms.
                                      Never affects the real response.
```

The legacy path (`intent_parser.py` → `handle_command()`'s if/elif →
`player_action.py`) keeps being the **only** thing that actually acts,
byte-for-byte unchanged from Phase 10. Alongside it, the Phase 10 Agent
Core independently evaluates the exact same transcribed text and reports
what it would have picked — with zero ability to affect what the user
hears or sees.

**Why this, not a cutover, and not a literal "Legacy Adapter":** Part
14.13 itself says "the old intent parser should not disappear until the
new Agent Core has proven itself." Shadow mode is how that proof gets
gathered — real speech, real mis-transcriptions, real casual phrasing,
observed against the Agent Core's actual decisions, with **zero risk**,
before anyone commits to a cutover. **Deciding if/when to ever actually
cut over is an explicit, human decision for a future phase. This phase
does not attempt it, and does not recommend a timeline for it.**

---

## What was built / changed

### Modified: `src/jairus/application/agent/agent_core.py`

`run_goal()` gained two new, both-optional parameters — **no existing
call's behavior changes**:

```python
def run_goal(goal_text: str, allowed_tools: list[str] | None = None, dry_run: bool = False) -> ToolResult
```

- **`allowed_tools`** — overrides the module-level `ALLOWED_TOOLS`
  default (Phase 10's original 5-tool list). Omitting it keeps every
  existing caller (including Phase 10's own test suite, re-run unmodified
  after this change — see "Backward compatibility" below) working exactly
  as before.
- **`dry_run`** — Phase 11's shadow mode. When `True`:
  - Still makes a real LLM call and a real `policy_engine.evaluate()`
    call — the decision quality being observed has to be the real one.
  - **Structurally** never reaches `request_confirmation()` (the blocking
    terminal `input()`) or `execute_tool()`. This isn't "skipped because
    the policy happened to say allow" — the `if dry_run:` branch returns
    before either call is reachable **at all**, regardless of what
    `policy_decision` says. Verified directly (§ Testing) against a
    `DISRUPTIVE`/`requires_confirmation=True` tool, not just the
    `HARMLESS` ones the shadow allow-list actually uses.
  - Prints `[shadow] would call: {tool_name} args={...} (policy=...,
    dry run, not executed)` and returns a `ToolResult` describing the
    decision, not an executed outcome.

`_build_system_prompt()`/`_call_ollama()` were updated to take
`allowed_tools` as a parameter instead of reading the module global
directly — internal refactor, no behavior change for existing callers.

### Modified: `assistant_loop.py`

Confirmed by inspecting this repository's own `RECONNAISSANCE.md`: **the
"conversation-mode follow-up loop" (continuing without repeating the wake
word) does not exist in this codebase.** `README.md` describes it as an
intended feature; the actual code does not implement it —
`run_assistant()` has exactly one loop, and returns to wake-word listening
after every single command. There is therefore only **one** real place
text gets transcribed and handed off, not two — confirmed via
`grep`/direct reading before writing any code, not assumed. Only that one
site was wired. (If conversation mode is implemented in a later phase,
wiring shadow mode into its own transcription point would be a natural,
small follow-up then.)

Three small, additive pieces, nothing else touched:

1. **New imports + a hardcoded, media-only allow-list** (module level):
   ```python
   from jairus.application.agent import run_goal
   from jairus.tools import register_media_tools

   SHADOW_ALLOWED_TOOLS = [
       "media.play", "media.pause", "media.resume", "media.skip",
       "media.correct", "media.volume_up", "media.volume_down",
       "media.now_playing", "media.queue",
   ]
   ```
   Exactly Aria's existing 9 voice actions, nothing more — no
   `apps.launch`/`apps.close`, no `browser.*`/`windows.*`, even though
   all of those are registered and reachable in the full Tool Registry.
   Voice capability is **not** expanding this phase; only the
   decision-maker being observed is new.

2. **A new `_shadow_evaluate(text)` helper**, called once, right after the
   real `submit_command()` call — deliberately **after**, not before or
   in parallel (see "Ordering" below):
   ```python
   if text.strip():
       submit_command(text, CommandSource.VOICE, context, state, conversation_id)
       _shadow_evaluate(text)  # Phase 11: dry-run only, observes/logs, never executes
   else:
       print("[skip] heard nothing usable, going back to sleep")
   ```
   `_shadow_evaluate()` itself wraps `run_goal(text, allowed_tools=SHADOW_ALLOWED_TOOLS,
   dry_run=True)` in its own `try/except Exception`, printing
   `[shadow] evaluation failed: {error}` and continuing — this can **never**
   propagate into the main loop, tested explicitly (§ Testing).

3. **One-time `register_media_tools()` call** added near the top of
   `run_assistant()` (Phase 5's `ToolDefinition`s are inert data until
   registered — nothing else in the live process had ever called this).

**`handle_command()`'s internals, `command_gateway.py`, and
`task_manager.py` are all untouched** — confirmed via `git diff` (§
Protected files).

### Ordering: why shadow runs *after* the real action, not before

The task description explicitly allowed either "before or immediately
alongside." Shadow evaluation makes its own real Ollama call, which takes
real time — running it *before* `submit_command()` would delay how long
the user waits to hear "Paused"/"Playing X" by that entire extra round
trip. Running it *after* means the real response the user hears is
**exactly as fast as it was in Phase 10** — shadow's latency only extends
how long the loop takes to get back to "listening for wake word again," a
backend detail invisible to the user. This is the more conservative
reading of "the real assistant must be 100% unaffected."

### Known, accepted tradeoff (not fixed this phase)

Every voice command now makes roughly double the Ollama calls it did
before (the existing `intent_parser.py` call, unless fast-pathed by
`quick_commands.py`, plus the new shadow `agent_core.py` call, which has
no fast path and always calls the LLM). The added latency for this
observation period is accepted, per the task's explicit instruction — no
parallelization or optimization was attempted.

---

## Backward compatibility

Phase 10's own test suite (`run_goal()` called with no new arguments, for
`media.pause`/`media.skip`/`apps.launch`/`apps.close`, including the
approve/deny/no-caching proofs) was re-run **unmodified** after this
phase's `agent_core.py` refactor: all 11 checks still passed. The only
adjustment needed anywhere was in an unrelated ephemeral test script's own
monkeypatch of a *private* helper (`_call_ollama`'s signature gained a
parameter) — not a behavior change to `run_goal()`'s public contract.

---

## Testing

**This phase required real voice-adjacent testing, not stubs — done as
honestly as this environment allows.**

**An unavoidable, disclosed limitation:** this environment has no way to
physically produce audio for a microphone to capture, so the
mic-capture → wake-word-detection → Whisper-transcription step itself
could not be exercised by speaking out loud. That step is **also
untouched by this phase** — Phase 11 only adds a call *after* `text`
already exists. Everything from that point on **was** run for real,
unstubbed: the actual `handle_command()` (real `intent_parser.py`,
real fast-path/Ollama routing, real `player_action.py`, real `pyttsx3`
speech), and the actual `_shadow_evaluate()` (real Agent Core, real
Ollama). Realistic lowercase, punctuation-light phrasing (matching
Whisper's typical output style) stood in for what a spoken utterance
would transcribe to — driven directly through `assistant_loop.handle_command()`
then `assistant_loop._shadow_evaluate()`, the identical pair of calls, in
the identical order, the real wake-word loop makes.

### Real action + shadow decision, side by side

| Said (simulated transcript) | **Real action (unchanged)** | **`[shadow]` log** |
|---|---|---|
| `"play some lo-fi beats"` | Ollama-parsed → searched & played on YouTube; spoke "Playing some lo-fi beats" | `would call: media.play args={'title': 'lo-fi beats'} (policy=allow, dry run, not executed)` |
| `"pause"` | Fast-pathed, no LLM; YouTube paused; spoke "Paused" | `would call: media.pause args={} (policy=allow, dry run, not executed)` |
| `"resume"` | Fast-pathed; resumed; spoke "Resumed" | `would call: media.resume args={} (policy=allow, dry run, not executed)` |
| `"skip"` | Fast-pathed; skipped via YouTube up-next; spoke "Skipped" | `would call: media.skip args={} (policy=allow, dry run, not executed)` |
| `"turn it up"` | Fast-pathed; YouTube volume raised; spoke "Turned it up" | `would call: media.volume_up args={} (policy=allow, dry run, not executed)` |
| `"what's playing"` | Fast-pathed; spoke the real current track title | `would call: media.now_playing args={} (policy=allow, dry run, not executed)` |

**The Agent Core's decisions matched the legacy path's own decision on
every single command tested** — a genuinely encouraging early signal for
whatever future phase eventually considers a cutover, though (per the
"Approach" section) that call is explicitly not made or hinted at here.

**Regression confirmed, the most important check in this phase:** every
real action above happened exactly as it would have before Phase 11 —
same log lines, same spoken responses, same underlying `player_action.py`
calls. Nothing about the real path's behavior, timing-to-response, or
output changed.

### Conversation mode

**Not tested — because it does not exist in this codebase** (see
"Modified: `assistant_loop.py`" above). Only the one real call site was
wired; there was no second one to test.

### Shadow-evaluation failure resilience — tested twice, two different ways

**1. A real, sustained Ollama outage.** Both the Ollama server process and
its tray supervisor (which auto-restarted the server too quickly on a
first, less aggressive attempt — itself a real, minor finding: Ollama's
Windows tray app self-heals the server within a couple of seconds by
default) were stopped and the outage confirmed sustained (unreachable for
5+ consecutive seconds) before proceeding:

```
=== confirmed sustained outage -- running 'pause' through the real loop's two calls ===
--- real path: handle_command() ---
[intent] fast-pathed 'pause' -> pause (no LLM call)
[player] paused (YouTube)
[voice] Paused
  handle_command returned True (expected True -- fast-pathed, no Ollama dependency)
--- shadow path: _shadow_evaluate() ---
[agent] goal: 'pause' [dry run]
[agent] LLM call/parse failed: HTTPConnectionPool(...): Failed to establish a new
connection: [WinError 10061] No connection could be made because the target
machine actively refused it
  (execution reached this line -- _shadow_evaluate() did not propagate an exception)
```

The real action was completely unaffected (fast-pathed commands don't
touch Ollama at all). Notably, `run_goal()`'s **own** internal
`try/except` (around its Ollama HTTP call, already built in Phase 10)
caught the connection failure and returned a clean
`ToolResult(failure_category=BACKEND_UNAVAILABLE)` — so `_shadow_evaluate()`'s
outer `try/except` had nothing left to catch *for this particular failure
mode*. Ollama was then restarted (`ollama serve`) and confirmed reachable
again within 2 seconds.

**2. A deterministic test of `_shadow_evaluate()`'s own wrapper**, to
prove that layer is a real, working safety net and not just redundant
with `run_goal()`'s internal handling — `run_goal` itself was made to
raise directly (a failure mode `run_goal()`'s own internal handling
doesn't already catch):

```
=== _shadow_evaluate() with run_goal() itself raising ===
[shadow] evaluation failed: simulated unexpected failure
(execution reached this line -- the wrapper's own try/except caught it, as designed)
```

Together, these two results show **layered** resilience: an Ollama
connection failure is caught by `run_goal()`'s own existing handling; any
other kind of unexpected failure is caught by `_shadow_evaluate()`'s
wrapper. Either layer alone would have kept the real assistant unaffected.

**A side note on restoring the environment:** only the bare `ollama serve`
process was relaunched (needed for shadow mode to work again); Ollama's
tray icon app (`ollama app.exe`) was not automatically relaunched, since
there's no simple way to do that from here — the underlying service works
identically without it, but its tray UI won't reappear until it's started
again manually, if you use it.

---

## Live regression check

Ran `python -u main.py` for real after this phase's changes. Reached
`[ready] listening for wake word: 'hey jairus'` — full normal
initialization, including the new one-time `register_media_tools()` call
added to `run_assistant()` executing without error. Identical to every
prior phase's check.

## Protected files

`git diff` — all empty, confirmed after this phase's changes:

- `intent_parser.py`
- `src/jairus/application/commands/command_gateway.py`
- `src/jairus/application/tasks/task_manager.py`
- `player_action.py`
- `src/jairus/infrastructure/automation/apps.py`
- `src/jairus/infrastructure/automation/windows_ui.py`
- `src/jairus/infrastructure/automation/browser.py`

`handle_command()`'s internals specifically (inside the modified
`assistant_loop.py`) are also untouched — only two additive lines were
added around its existing, unmodified call site, plus new module-level
setup above it. `git diff` on `assistant_loop.py` shows exactly that: new
imports/constants/a new function, one `register_media_tools()` call, and
one new line calling `_shadow_evaluate(text)` right after the existing
`submit_command(...)` call.

---

## How to read the shadow logs

Every real voice command now produces, alongside the normal output, one
line starting with `[agent] goal: '...'  [dry run]` and one of:

- `[shadow] would call: <tool> args=<dict> (policy=allow|confirm, dry run, not executed)`
  — the Agent Core found a matching tool among the 9 media actions.
- `[agent] no tool selected: <reason>` — the Agent Core found no suitable
  match among the 9 (this is `run_goal()`'s own existing log line, not a
  new one — dry mode doesn't change how a "no match" is reported, only
  how a *found* tool is reported).
- `[shadow] evaluation failed: <error>` — something went wrong running
  the shadow evaluation itself (e.g. Ollama unreachable, if `run_goal()`'s
  own internal handling didn't already produce a clean result first). The
  real response for that command is unaffected either way.

None of these lines are spoken, and none of them change the orb's status
or the real command's outcome — they only appear in the terminal.

---

## What this phase explicitly does NOT do

- **Does not decide, recommend, or schedule a cutover.** Whether and when
  the Agent Core ever becomes the thing that actually executes voice
  commands is an explicit future human decision — this phase exists to
  gather the evidence for that decision, not to make it.
- **Does not expand voice capability.** The shadow allow-list is exactly
  the 9 tools Aria could already do via voice before this phase — no
  `apps.*`, `browser.*`, or `windows.*`.
- **Does not touch `handle_command()`'s internals**, `command_gateway.py`,
  or `task_manager.py`.
- **Does not implement conversation mode** — it doesn't exist in this
  codebase yet, so there was nothing to wire a second call site into.
- **Does not optimize the doubled Ollama-call latency** — an accepted,
  temporary cost of the observation period.
