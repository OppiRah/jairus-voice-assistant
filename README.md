# Always-Listening Voice Music Controller

Say a wake word, then a command like *"play Blinding Lights by The Weeknd on yt music"*,
and it opens a browser and plays it. Runs fully local except the actual song search results.

Built for: Windows laptop, 16GB RAM, RTX 3060 6GB VRAM (adjust model sizes if yours differs).

---

## 0. Prerequisites

- **Python 3.10 or 3.11** installed (3.12+ can have wheel issues with some audio libs)
- **Ollama** already installed with `qwen2.5:3b` pulled (you've got this from the file organizer project)
- **NVIDIA drivers + CUDA** working (you already have this for Ollama, so you're set)
- A working microphone

Check Ollama is running:
```powershell
ollama list
```
You should see `qwen2.5:3b` in the list. If not: `ollama pull qwen2.5:3b`

---

## 1. Set up the project folder

Unzip/copy this folder wherever you keep projects, e.g. `C:\Users\<you>\voice_music_control`

Open PowerShell in that folder.

## 2. Create a virtual environment

```powershell
python -m venv venv
.\venv\Scripts\activate
```

You should see `(venv)` in your prompt now.

## 3. Install Python dependencies

```powershell
pip install -r requirements.txt
```

## 4. Install Playwright's browser (dependency)

```powershell
python -m playwright install chromium
```

(Using `python -m` instead of the bare `playwright` command avoids issues if your venv's
`Scripts` folder isn't on PATH — this way it always resolves correctly. Playwright needs
this installed even though we'll actually be controlling your real Brave browser, not the
bundled Chromium — it's a dependency of the automation engine itself.)

## 5. Install PyTorch with CUDA (needed for faster-whisper on GPU)

```powershell
pip install torch --index-url https://download.pytorch.org/whl/cu124
```

(Use `cu124` even if `nvidia-smi` shows a newer CUDA version like 12.x/13.x — it's forward
compatible. If you're on an older CUDA driver, or `cu124` doesn't work, check
https://pytorch.org/get-started/locally/ for the right command for your setup.

**Note:** if `python --version` shows **3.13**, stick with `cu124` or newer — PyTorch's
`cu121` wheels were never built for Python 3.13, which is why `cu121` fails with
"No matching distribution found for torch".)

## 6. Launch Brave with remote debugging enabled

The script attaches to your **already-open** Brave and opens a new tab in it, instead of
launching a separate browser window. For that to work, Brave has to be started with a
debugging port open. One-time setup:

1. Close **all** Brave windows completely
2. Right-click your Brave shortcut (desktop or taskbar) → **Properties**
3. In the **Target** field, add ` --remote-debugging-port=9222` to the end, e.g.:
   ```
   "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe" --remote-debugging-port=9222
   ```
4. Click OK, then always launch Brave from that shortcut going forward

Open Brave from that shortcut now and leave it running before starting the script.

## 7. First run

```powershell
python main.py
```

First run will download the openwakeword pretrained models (~few MB) and the
faster-whisper "small" model (~500MB) — this only happens once.

You'll see:
```
[ready] listening for wake word: 'hey jarvis'
```

Say **"hey jarvis"**, wait for `[wake] detected!`, then say your command within the
5 second recording window, e.g.:

> "play Blinding Lights by The Weeknd on yt music"

It'll transcribe, parse the intent, open a **new tab in your existing Brave window**,
search, and click the first result to start playing it automatically.

**If it says "Couldn't connect to Brave"** — Brave either isn't running, or wasn't started
with the `--remote-debugging-port=9222` flag from step 6. Close Brave, relaunch it from the
shortcut you edited, and try again.

---

## New: a visual companion (the orb)

Running `python main.py` now opens a small window with a glowing, pulsing orb
instead of just a terminal. It reflects what the assistant is doing:

| Color | Status |
|---|---|
| Blue | Idle — listening for the wake word, subtly reactive to room sound |
| Green | Listening — recording your command, pulses with your actual voice |
| Violet | Thinking — transcribing / figuring out what you meant |
| Gold | Speaking — pulses with a synced (simulated) animation while it talks |

**Closing the orb window shuts down the whole assistant** — that's the "off switch"
for now, no separate Ctrl+C needed (though Ctrl+C in the terminal still works too).

The terminal window still shows all the same `[transcript]` / `[intent]` / `[player]`
logs as before — keep it open alongside the orb if you want to see what's happening
under the hood.

## New: what you can say now

**Music control**
- **Mood/vibe requests** — "play something chill", "play upbeat workout music" —
  the LLM turns that into a good YouTube search phrase instead of needing an exact title
- **Playlist mode** — "queue up a workout playlist" — the LLM generates 5-8 real songs
  fitting the request and plays them back to back; "skip" advances through the queue
- **Volume control** — "turn it up" / "turn it down" / "lower the volume"
- **"What's playing?"** — reads back the current track/video title

**Conversational behavior**
- **Multi-turn correction** — after it plays something, say "no not that one" / "wrong song"
  and it switches to the next search result (keeps up to 5 alternates per search)
- **Context awareness** — "play that again" or "play it" resolves to whatever it last played,
  without you repeating the title
- **Conversation mode** — after your first command, it keeps listening for follow-ups
  without needing "hey jarvis" again, until ~6 seconds of silence
- **Silence-detection recording** — no more fixed 5-second window; it stops recording as
  soon as you stop talking

**Backends**
- **Local music library** — if you set `MUSIC_LIBRARY_DIR` in `local_library.py`, it checks
  your own files first (fuzzy-matched by filename) before searching YouTube. Playback uses
  `pygame`, fully offline, independent of the browser
- **System media key fallback** — if nothing is actively tracked (no browser tab, no local
  track), pause/resume/skip/volume fall back to Windows' system media keys, which control
  whatever app currently holds the audio session

## Setting up Claude as a smart fallback (optional)

By default this whole project runs on Ollama alone — free, local, no setup beyond
what you've already done. Adding Claude is entirely optional and, if you skip it,
nothing changes or breaks — `intent_parser.py` just keeps using Ollama.

**What Claude gets used for, exactly (this is the whole policy — no hidden calls):**
1. **Ollama failure fallback** — if Ollama times out, isn't running, or returns
   something unparseable, Claude is tried as a smarter backup before giving up
2. **Playlist quality upgrade (opt-in, off by default)** — flip `ESCALATE_QUEUE_TO_CLAUDE`
   to `True` at the top of `intent_parser.py` if you want "queue up a workout playlist"
   style requests to get Claude's (generally more accurate) song picks instead of
   Ollama's. This is the only case where Claude gets called on a healthy, working system.

Everything else — every single song/show "play" request, every pause/skip/volume
command — stays on Ollama or the free fast-path, untouched.

**Getting an API key:**
1. Go to `console.anthropic.com` and sign up
2. Verify your phone number (SMS code)
3. New accounts typically get a small one-time trial credit — check the console
   dashboard for a banner about claiming it
4. Go to **Settings → API Keys → Create Key**, copy it immediately (starts with `sk-ant-`,
   only shown once)

This is a **separate account/billing system from Claude Pro** (the claude.ai subscription)
— having Pro does not give you API credit. The API is pay-per-token with no ongoing free
tier once the trial credit runs out.

**Setting your key as a permanent environment variable (Windows):**

Don't paste your key directly into any `.py` file — if you ever share this project or
push it somewhere, that leaks your key. Instead:

1. Press the Windows key, search "Environment Variables," open
   "Edit environment variables for your account"
2. Under "User variables," click **New**
3. Variable name: `ANTHROPIC_API_KEY`
4. Variable value: your key (the `sk-ant-...` string)
5. OK your way out, then **close and reopen PowerShell** (env var changes don't
   apply to already-open terminals)

Verify it worked:
```powershell
echo $env:ANTHROPIC_API_KEY
```
Should print your key back. If it's blank, the terminal was opened before you set it —
close it and open a fresh one.

**Cost expectations:** using `claude-haiku-4-5-20251001` (the cheapest current model,
what this project uses), each fallback/upgrade call is roughly $0.0005–0.001 — a
fraction of a cent. Even if Ollama broke completely and every single request fell back
to Claude, you'd be looking at well under a dollar for weeks of normal use. Pricing is
per-token and can change — check `console.anthropic.com`'s billing page for current rates.



Open `local_library.py` and set:
```python
MUSIC_LIBRARY_DIR = r"C:\Users\miscr\Music"
```
(or wherever your MP3s/FLACs live). Leave it as `None` to keep YouTube-only behavior.

It indexes the folder recursively on first use and fuzzy-matches your spoken request
against filenames — so a file named `The Weeknd - Blinding Lights.mp3` will match
"play Blinding Lights by The Weeknd" well. Bad or missing tags/filenames = worse matches;
if it's not finding a file you know you have, check `MATCH_THRESHOLD` in the same file
(lower it slightly if matches are being missed).

## Training a custom wake word (optional, bigger undertaking)

Swapping "hey jarvis" for something custom (like your own name for it) isn't a quick code
change — it requires actually training a small classifier on synthetic voice samples plus
background noise augmentation. openWakeWord provides the tooling and a ready-to-run
notebook for this:

https://github.com/dscripka/openWakeWord

Follow their "training custom models" notebook (works well on Google Colab's free GPU tier
if you don't want to tie up your own). Once you have a trained `.onnx` or `.tflite` file,
just point to it in `main.py`:
```python
WAKE_WORD_MODEL = "my_wake_word.onnx"
```
The code already handles both the bundled name format and a custom file path — no other
changes needed once you drop the trained model in.

## Tuning / known rough edges

- **Wake word not triggering / too sensitive** — adjust `DETECTION_THRESHOLD` in `main.py`
  (lower = more sensitive, more false positives; higher = you need to say it louder/clearer)
- **Recording cuts you off too early / never stops** — adjust `SILENCE_THRESHOLD` in
  `audio_utils.py`. It's a volume (RMS) cutoff on int16 samples — raise it if background
  noise is triggering "speech detected," lower it if it's cutting off quiet speech. Also
  tune `silence_duration` (how long you need to pause before it stops recording)
- **Conversation mode exits too fast / lingers too long** — adjust the `max_duration` and
  `silence_duration` passed to `record_until_silence(...)` in the conversation-mode loop
  inside `main.py`
- **Background music drowning out your voice** — worth testing early; if it's an issue, consider
  having the wake word listener temporarily lower system volume when it triggers, before recording
- **VRAM pressure** — Ollama (qwen2.5:7b) + Whisper "small" both loaded can get tight on 6GB.
  If you see OOM errors, drop `MODEL_SIZE` in `transcribe.py` to `"base"`
- **Site UI changes break the click selector** — `player_action.py` has the CSS selector for
  "first search result" on YouTube. If clicking stops working, the site probably changed its
  layout — open devtools and update `FIRST_RESULT_SELECTOR`
- **Correction runs out of alternatives** — it only tracks the top 5 results per search
  (`MAX_RESULTS_TO_TRACK` in `player_action.py`); after that it'll say "that was the last
  option I found" — just start a fresh "play" request instead
- **Correction doesn't work for local files or playlist mode** — it's YouTube-search-specific
  for now; local library matches are assumed to already be a good match
- **Media key fallback controls the wrong app** — if you have multiple things capable of
  playing audio open at once (e.g. Spotify desktop app AND a YouTube tab), Windows' media
  keys go to whichever one currently "owns" the system media session — same ambiguity as
  pressing a physical media key on your keyboard would have
- **"What's playing?" while nothing's playing** — it'll just say "nothing's playing right now"
  rather than guessing
- **Wondering if Claude got called** — check the terminal for `[intent] parsed via Ollama (free)`
  vs `[intent] parsed via Claude (...)` — every single request logs which one handled it,
  so you can always see exactly when (if ever) anything cost money
- **Claude escalation says "unavailable/failed"** — either `ANTHROPIC_API_KEY` isn't set
  (expected if you haven't set it up — everything still works via Ollama), or something's
  wrong with the key/billing on the console side
- **Orb window is laggy or the assistant feels slower with it open** — pygame's window
  rendering is lightweight (60fps of simple circles), so this shouldn't happen, but if it
  does, lower `FPS` in `orb_ui.py`
- **Orb colors/size feel off** — tweak `COLORS` and `BASE_RADIUS` at the top of `orb_ui.py`
- **Closing the orb window ends everything, including if you didn't mean to** — that's the
  intended v1 behavior for simplicity; if you want the assistant to keep running headless
  without the window, run `assistant_loop.py`'s `run_assistant()` directly from your own
  script instead of going through `main.py`

## Next upgrades (if you want to keep building this)

- Swap `requests` calls to Ollama for streaming, so intent parsing feels more responsive
- Sound effect on wake instead of/alongside "Yes?" for a snappier feel
- Smarter local-library matching (e.g. using ID3 tags instead of just filenames)
- Real KDE Connect integration if/when a reliable Windows CLI hook becomes available

