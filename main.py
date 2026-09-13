"""
main.py — entry point. Starts the orb UI on the main thread and the voice
assistant logic on a background thread, sharing state between them.

Run:  python main.py
Stop: close the orb window (or Ctrl+C in the terminal)
"""

import threading

from assistant_state import AssistantState
from assistant_loop import run_assistant
from orb_widget import run_orb


def main():
    state = AssistantState()

    assistant_thread = threading.Thread(target=run_assistant, args=(state,), daemon=True)
    assistant_thread.start()

    run_orb(state)  # blocks on the main thread until the window is closed


if __name__ == "__main__":
    main()
