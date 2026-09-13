# AssistantState status vocabulary

The backend-side prerequisite named in `ORB_RENDERER_INVESTIGATION.md`
sections 1 and 6 — expanding `AssistantState`'s status vocabulary from the
original 4 values toward `UI_UX_CONTEXT.md`'s target model, done as its
own step, independent of any Godot/rendering integration work. Same
rigor as the permission-level reasoning in `FILESYSTEM_TOOLS.md`/
`DEVELOPER_TOOLS.md`: every state is reasoned through individually
against whether a real trigger point exists in the live code path today
— `handle_command()` and `run_assistant()` in `assistant_loop.py` — not
the shadow-only Agent Core (Phase 11) or the not-yet-wired Policy Engine
(Phase 10).

## The two questions investigated first

### Where does SPEAKING fit? (not in the originally-requested 8)

`tts.py`'s `speak()` sets status to `"speaking"` for the entire duration
of TTS audio playback, then reverts to `"idle"` when done — real,
currently-working, user-visible behavior (the orb pulses gold) that
predates this phase and is called from many places: every
`handle_command()` branch's announcement, and the wake-word "Yes?"
greeting in `run_assistant()`.

It does not cleanly fit under any of the requested 8:

- It fires for pure announcements with no action at all (`"Yes?"`,
  `"Didn't catch that"`, `"Couldn't come up with a playlist for that"`) —
  these aren't EXECUTING anything.
- It fires both *before* an action (the "play"/"queue" branches announce
  first, then act) and *after* one (pause/resume/skip/correct/volume
  announce after acting) — it isn't consistently a sub-phase of any
  single other state.
- It represents a distinct, physical, observable fact (audio is coming
  out of the speakers right now) that is orthogonal to *what* the
  assistant is doing conceptually.

**Decision: SPEAKING stays its own value**, alongside the requested 8,
not folded into EXECUTING or dropped. Dropping it would silently regress
real, working, currently-shipped behavior for no benefit; folding it into
EXECUTING would misrepresent moments where nothing is actually being
executed (e.g. "Yes?"). `tts.py` needed zero changes to keep working:
`AssistantStatus` is a `StrEnum`, so `tts.py`'s existing
`state.set_status("speaking")` (a plain string) is byte-for-byte
identical to `state.set_status(AssistantStatus.SPEAKING)` for every
purpose (equality, dict-key lookup) — verified directly, not assumed.

### Where does OFFLINE fit, given Phase 3's health system already exists?

`AssistantState.get_health_status()` (Phase 3) already tracks whether the
wake-word model is loaded and the mic stream is active
(`_model_loaded`/`_mic_active`), returning `"starting"` when either isn't
true yet. Building OFFLINE as a *second*, independently-triggered value
in the status vocabulary — something `assistant_loop.py` would need new
`set_status(OFFLINE)` calls for — would be exactly the "second,
disconnected way of saying the same thing" this investigation was told
to avoid.

**Decision: OFFLINE is derived, not triggered.** `get_snapshot()` now
checks `_mic_active` directly: if the mic stream isn't active, the
real-time loop genuinely isn't running (still starting up, or the
assistant thread crashed/exited via its `finally` block resetting
`mic_active` to `False`) — OFFLINE is a more honest description of that
than whatever `_status` happens to still hold from before the loop
stopped. `assistant_loop.py` needed **zero new lines** for this; it falls
out entirely from a signal Phase 3 already maintains. Verified directly:
setting mic active, setting status to `"speaking"`, then setting mic
inactive again correctly flips the observed status to `OFFLINE` with no
new trigger code involved.

## Every other state, reasoned individually

| State | Real trigger today? | Where |
|---|---|---|
| IDLE | Yes (pre-existing) | Baseline state throughout `run_assistant()` |
| LISTENING | Yes (pre-existing) | Wake-word detected, recording the command |
| THINKING | Yes (pre-existing) | Transcribing audio, extracting intent |
| SPEAKING | Yes (pre-existing) | `tts.py`'s `speak()`, unmodified |
| **EXECUTING** | **Yes, newly wired** | Immediately before each real action-performing call in `handle_command()` |
| **COMPLETED** | **Yes, newly wired** | End of a successful `handle_command()` run, before returning `True` |
| **ERROR** | **Yes, newly wired** | `handle_command()`'s existing `except` block, before returning `False` |
| WAITING_CONFIRMATION | **No** — kept in the vocabulary only | No real confirmation flow exists in the live path (confirmed: zero references to any confirmation concept anywhere in `command_gateway.py`/`task_manager.py`/the voice interface — the Policy Engine's `requires_confirmation` is inert `ToolDefinition` metadata, Phase 5, never read outside tests) |
| OFFLINE | **Yes, derived** | `get_snapshot()`, from `_mic_active` — see above |

### EXECUTING — which branches got it, which didn't

Added immediately before the real action-performing call in every branch
that actually mutates something: `play_song`, `start_queue`,
`pause_music`, `resume_music`, `skip_music`, `correct_song`,
`adjust_volume` (up and down). **Not** added for `whats_playing`
(`get_now_playing()` is a read, not an action with a real-world effect —
THINKING already correctly covers "the assistant is looking something
up") or for the queue-with-no-songs / unrecognized-command branches
(nothing is executed in either).

One honest quirk worth naming, not fixing: because the existing code
announces *before* acting for "play"/"queue" but *after* acting for
pause/resume/skip/correct/volume, the visible sequence differs slightly
by branch — "play" goes THINKING → SPEAKING → *(a brief flash back to
IDLE, since `speak()` always reverts to idle on its own)* → EXECUTING,
while "pause" goes THINKING → EXECUTING → SPEAKING. This is the honest
reflection of `handle_command()`'s existing call order; reordering those
calls to make the sequence look cleaner was out of scope (a decision-
logic change, not a mechanical addition) and was not done.

### COMPLETED / ERROR — the timed-reset question

Both are set at a single point covering every branch uniformly (after
the whole `try` succeeds; in the existing `except` block), rather than
duplicated per branch. Investigated what "immediately transitioning back
toward IDLE" should mean in practice: `run_assistant()` already calls
`state.set_status(IDLE)` unconditionally right after `handle_command()`
returns, regardless of success or failure — so without any change,
COMPLETED/ERROR would be overwritten within the same call-stack unwind,
on the order of microseconds, never actually visible to a human. A new
`TERMINAL_STATE_DISPLAY_SECONDS = 0.6` constant + `time.sleep(...)` after
setting each one makes the state genuinely observable before the
existing reset takes over. This is a deliberate, small, real behavior
change (every command now takes ~0.6s longer before the assistant is
ready for the next wake word) — a real, if minor, tradeoff between
visual legibility and responsiveness, not something to gloss over. 0.6s
was chosen as long enough to register clearly against the orb's
60fps-smooth animation, short enough not to meaningfully hurt a personal
assistant's responsiveness.

### WAITING_CONFIRMATION's color — deliberately absent

`theme.ORB_COLORS` has no entry for `AssistantStatus.WAITING_CONFIRMATION`.
This is intentional, not an oversight: the existing
`ORB_COLORS.get(status, ORB_COLORS[AssistantStatus.IDLE])` fallback
already handles an unmapped status safely (falls back to idle's blue),
and inventing a color for a state that cannot currently be observed
would be speculative work with nothing real to validate it against. When
a real confirmation flow exists, this is a one-line addition.

## New orb colors chosen (theme.py)

EXECUTING/COMPLETED/ERROR/OFFLINE needed colors distinct from all four
existing ones *and* from each other, since they can all appear on the
same orb. None reuse `theme.SUCCESS`/`WARNING` even though those names
sound related — `theme.SUCCESS` (`#4fd18b`) is close enough to
`ORB_COLORS[LISTENING]` (`(60, 200, 140)`) that reusing it for COMPLETED
risked visually blending two different orb states together, which
matters here in a way it didn't for Phase 7's chrome colors (those never
appear side by side on the orb itself):

- EXECUTING: a new teal/cyan `(60, 190, 210)` — distinct from idle's blue
  and listening's green.
- COMPLETED: a new pale mint-white `(210, 250, 225)` — a bright "flash of
  completion," clearly distinct from listening's more saturated green.
- ERROR: reuses `theme.ERROR`'s exact RGB, `(224, 82, 79)` — deliberately
  the *same* red used for the Dangerous permission tier elsewhere in the
  app, so the whole app agrees on what "red" means.
- OFFLINE: reuses `theme.TEXT_DISABLED`'s exact RGB, `(74, 77, 94)` — the
  same dim gray already used for "de-emphasized/inactive" elsewhere.
