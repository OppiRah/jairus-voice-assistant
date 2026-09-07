# Jairus — Phase 0 Repository Reconnaissance

**Status:** Reconnaissance snapshot — no code changes made
**Scope:** Current-state audit of the existing repository, mapped against the
target architecture in `JAIRUS_ARCHITECTURE.md` (Parts 1–15).
**Explicitly out of scope:** proposing migration steps, sequencing, or first
moves. This document is an honest inventory, not a plan.

---

## 1. Method

Every non-vendored source file in the repository was read in full:

- 15 Python modules in the repo root (`*.py`, ~1,562 LOC total excluding the
  architecture doc).
- `README.md` (299 lines), `requirements.txt` (9 lines).
- `JAIRUS_ARCHITECTURE.md` (7,778 lines) in full.
- `__pycache__/` was inspected to confirm no additional (deleted/renamed)
  modules ever existed — the 14 cached `.pyc` files correspond exactly to the
  14 importable modules present today.

`venv/` (9,000+ files) and `browser_profile/` (a checked-in Brave user-data
directory, ~5 MB) were catalogued but not treated as project source.

---

## 2. Repository Snapshot

### 2.1 Inventory

| File | LOC | Role in the running system |
|---|---:|---|
| `main.py` | 29 | Process entry point. Inits pygame, creates shared state, starts the assistant on a background thread, runs the orb UI on the main thread. |
| `assistant_loop.py` | 172 | The always-on voice loop: wake word → record → transcribe → `handle_command()` (intent extraction + a large `if/elif` action dispatch + spoken replies). This is the spine of the current system. |
| `assistant_state.py` | 26 | Thread-safe holder for two values: `status` (`idle`/`listening`/`thinking`/`speaking`) and `level` (0–1 audio level for the orb). |
| `audio_utils.py` | 79 | `record_until_silence()` — RMS-threshold voice-activity recorder. |
| `transcribe.py` | 41 | `faster-whisper` (`small`, CUDA, `int8_float16`) STT wrapper, lazy-loaded singleton. |
| `intent_parser.py` | 134 | `extract_intent()`: quick-command fast path → Ollama (`qwen2.5:7b`) → optional Claude escalation. Returns a fixed dict `{action, title, artist, songs}`. |
| `quick_commands.py` | 55 | Deterministic fuzzy match of short utterances against canonical phrases for `pause/resume/skip/volume/whats_playing/correct`. No LLM. |
| `claude_client.py` | 57 | Raw `requests` POST to the Anthropic Messages API (`claude-haiku-4-5-20251001`). Reads `ANTHROPIC_API_KEY` from env; raises if absent. |
| `context.py` | 47 | `ConversationContext`: last 4 raw transcripts + `last_song`. Renders a prompt block. In-memory only, reset on restart. |
| `player_action.py` | 291 | The "playback brain". Routes `play/pause/resume/skip/correct/volume/now_playing` across three backends (local files → YouTube via CDP → system media keys), plus multi-song queue and search-result correction. Holds most of the system's mutable state in module globals. |
| `local_library.py` | 69 | Lazy filename index of a configured music folder + `difflib` fuzzy match. Disabled by default (`MUSIC_LIBRARY_DIR = None`). |
| `local_player.py` | 57 | `pygame.mixer` local-file playback with its own play/pause/volume state (module globals). |
| `media_keys.py` | 49 | `ctypes` Win32 `keybd_event` calls for Play/Pause, Next, Volume Up/Down. Windows-only. |
| `tts.py` | 58 | `pyttsx3` (SAPI5) speech. Also flips `AssistantState` to `speaking` and runs a thread that feeds the orb a randomised "talking" animation level. |
| `orb_ui.py` | 90 | Pygame window that reads `AssistantState` and draws a pulsing orb. Closing the window calls `os._exit(0)` and ends the process. |

### 2.2 Dependencies (`requirements.txt`)

`openwakeword`, `sounddevice`, `numpy`, `faster-whisper`, `requests`,
`playwright`, `pyttsx3`, `pywin32`, `pygame`. PyTorch/CUDA and
`python -m playwright install chromium` are documented manual steps.

### 2.3 Non-code assets

- `hey_jairus.onnx` (415 KB) — a **custom-trained openWakeWord model** for
  "hey jairus" is present and is what `assistant_loop.py` actually loads.
- `browser_profile/` — a checked-in Brave profile directory. Not referenced by
  any code; appears to be a manual artifact of CDP testing.
- `__pycache__/` — build artifact, checked in.

### 2.4 Project management state

- **Not a git repository.** The architecture doc's Phase 0 assumes a
  "Git checkpoint" as step one; there is currently no version control, no
  `.gitignore`, no `pyproject.toml`, no `src/` package layout.
- **No tests** of any kind.
- **No configuration layer** — tunables are module-level constants edited in
  place (`WAKE_WORD_MODEL`, `DETECTION_THRESHOLD`, `MODEL_SIZE`,
  `OLLAMA_MODEL_NAME`, `ESCALATE_QUEUE_TO_CLAUDE`, `MUSIC_LIBRARY_DIR`,
  `SILENCE_THRESHOLD`, `CDP_URL`, …).

---

## 3. How the System Actually Works Today

### 3.1 Runtime shape

Two threads, started by `main.py`:

- **Main thread:** `orb_ui.run_orb(state)` — 60 fps pygame render loop, read-only
  against `AssistantState`.
- **Daemon thread:** `assistant_loop.run_assistant(state)` — the voice pipeline.
- A **third, transient thread** is spawned by `tts.speak()` for the duration of
  each utterance to animate the orb.

Shared state between them is exactly one object: `AssistantState` (status enum +
float level, guarded by a `threading.Lock`).

### 3.2 The actual data flow

```text
sounddevice InputStream (16 kHz, 80 ms int16 chunks)
        │
        ▼
openWakeWord Model.predict(chunk)  ──  score > 0.5 ?
        │ (idle: chunk RMS also drives a subtle orb level)
        ▼  yes
stream.stop()  →  state="listening"  →  tts.speak("Yes?")
        │
        ▼
audio_utils.record_until_silence()      (RMS VAD, 0.8 s trailing silence)
        │
        ▼  state="thinking"
transcribe.transcribe_audio()           (faster-whisper, GPU)
        │  text
        ▼
assistant_loop.handle_command(text, context, state):
        │
        ├─ intent_parser.extract_intent(text, context)
        │     ├─ quick_commands.match_quick_command()      → dict, or
        │     ├─ Ollama /api/generate  (qwen2.5:7b, temp 0) → dict, or
        │     └─ claude_client.call_claude() [fallback / opt-in queue upgrade]
        │           → dict {action, title, artist, songs}
        │
        ├─ big if/elif on intent["action"]:
        │     play / queue / pause / resume / skip / correct /
        │     volume_up / volume_down / whats_playing
        │        │
        │        ▼  player_action.*:
        │        ├─ _play_resolved_song(): local_library match?
        │        │     ├─ yes → local_player (pygame.mixer)
        │        │     └─ no  → _play_youtube(): Playwright connect_over_cdp
        │        │             → new tab → youtube.com/results → click result
        │        ├─ pause/resume/skip/volume: local? → CDP page.evaluate? → media_keys
        │        └─ queue: list of songs, _queue_index advances on skip
        │
        ├─ tts.speak(<canned phrase>, state)   (state="speaking")
        │
        └─ context.add_turn(text, intent)      (last 4 transcripts + last_song)
        │
        ▼  state="idle", level=0, oww_model.reset(), stream.start()
back to wake-word listening
```

### 3.3 Key characteristics of the current design

- **Intent → Action Router**, exactly as the architecture doc describes the
  "old" model. The router is a single `if/elif` chain in `handle_command()`.
- **Tools are plain functions**, imported directly and called by name. There is
  no registry, no schema, no indirection.
- **The intent schema is media-shaped.** `{action, title, artist, songs}` can
  only express music/video requests. There is no generic "goal" concept.
- **State lives in module globals.** `player_action._queue`,
  `_playback_mode`, `_last_search_results`, `_last_played_page`;
  `local_player._current_track`, `_volume`. Restart loses everything.
- **"Executed" is assumed to mean "succeeded."** Nothing observes or verifies
  outcomes; the spoken reply ("Playing X") is emitted before/around the action
  regardless of whether playback actually started.
- **Everything is synchronous and single-flight** — one command is fully
  handled before the loop resumes listening. This is incidental, not enforced
  by a scheduler.
- **Observability is `print()`** to stdout with `[tag]` prefixes.
- **The only "stop" is closing the orb window** (`os._exit(0)`), or Ctrl+C.

---

## 4. Module-by-Module Notes

### `main.py`
Thin composition root. Threading model and pygame lifetime live here. Target
equivalent is `src/jairus/main.py` as the runtime bootstrap (Part 11.5 startup
sequence), but that sequence is far larger (config → DB → LLM → tools → voice →
gateway → READY) than the current three lines.

### `assistant_loop.py`
The single most architecturally significant file, because it fuses roles the
target keeps separate:

- Wake-word listening + audio stream ownership → **Voice Input Adapter** /
  `infrastructure/audio/wakeword` + `interfaces/voice`.
- `handle_command()` intent-extraction call → belongs to the **Agent Core**
  understanding step.
- `handle_command()` `if/elif` dispatch → the **Action Router** that the doc
  says is replaced by **Agent Core + Tool Registry + Tool Executor**.
- Canned spoken replies inline in each branch → **Response Generation** (Part
  65) + TTS backend.
- `context.add_turn()` call → **Context Manager**.
- Status transitions (`listening`/`thinking`/`speaking`/`idle`) → **Runtime
  State Manager** / command lifecycle.

No command ID, no task, no policy, no confirmation, no verification, no
cancellation of an in-flight command.

Stale comment: the header block claims the wake word "stays `hey_jarvis`"
because no custom model exists — but the code loads `hey_jairus.onnx` (a custom
model that *is* in the repo). See §6.

### `assistant_state.py`
Correct, minimal, thread-safe. Represents a thin slice of the target's
**Runtime State** (Part 51): only presentation status + audio level. Target
runtime state also tracks active task, current application, current browser
page, current execution. The lock-guarded snapshot pattern is reusable.

### `audio_utils.py`
Self-contained RMS voice-activity recorder. Maps cleanly to
`infrastructure/audio/recording`. The doc (Phase 12) explicitly expects this to
"survive almost unchanged." Only coupling is the `on_level` callback into the
orb.

### `transcribe.py`
Clean `faster-whisper` singleton. Maps to `infrastructure/audio/stt`. Survives
almost unchanged. Hard-codes `device="cuda"` and model size.

### `intent_parser.py`
Three concerns braided together:

1. **Fast path** (`match_quick_command`) → target **Fast Path** (Parts 69–70),
   near the Gateway/Agent boundary.
2. **LLM calls** — direct `requests` to `localhost:11434` and, via
   `claude_client`, to the Anthropic API → target `infrastructure/llm/` with an
   **LLM Provider interface** (`generate_decision(context) → Decision`), Ollama
   and cloud as interchangeable providers.
3. **Escalation policy** (Ollama fails, or `ESCALATE_QUEUE_TO_CLAUDE` for
   playlists) → a bespoke fallback ladder; the target model is provider
   abstraction where the Agent Core is indifferent to which model answered.

The output contract `{action, title, artist, songs}` is replaced in the target
by the structured decision schema `{type, tool, arguments, message}` (Part 67),
where `type ∈ {tool_call, complete, ask_user, recover}`.

This is the module the migration plan (Phases 11–13) describes wrapping behind a
"legacy adapter" and then deleting.

### `quick_commands.py`
Small, deterministic, exactly the shape Part 70 wants ("frequent, unambiguous,
low-risk, easy to identify deterministically"). Canonical-phrase table +
`SequenceMatcher` + a 6-word cap. Portable to the target Fast Path with little
change, though it currently emits the media-shaped intent dict.

### `claude_client.py`
Single-turn Anthropic Messages call. Becomes one implementation behind the LLM
Provider interface (`infrastructure/llm/anthropic_provider.py`). Note: the
target V1 is explicitly **Ollama-only with abstraction**, cloud "optional
later" — so a working cloud path exists today but is *not* abstracted, which is
the part that doesn't match.

### `context.py`
`ConversationContext` = last 4 transcripts + `last_song {title, artist}`,
flattened into a prompt string. Maps to **Context Manager / Conversation
Context** (Part 53), but:

- `last_song` is media-specific and would need to generalise to
  "recent task / referent" state.
- It concatenates raw conversation turns straight into the model prompt; the doc
  is explicit that "conversation history should not automatically become Agent
  context" (Parts 51, 53, 57–58) — the target has a Context Builder that
  curates layered, minimised context.

### `player_action.py`
The largest and richest module. Contains, inline and interleaved:

- **Media capability surface**: `play_song`, `pause_music`, `resume_music`,
  `skip_music`, `correct_song`, `adjust_volume`, `get_now_playing`,
  `start_queue` → target `tools/media/*` tool definitions
  (`media.play`, `media.pause`, `media.resume`, `media.next`,
  `media.volume_set`, `media.now_playing`).
- **A hand-rolled backend hierarchy**: local file → YouTube/CDP → system media
  keys. This is a good instinct that matches the doc's "Automation Backend
  Hierarchy" (Part 19) — but it is implemented as `if _playback_mode == ...`
  branches inside each function rather than as pluggable adapters in
  `infrastructure/automation/`.
- **Browser automation**: Playwright `connect_over_cdp("http://localhost:9222")`,
  tab creation, selector-based result clicking, `page.evaluate()` for
  play/pause/volume → target `infrastructure/automation/browser/` behind a
  browser adapter. Connection lifecycle is currently the user's manual
  responsibility (launch Brave with `--remote-debugging-port=9222`).
- **Sequencing logic**: `_queue` / `_queue_index` advancement, `correct_song()`
  cycling through `_last_search_results` → in the target this is Agent Core
  task state / sequencing, not backend state.
- **Mutable runtime state in module globals** (7 of them) → target **Runtime
  State Manager**; also what Android's `command.status` queries would need to
  read.
- **No verification**: `play_song` never confirms audio is producing sound;
  `game.launch`-style "executed ≠ succeeded" (Part 30) applies here already.

### `local_library.py`
Filename-only fuzzy index of one configured folder. Disabled by default. Maps to
a media backend under `infrastructure/` and/or informs a future
`filesystem.search`-style capability. `difflib` matching on `path.stem`.

### `local_player.py`
`pygame.mixer` playback + `_volume` / `_current_track` globals. A media backend
in the target. Shares the pygame mixer with nothing else, but pygame itself is
also init'd by `main.py`/`orb_ui.py`.

### `media_keys.py`
`ctypes` Win32 virtual-key presses. The lowest tier of the media backend
hierarchy. Windows-only (degrades to a printed warning elsewhere). Maps to
`infrastructure/platform/` or `infrastructure/automation/input/`.

### `tts.py`
`pyttsx3` speech synthesis **plus** orb animation control. Two target concerns
in one file: `infrastructure/audio/tts` (the backend) and the Agent-side
**Response Generation** trigger. The orb-animation thread also makes this file a
second writer to `AssistantState`, alongside `assistant_loop`.

### `orb_ui.py`
Pure presentation, read-only against `AssistantState`. Maps to
`interfaces/desktop/` (or a voice-companion UI). `os._exit(0)` on window close
is the de facto process kill switch — related to, but not the same as, the
doc's **LLM-independent emergency stop** for tasks (Part 27), which needs to
cancel an in-flight task without killing the process.

---

## 5. Target Architecture (brief recap)

From `JAIRUS_ARCHITECTURE.md`, the intended pipeline is:

```text
Input Adapters (Voice, Android text, …)
      ↓
Command Gateway        — auth, validation, command IDs, events, cancellation
      ↓
Task Manager           — lifecycle, one autonomous task at a time, timeouts
      ↓
Agent Core             — understand → plan → validate → execute → observe → verify
   ├── Context Builder — curated, layered, minimal context
   ├── LLM Provider    — abstract; Ollama first, cloud optional later
   └── Policy Engine    — permission levels 0–3, confirmation, budgets
      ↓
Tool Registry          — allowlisted capabilities, schemas, permissions, verifiers
      ↓
Tool Executor          — schema-validate → policy → execute → observe → verify
      ↓
Automation Backends    — native API > Windows UIA > browser/CDP > input sim > vision
      ↓
Observation / Verification → Task result → Complete | bounded Recover
```

Cross-cutting: domain models (`Command`, `Task`, `ToolDefinition`, `ToolResult`,
`Permission`, `Confirmation`), a Repository layer over SQLite/Oracle, structured
audit traces, a JSON WebSocket protocol for Android, and a `src/jairus/` modular
monolith layout (`domain/ application/ interfaces/ tools/ infrastructure/
configuration/ observability/`).

---

## 6. Mapping: Current → Target

| Current code | Target home | Fit |
|---|---|---|
| `main.py` thread bootstrap | `src/jairus/main.py` runtime bootstrap (Part 11.5) | Concept survives; scope grows substantially. |
| `assistant_loop.py` wake-word + stream loop | Voice Input Adapter + `infrastructure/audio/wakeword` + `interfaces/voice` | Clean extraction once the loop stops calling `handle_command` directly. |
| `assistant_loop.handle_command()` intent call | Agent Core — understand step | Becomes one call into the decision loop. |
| `assistant_loop.handle_command()` `if/elif` dispatch | **Agent Core + Tool Registry + Tool Executor** | Does not survive — this *is* the "Action Router" the doc replaces. |
| Canned `speak(...)` phrases per branch | Response Generation (Part 65) + TTS backend | Phrasing moves out of the router. |
| `assistant_state.py` | Runtime State Manager (slice of Part 51) | Pattern reusable; must widen beyond status+level. |
| `audio_utils.py` | `infrastructure/audio/recording` | Near-verbatim (Phase 12). |
| `transcribe.py` | `infrastructure/audio/stt` | Near-verbatim. |
| `quick_commands.py` | Fast Path (Parts 69–70) | Good fit; output type changes. |
| `intent_parser.py` fast-path branch | Fast Path | See above. |
| `intent_parser.py` Ollama/Claude calls | `infrastructure/llm/` + LLM Provider interface | Logic reshaped around `generate_decision()`. |
| `intent_parser.py` `{action,title,artist,songs}` schema | Decision schema `{type,tool,arguments,message}` (Part 67) | Replaced. |
| `claude_client.py` | `infrastructure/llm/anthropic_provider.py` | Fits as a provider; ahead of the "Ollama-only V1" line. |
| `context.py` | Context Manager / Conversation Context (Part 53) | Fits; `last_song` must generalise; must stop auto-feeding raw turns to the prompt. |
| `player_action.py` media functions | `tools/media/*` tool definitions | Capability list matches Part 15.4 almost 1:1. |
| `player_action.py` local→YouTube→media-keys branching | `infrastructure/automation/*` backend adapters + backend hierarchy (Part 19) | Right idea, wrong layer — currently inline branches, not adapters. |
| `player_action.py` CDP/Playwright code | `infrastructure/automation/browser/` | Fits; adapter should own the CDP connection lifecycle. |
| `player_action.py` `_queue` / `correct_song` sequencing | Agent Core task state / sequencing | Moves out of the backend. |
| `player_action.py` / `local_player.py` module globals | Runtime State Manager | Must become explicit, queryable state. |
| `local_library.py` | media backend under `infrastructure/` | Fits. |
| `local_player.py` | media backend under `infrastructure/` | Fits. |
| `media_keys.py` | `infrastructure/platform/` or `.../automation/input/` | Fits as lowest backend tier. |
| `tts.py` speech | `infrastructure/audio/tts` | Fits. |
| `tts.py` orb-animation thread | `interfaces/` presentation concern | Should be decoupled from the TTS backend. |
| `orb_ui.py` | `interfaces/desktop/` | Fits; read-only-against-state pattern is already correct. |
| `hey_jairus.onnx` | asset consumed by the wakeword backend | Fits; keep. |

---

## 7. Things That Do Not Cleanly Map / Need Structural Change

1. **No domain layer.** Everything is passed as ad-hoc dicts (`intent`) and
   strings. `Command`, `Task`, `ToolDefinition`, `ToolCall`, `ToolResult`,
   `Permission`, `Confirmation`, `TaskStatus`, `CommandSource` do not exist.
   These are the shared vocabulary the rest of the target design assumes.

2. **No Command Gateway and no command identity.** The voice loop calls
   `handle_command()` in-process. There are no command IDs, conversation IDs, or
   task IDs, so nothing downstream can be tracked, cancelled by reference,
   confirmed against, audited, or reported to a second client.

3. **No Task Manager / lifecycle.** There is no `RECEIVED → UNDERSTANDING →
   PLANNING → WAITING_CONFIRMATION → EXECUTING → OBSERVING → COMPLETED` state
   machine, no timeouts, no "one autonomous task at a time" enforcement (it is
   single-flight only because the loop blocks), no `FAILED/RECOVERING/
   CANCELLED/INTERRUPTED` states.

4. **No Tool Registry / Tool Executor / schema validation.** "Tools" are
   imported Python functions dispatched by string match. The LLM's output is
   trusted structurally (parsed as JSON, defaulted) but never validated against
   a per-tool input schema, and there is no allowlist boundary — the defense-in-
   depth chain in Part 18 is entirely absent.

5. **No Policy Engine.** No permission levels, no notion of destructive vs
   harmless, no confirmation system. Every recognised action executes
   immediately. (Today's action set is all Level 0, so nothing *forces* the
   issue yet — but the structure to gate anything higher does not exist.)

6. **No observation / verification.** Directly contradicts Part 30
   ("tool executed ≠ task succeeded"). `play_song()` assumes success; spoken
   confirmations are emitted regardless of outcome. There are no verifiers.

7. **No persistence / Repository layer.** All state is in-memory module
   globals. `context.py` itself documents "resets whenever the script
   restarts." No SQLite/Oracle, no `conversations/messages/commands/
   tool_executions/devices/confirmations/preferences` entities, no audit
   history.

8. **No LLM Provider abstraction.** `intent_parser.py` imports `requests` and
   hard-codes the Ollama URL; `claude_client.py` hard-codes the Anthropic URL.
   The Agent Core (such as it is) is directly coupled to both. The target
   requires `Agent Core → LLM Provider interface → {Ollama, cloud}`.

9. **Media-shaped everything.** The intent schema, `ConversationContext.
   last_song`, the entire `player_action` module, and the quick-command table
   all assume the domain is music/video playback. The target is a
   general-purpose computer agent (apps, browser, Windows UIA, games,
   filesystem, system, developer tools) — none of which have any presence in the
   current code.

10. **`handle_command()` mixes five concerns** — intent parsing, action
    dispatch, user-facing phrasing, error handling, and context update — in one
    function. The target separates these across Agent Core, Tool Executor,
    Response Generation, and Context Manager.

11. **Backend fallback logic is inline, not pluggable.** `player_action`
    chooses local vs CDP vs media-keys with `if _playback_mode == ...` inside
    each function. The target wants named adapters selected by a backend
    hierarchy so backends "can evolve independently" (Parts 12.7, 19).

12. **No cancellation / emergency stop for a running task.** The only stop is
    killing the process via the orb window (`os._exit(0)`). Part 27 requires an
    LLM-independent stop that halts an in-flight task without a process kill.

13. **No bounded autonomy.** No max-tool-calls, task-duration, or
    recovery-attempt limits — though there is also no multi-step execution to
    bound yet.

14. **No networking / Android surface whatsoever.** No Gateway server, no
    WebSocket/HTTP, no protocol envelope, no auth, no device registry. Part 13
    is entirely greenfield.

15. **Repository structure.** Flat scripts in the repo root; no `src/jairus/`
    package, no `pyproject.toml`, no `configuration/` module (tunables are
    in-code constants), no `docs/` tree, no tests, and **the project is not
    under git** — so the Phase 0 "known-good baseline / Git checkpoint" the doc
    calls for does not exist yet.

16. **`tts.py` and `assistant_loop.py` both write `AssistantState`.** Minor
    today, but state ownership needs to be explicit once a real State Manager
    exists.

17. **Repo hygiene.** `venv/`, `browser_profile/` (a full Brave profile), and
    `__pycache__/` are all checked into the working tree and will need a
    `.gitignore` before version control is introduced.

---

## 8. Documentation / Code Drift (relevant to an accurate baseline)

Phase 0 in the doc calls for "document current system" and "record known
failures." The following mismatches between `README.md`, in-code comments, and
actual behaviour were found and should be reconciled as part of any baseline:

| Claim | Source | Reality in code |
|---|---|---|
| Wake word is "hey jarvis"; no custom model exists | `README.md`, `assistant_loop.py` header comment | `assistant_loop.py` loads `hey_jairus.onnx`, a custom model that is in the repo. The comment is stale. |
| Ollama model is `qwen2.5:3b` | `README.md` §0 | `intent_parser.py` uses `qwen2.5:7b`. |
| "Conversation mode" — keeps listening for follow-ups without the wake word until ~6 s of silence; tune it in `main.py` | `README.md` ("Conversational behavior", "Tuning") | Not implemented. `run_assistant()` returns to wake-word listening after every command. `main.py` contains no conversation-mode loop. |
| Recording window is "5 seconds" | `README.md` §7 first-run walkthrough | Superseded by `record_until_silence()`; the 5 s figure is from an earlier version. |
| `MODEL_SIZE` guidance mentions dropping to `"base"` under VRAM pressure | `README.md` | Matches code default `"small"` — consistent, noted for completeness. |

None of these are bugs in the running system; they are accuracy gaps in the
baseline documentation.

---

## 9. Present in Target, Absent Today (net-new)

For completeness, the following target components have **no current-code
antecedent at all** and would be built from scratch:

- `domain/` models and events
- Command Gateway, Task Manager, command/task IDs and lifecycle
- Policy Engine, permission levels, confirmation system, audit log
- Tool Registry, Tool Executor, tool schemas, tool verifiers
- Observation / verification subsystem
- Repository layer + database (SQLite/Oracle) + data model
- LLM Provider interface (the two concrete callers exist; the abstraction does not)
- Context Builder / layered context (a flat `ConversationContext` exists)
- Application, Browser (semantic), Windows UIA, Games, Filesystem, System, and
  Developer tool families and their backends
- WebSocket/HTTP Gateway server, JSON protocol envelope, auth, device registry
- Android client (separate project)
- `configuration/` module, `.env` handling, `observability/` (logging/metrics/
  tracing) beyond `print()`
- Test suites (`unit/ integration/ contract/ security/ system/`)
- `src/jairus/` package layout, `pyproject.toml`, `docs/architecture/*`

---

## 10. Current-State vs Target-State: Honest Summary

**What the repository is today:** a single-purpose, single-process,
voice-controlled **media** assistant. It does a competent job of the hard
real-time pieces — wake word (with a custom-trained model), silence-aware
recording, GPU Whisper, a free/local-first LLM path with an optional paid
fallback, three-tier playback routing, and a reactive UI — and it is small
enough (~1,560 LOC) to hold in your head.

**What the architecture wants it to become:** a general-purpose, tool-driven,
policy-gated **computer agent** with observation/verification, persistence,
multi-interface input (voice + Android), and a security model that treats the
LLM as untrusted.

**Where they meet:** the *infrastructure-facing* half of the current code
(`audio_utils`, `transcribe`, `tts`, `media_keys`, `local_player`,
`local_library`, the CDP code inside `player_action`, `orb_ui`, the wakeword
model, and `quick_commands`) maps onto target `infrastructure/` and
`interfaces/` boxes with modest change, and the doc explicitly plans to preserve
it.

**Where they diverge:** the *decision-facing* half — `handle_command()`'s
intent→action router, the `{action,title,artist,songs}` schema, the direct
function-call "tools", the module-global state, and the absence of any Gateway,
Task Manager, Policy Engine, Tool Registry, verification, persistence, or domain
model — is precisely the part the target replaces. There is no command
identity, no task lifecycle, and no security boundary to build on; those are
greenfield.

**Baseline caveat:** the project is not yet under version control and its README
describes at least one feature ("conversation mode") that the current code does
not implement, plus two model-name mismatches. An accurate written baseline and
a git checkpoint do not exist yet.

*(Per the task brief and the architecture doc's own instruction, this document
stops at the snapshot and does not recommend what to migrate first.)*
