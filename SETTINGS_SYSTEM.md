# Settings system (UI Phase 6)

Survey of every configuration-like constant across the project, reasoned
individually against one question: is this genuinely sensible for a
non-technical user to edit via a GUI, or is it a deployment-level/advanced
value better left as a code constant for now? Same rigor as the
permission-level reasoning in `FILESYSTEM_TOOLS.md`/`DEVELOPER_TOOLS.md` —
each constant gets its own real argument, nothing defaulted to "include
everything" or "include nothing" for convenience.

## Included — real, editable settings

**`assistant_loop.py`'s `DETECTION_THRESHOLD` -> `wake_word_sensitivity`.**
A single float compared against a live score every loop iteration. Its
effect (fewer false wake-ups vs. needing to speak more clearly) is
immediately perceivable by anyone using the assistant, with no technical
knowledge required to understand what "sensitivity" means. Also happens to
be nearly free to make genuinely live: the comparison already runs inside
a tight loop, so reading the current value fresh each iteration (instead
of once at startup) costs nothing and needs no restart. **Included, applies
immediately.**

**`transcribe.py`'s `MODEL_SIZE` -> `whisper_model_size`.** A real,
bounded choice (a handful of standard Whisper sizes) with a genuine,
understandable tradeoff: bigger is more accurate but slower and heavier on
VRAM — the exact tradeoff the original hardcoded comment already spelled
out for a human maintainer to reason about by hand. A dropdown of the
standard size names removes any chance of an invalid value. Unlike wake-
word sensitivity, this can't apply live: `_get_model()` caches the loaded
model for the process's lifetime, and reloading a different-sized model
mid-run is a multi-second, VRAM-churning operation, not a free comparison.
**Included, restart required.**

**`local_library.py`'s `MUSIC_LIBRARY_DIR` -> `music_library_dir`.** A
personal folder path — exactly the kind of "where are your files" setting
ordinary desktop apps expose, and the most concretely useful of the
bunch (it's the only way to ever turn local-file playback on at all
without hand-editing a `.py` file). Can't apply live: the file index is
only ever built once per process (`_index is None` check), so a changed
path needs a fresh index build, which only happens at the next `import`
today. **Included, restart required.**

**`local_library.py`'s `MATCH_THRESHOLD` -> `music_match_threshold`.** A
closer call than the other three — its effect (does a spoken request match
a local file closely enough to use it instead of falling back to YouTube)
is more of an internal tuning knob than something a typical user thinks
about day to day, and it's genuinely optional/advanced. Included anyway
because it's real, understandable once explained ("how closely a request
must match a filename"), and — unlike the folder path — completely free to
make live: `find_local_match()` already re-reads it at call time with no
cached state depending on it. Labeled "(advanced)" in the UI rather than
presented as equally central as the other four. **Included (advanced),
applies immediately.**

**`src/jairus/configuration/settings.py`'s `ANDROID_PAIRING_CODE` ->
`android_pairing_code`.** The strongest case of all five, not just a
"nice to have": it's a real security credential, currently shipped at a
publicly-known default (`"changeme-pairing-code"`, visible in this very
repo) with **no existing prompt or mechanism anywhere** that ever
encourages a user to change it. Anyone on the same LAN who knows this
project exists and reads its source knows the default pairing code.
Exposing it in Settings is the single highest-value change in this phase.
It can't apply "live" in the way wake-word sensitivity can — not because
of caching, but because `run_gateway.py` is a **separate OS process** from
the Qt app entirely (Phase 13's own docstring: "not yet integrated into
main.py"). A freshly *started* gateway process reads the config file
itself, so the honest framing isn't "restart Jairus," it's "takes effect
the next time the Android Gateway is started" — and the Settings page says
exactly that, not a generic restart note that would be misleading about
which process actually needs restarting. **Included, takes effect on the
Gateway's next start (a different process, not Jairus's main window).**

## Left as code-only (or config-file-only, no GUI field)

**`assistant_loop.py`'s `WAKE_WORD_MODEL`.** Deliberately **not** made
editable, diverging from the initial instinct that offered it as a
candidate. Reasoning: there is currently exactly one real, working value
(`hey_jairus.onnx`) — openWakeWord ships no other model actually trained
for this assistant's wake phrase, and there's no file-browser or
validation to keep a user from typing a filename that doesn't exist,
silently breaking wake-word detection with no clear error message pointing
back to Settings. A free-text field with a single valid answer and a
high, confusing failure mode isn't "genuinely sensible for a non-technical
user to edit" — it's a footgun with no present upside. Building real
validation (scanning openWakeWord's model directory for valid options)
would be inventing a new capability beyond "surface existing config,"
which is out of this phase's scope. Stays a plain hardcoded constant, not
even routed through the config file.

**`src/jairus/configuration/settings.py`'s `GATEWAY_HOST` /
`GATEWAY_PORT`.** Confirmed the initial instinct here through actual
investigation, not just deferred to it: these are LAN bind-address/port
values. `0.0.0.0:8765` is a sensible universal default that essentially
never needs changing for this project's actual use case (one phone
pairing with one PC on the same network), and a bad value here (a port
already in use, a malformed address) breaks the *entire* Gateway with a
failure mode a non-technical user has no way to diagnose from inside a
simple settings field — there's no port-conflict detection or address
validation built. Real, but deployment-level. **Routed through the same
config file/loader as everything else** (so a technical user can still
hand-edit `jairus_config.json` if they genuinely need to), **but given no
field in the Settings UI** — the one place `GATEWAY_HOST`/`GATEWAY_PORT`
and `ANDROID_PAIRING_CODE` already lived together (Phase 13's
`settings.py`) now treats all three consistently as config-file-backed,
rather than splitting that one small module into "some constants read a
file, some don't."

## Architecture: one config file, one loader

`src/jairus/configuration/settings.py` (Phase 13's existing module, the
package explicitly reserved for this since Phase 1) was extended rather
than creating a second config system. It now reads/writes
`jairus_config.json` at the repo root (gitignored — it can hold a personal
pairing code and a personal folder path). `get(key)` / `save(updates)` /
`all_settings()` are the primary API; `GATEWAY_HOST` / `GATEWAY_PORT` /
`ANDROID_PAIRING_CODE` remain available as plain module attributes for
Phase 13's existing consumers (`run_gateway.py`, `gateway_server.py`),
resolved dynamically via a module `__getattr__` so they can never go stale
within a running process.

Every default in `settings.py`'s `_DEFAULTS` dict is identical to what was
hardcoded before this phase, so a machine with no `jairus_config.json`
present behaves byte-for-byte the same as before Phase 6 existed —
verified directly (see the Phase 6 report's fresh-run test).

`assistant_loop.py`, `transcribe.py`, and `local_library.py` — all
top-level scripts outside the `jairus` package — import
`jairus.configuration.settings` via the same `sys.path` bootstrap
`assistant_loop.py` already used for other `jairus.*` imports (Phase 3),
extended to the two files that didn't have it yet.
