# Jairus — Phase 12: Voice Input Adapter

**Migration step:** Phase 12 of `JAIRUS_ARCHITECTURE.md` (Part 14.14,
"Migrate Voice"), adapted — see below — around Part 11.7 ("Input
Adapters": "the agent should not care where a command came from").

**One-sentence summary:** the existing, inline
`command_gateway.submit_command(text, CommandSource.VOICE, ...)` call in
`assistant_loop.py` moved into its own module,
`interfaces/voice/voice_adapter.py` — same call, same arguments, same
return value, just relocated to the layer the architecture actually
describes for it.

---

## Adapted scope — why this isn't the doc's literal Phase 12

`JAIRUS_ARCHITECTURE.md`'s own Phase 12 assumes the Agent Core already
makes real, live decisions by this point in the sequence — it's framed as
wiring voice into an Agent Core that's already the thing running commands.
**That assumption doesn't hold in this repo.** Phase 11 built shadow mode,
not a cutover: the legacy path is still the only thing that ever executes
anything, and no cutover has happened or was scheduled.

So this phase is scoped down to what's actually true here: it formalizes
voice as a proper input adapter **at the wiring level** —
`Wake Word -> Recorder -> Whisper -> Voice Adapter -> Gateway`, per Part
14.14's own diagram — without changing **who** decides what runs. This
changes *where* the call happens, not *what* happens or *who* decides.

---

## What moved

### New: `src/jairus/interfaces/voice/voice_adapter.py`

```python
def submit_voice_command(text: str, context, state, conversation_id: str) -> Command
```

Does exactly what the inline call in `assistant_loop.py` did since Phase
3 — calls `command_gateway.submit_command(text, CommandSource.VOICE,
context, state, conversation_id)` and returns its result. Nothing added:
no new validation, no new logging, no new logic of any kind. `source` is
fixed to `CommandSource.VOICE` inside the adapter, since every caller of
a *voice* adapter already knows that — one fewer import
(`CommandSource`) needed at the call site.

### Changed: `assistant_loop.py`

Two-line diff, same shape as Phase 3's original change to this file:

```diff
-from jairus.application.commands.command_gateway import submit_command
-from jairus.domain.commands import CommandSource
+from jairus.interfaces.voice import submit_voice_command
```

```diff
-                    submit_command(text, CommandSource.VOICE, context, state, conversation_id)
+                    submit_voice_command(text, context, state, conversation_id)
```

**Phase 11's shadow-evaluation call site — the very next line,
`_shadow_evaluate(text)` — was not touched at all**, character for
character identical to how Phase 11 left it, including its own docstring
and internal logic. `_shadow_evaluate()`'s docstring still refers to
"the real `submit_command()` above" — still accurate in substance
(`submit_voice_command()` is a one-line wrapper around exactly that call),
just one level more indirect than the literal function name now visible
at the call site. Left as-is rather than edited, per this phase's own
instruction to leave Phase 11's shadow call site exactly as it is.

---

## What did NOT change (confirmed via diff)

- `handle_command()`'s internals — untouched.
- `intent_parser.py` — 0 lines changed.
- `command_gateway.py` — 0 lines changed. It still does exactly what it
  did in Phase 4: create the `Command`, create the linked `Task`, call
  the unmodified `handle_command()`, drive both to their final status.
- `task_manager.py` — 0 lines changed.
- **`agent_core.py` — 0 lines changed.**
- **`policy_engine.py` — 0 lines changed.**
- Shadow mode's behavior, log format, and allow-list — unchanged, verified
  in testing below (identical `[shadow]` output to Phase 11).

No feature flag, no `if USE_AGENT_CORE:` branch, no scaffolding of any
kind toward a future cutover was added. Per Phase 11's own conclusion,
deciding whether and when the Agent Core ever becomes the thing that
actually executes voice commands is an explicit human decision for later
— this phase doesn't move that decision any closer, structurally or
otherwise.

---

## Testing

Real, not stubbed — same honest constraint as Phase 11: this environment
has no way to physically speak into a microphone, so the
mic-capture → wake-word → Whisper step itself wasn't exercised (it's also
untouched by this phase — the adapter only sits after `text` already
exists). Everything from that point on was run for real: the actual new
`submit_voice_command()` call site, the actual unmodified
`command_gateway`/`task_manager`/`handle_command()`/`player_action.py`
chain, and the actual unmodified `_shadow_evaluate()`.

1. **`python -u main.py`** — real process, real startup. Reached
   `[ready] listening for wake word: 'hey jairus'`, confirming the new
   `jairus.interfaces.voice` import resolves cleanly with no import
   errors, same as every prior phase's check.
2. **Two realistic simulated transcripts** (a play request and a
   fast-path command — "pause"), driven through
   `assistant_loop.submit_voice_command()` then
   `assistant_loop._shadow_evaluate()`, the exact pair the real loop now
   calls:

   ```
   [simulated transcript] play some lo-fi beats
   [gateway] command 266a9515-... received: 'play some lo-fi beats'
   [task] task 3ef3ec32-... received (command 266a9515-...)
   [gateway] command 266a9515-... -> understanding
   [task] task 3ef3ec32-... -> executing
   [intent] parsed via Ollama (free)
   [voice] Playing some lo-fi beats
   [player] playing 'some lo-fi beats' (YouTube)
   [gateway] command 266a9515-... -> completed
   [task] task 3ef3ec32-... -> completed
   [shadow] would call: media.play args={'title': 'lo-fi beats'} (policy=allow, dry run, not executed)

   [simulated transcript] pause
   [intent] fast-pathed 'pause' -> pause (no LLM call)
   [player] paused (YouTube)
   [voice] Paused
   [gateway] command 5917fdd8-... -> completed
   [task] task 8a535418-... -> completed
   [shadow] would call: media.pause args={} (policy=allow, dry run, not executed)
   ```

   **Byte-for-byte identical in shape and content to Phase 11's own
   test output** — same `[gateway]`/`[task]`/`[intent]`/`[player]`/`[voice]`
   log lines, same real playback behavior (a real song started, a real
   pause happened), same `[shadow] would call: ...` lines with the same
   tool/argument decisions. This phase is invisible from the user's (and
   the log's) perspective, exactly as intended — the test above is what
   proves that, not anything new working.

---

## Live regression check

`python -u main.py` reached `[ready] listening for wake word: 'hey
jairus'` — normal full initialization. Identical to every prior phase's
check.
