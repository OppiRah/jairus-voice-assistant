# Jairus UI/UX Context

*Persistent reference for all UI/UX work on Jairus. Read this before any UI
change, on either the Windows or Android side.*

## Purpose & current state

The 18-phase architectural migration (`JAIRUS_ARCHITECTURE.md`,
`PHASE_RETROSPECTIVE.md`) is complete. **UI/UX is now a separate development
stage built on top of that architecture — do not create "Phase 19" or treat
UI work as a continuation of the phase sequence.**

The original Aria voice system remains fully functional throughout. The
project also contains a modular command/task architecture, Agent Core,
policy/permissions, tool registry/executor, and Windows/browser/app/game/
filesystem/developer capabilities, an Android gateway/client, and reliability
hardening — but **some of this is implemented and tested without being the
final live decision path yet**. UI must represent actual, currently-exposed
system state — never an assumed future capability. When in doubt, inspect the
real repository; it is the source of truth, not this document or any
architecture doc.

## Product identity

**Jairus — Personal AI Computer Agent.** A local-first personal AI agent
runtime and computer-automation platform that understands natural-language
goals and safely operates a Windows computer through registered tools, with
multiple interfaces (Windows voice, Android remote client).

It should feel like a personal computer assistant — not a chatbot, a generic
dashboard, or a collection of scripts.

## Scope boundary (read this before touching anything backend)

Do not restart or extend the 18-phase migration merely because UI work
exposes a limitation. If a genuine backend requirement surfaces:
1. Document it.
2. Verify it's actually required (not a UI workaround that would suffice).
3. Make the smallest necessary backend change.
4. Preserve the existing architecture — don't redesign around it.
5. Test it.
6. Return to UI work.

Also do not, without genuine justification: introduce new frameworks,
add microservices, add state-management libraries the platform doesn't
already need, add a design-system package merely for styling, replace
working components without reason, or add cloud dependencies solely for UI.

## Repository rules before any UI change

1. Inspect the current implementation.
2. Inspect the relevant command/task/protocol/state models.
3. Inspect existing components and styling.
4. Reuse sound existing patterns rather than inventing new ones.
5. Do not rewrite working backend systems unnecessarily.

## UI architecture boundary

UI is a presentation/client layer only.

```
Good:  UI → Gateway/application interface → Agent runtime → tools
Bad:   UI → Playwright
Bad:   Android → Windows process manipulation
```

UI must never bypass: **Agent Core, Policy Engine, Tool Registry, Tool
Executor, authorization, confirmation, or the command/task lifecycle.** Use
the intended application or network interfaces only. The backend is
authoritative for task state, permissions, confirmations, execution,
verification, errors, cancellation, and system state — **clients display
that state, they never declare success themselves.**

## UI surfaces

### Windows Desktop
The previous reactive orb has been removed; Jairus's visual identity is being
redesigned from zero (see `archive/orb_v1/` for that prior R&D — treat it as
evidence and experience, not a design constraint). The surrounding shell
(sidebar with Home/History/Tools/Settings, a current-activity card, and
recent commands) is unaffected and stays as-is; only the centered visual slot
itself is undecided. Do not assume the next visual will be an orb, a sphere,
or share any element of the previous design.

States to represent (collapse where it would create noise, don't expose
every internal state):
```
IDLE → LISTENING → UNDERSTANDING → PLANNING → WAITING_CONFIRMATION →
EXECUTING → OBSERVING → RECOVERING → COMPLETED / FAILED / CANCELLED → OFFLINE
```

### Android
Kotlin + Jetpack Compose. A thin client — text command input, conversation/
history, task status, progress, confirmations, cancellation, connection
status, results. **Must not** contain Windows automation logic. Voice input
on Android is a future capability, not this stage.

### Shared UX
Windows and Android express the same underlying command/task model. Clients
display authoritative backend state; they do not independently classify
danger or declare success.

## Core UX principles

1. Clarity over decoration.
2. Truth over illusion — never show success before backend verification.
3. User control — confirm/deny/cancel/retry/reconnect should always be
   understandable actions, not guesses.
4. Minimal cognitive load.
5. Consistency across surfaces.
6. Accessibility (see below).

## Command/task UX & confirmation

Commands represent requests; tasks represent execution. The UI may hide
those technical terms in copy, but must preserve the distinction internally.
A multi-step task shows meaningful milestones, not raw implementation
events (see Progress below).

Confirmation must name the actual action:
```
Good: Delete `Downloads/OldMods`?
Bad:  Are you sure?
```
The client never independently classifies risk — the backend's permission
level is authoritative.

## Error handling

Support distinct, meaningful states for at least: connection failure,
timeout, permission denial, confirmation required, application not found,
backend unavailable, execution failure, verification failure, cancellation,
unknown result.

Translate technical failures into plain language:
```
timeout          → "Chrome took too long to respond."
app missing      → "I couldn't find that application."
connection lost  → "Jairus is offline."
verification     → explain the result couldn't be confirmed, don't guess
```
Raw stack traces, tool IDs, and internal UUIDs belong behind an optional
diagnostics view, never in the primary UI.

## Progress

Never invent fake percentages. Use real backend milestones only:
```
Opening Chrome… → Searching… → Checking result… → Done.
```

## Connection UX

Distinguish: Connected, Connecting, Reconnecting, Disconnected,
Authentication required, Connection error. Never silently drop a command.
A task acknowledged before a disconnect must remain recoverable after
reconnection per the existing protocol — the client shouldn't assume a
result just because it reconnected (test this explicitly, see Testing).

## Cancellation

Expose cancellation only for tasks that are actually cancelable right now.
```
Cancel pressed → cancellation requested → backend processes → cancelled
```
Never claim cancellation completed before the backend actually confirms it.

## User-facing language

Prefer:
- "Opening Chrome…" / "Searching YouTube…"
- "Waiting for your confirmation."
- "Skyrim is already running."
- "I couldn't find that application."
- "Task cancelled."

Never expose in normal use: `ToolDefinition` internals, tool IDs, agent
iteration counts, raw WebSocket payloads, raw exceptions, internal UUIDs.

## Visual direction

Target: personal, intelligent, technical, calm, modern, trustworthy.

Avoid design-for-design's-sake: excessive neon/cyberpunk, heavy
glassmorphism, cluttered dashboards, unnecessary gradients, animation
without semantic purpose, "AI magic" effects that obscure real state.
Animation should communicate state, not decorate.

Framing that matters: **"a serious personal computer assistant that happens
to look futuristic," not "a cyberpunk AI dashboard."** Glow/color as accent,
not as the whole design language.

## Component principles

Use reusable components for repeated concepts; avoid abstraction for its own
sake. Likely concepts: command bubble, task status, progress event,
confirmation card, error card, connection status, activity item, assistant
status, empty state. Follow whatever naming convention the codebase already
establishes once the first components exist — don't invent a second one.

## Responsive & accessibility

Readable text, sufficient contrast, adequate touch targets, keyboard
accessibility, system font-scaling support, graceful handling of long text/
results, small-screen behavior, reduced-motion support, orientation changes
where relevant. **Never use color alone to communicate state** — pair it
with an icon, label, or shape.

## Development order

1. UX specification — flows, screens, states, interactions, information
   hierarchy.
2. Visual direction — typography, spacing, components, colors, icons,
   animation language.
3. Windows UI.
4. Android UI.
5. Shared interaction language, reconciled across both.
6. Real usability testing.

## AI workflow

ChatGPT: research, UX/architecture decisions, critique, design
specifications, implementation prompts. Claude Code: repository inspection,
implementation, testing, reporting.

```
USER → ChatGPT (precise implementation prompt) → Claude Code →
USER review → ChatGPT independent audit → next prompt/fix
```

Claude Code should not silently make major UX assumptions — surface them
for a decision instead.

## Claude Code task pattern (per UI task)

1. Inspect before modifying.
2. State a concise implementation plan.
3. Implement the smallest coherent change.
4. Run relevant tests/build/lint.
5. Perform real-device/manual verification where appropriate.
6. Review the diff.
7. Report: files changed, behavior, tests run, manual verification
   performed, limitations, follow-ups.

## Testing — cover more than the happy path

At minimum, exercise: a normal command, a multi-step command, a
confirmation flow, a cancellation, a backend failure, a timeout, an Android
disconnect, a reconnect, a task that completed *before* reconnection, a task
still running *after* reconnection, invalid/empty input, and a very long
result. Use the real backend/protocol wherever practical — matches this
project's established preference for real testing over mocks.

## Visual QA (for any significant visual change)

Inspect the actual running UI, not just a successful compile. Check:
spacing, hierarchy, wrapping, alignment, button placement, touch targets,
animation, error states, long content, small-screen behavior, dark/light
behavior if supported. **Compilation alone is not UI validation.**

## Git discipline

Same conventions already established for this project: focused changes,
tests, diff review, meaningful commit messages, no automatic push — wait
for explicit approval before pushing.

## Definition of done

A UI feature is done only when it:
- Implements the intended UX.
- Reflects real backend state (never fabricated).
- Handles the relevant failure/confirmation/cancellation/disconnection
  states.
- Preserves the security/policy boundary above.
- Works on the actual target platform/device (not just "should work").
- Has been manually inspected where practical.
- Passes appropriate tests/build/lint.
- Updates documentation when architecturally meaningful.
- Contains only the intended Git changes.

## Guiding principle

**Jairus should look intelligent because it behaves intelligently and
communicates clearly — not because the UI is covered in AI-themed effects.**
