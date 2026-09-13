"""
orb_widget.py — the visual companion window: a glowing, pulsing orb that
reflects the assistant's current state (idle / listening / thinking /
speaking) and reacts to live audio level, alongside a current-activity
label and a scrollable recent-commands history list. PySide6/Qt port of
orb_ui.py's pygame rendering — same colors, same breathing/pulse math,
same read-only relationship to AssistantState.

Runs on the main thread — Qt owns the window/event loop. The actual voice
assistant logic runs in a background thread and just updates a shared
AssistantState object; this file only ever reads from it. Current
activity and history reflect the most recent real thing the assistant
said/did (the same points that already drive speak()) — not live,
continuously-polled playback state, so they can't go stale/wrong just
because playback was controlled some other way.

Closing the orb window shuts down the whole assistant (simplest v1
behavior, same as before).
"""

import math
import os
import sys
import time

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QMainWindow,
    QVBoxLayout,
    QWidget,
)

EMPTY_HISTORY_TEXT = "Nothing yet — say \"hey jairus\" to get started"

WINDOW_SIZE = 480
FPS = 60
BASE_RADIUS = 70

COLORS = {
    "idle":      (70, 130, 200),   # calm blue
    "listening": (60, 200, 140),   # green
    "thinking":  (170, 90, 220),   # violet
    "speaking":  (250, 170, 60),   # warm gold
}


class OrbWidget(QWidget):
    def __init__(self, state, parent=None):
        super().__init__(parent)
        self._state = state
        self._start_time = time.time()
        self.setFixedSize(WINDOW_SIZE, WINDOW_SIZE)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self.update)
        self._timer.start(int(1000 / FPS))

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        painter.fillRect(self.rect(), QColor(12, 12, 20))  # near-black background so the glow pops

        status, level = self._state.get_snapshot()
        color = COLORS.get(status, COLORS["idle"])
        t = time.time() - self._start_time
        center = (self.width() // 2, self.height() // 2)

        self._draw_orb(painter, center, level, color, t)

    def _draw_orb(self, painter, center, level, color, t):
        # gentle breathing motion, layered on top of live/animated audio level
        breathe = (math.sin(t * 1.6) + 1) / 2  # 0..1
        pulse = BASE_RADIUS * (1.0 + 0.15 * breathe + 0.35 * level)

        # aura: soft, layered, low-alpha rings behind the core orb — additive
        # blending to match pygame's BLEND_RGBA_ADD (overlapping rings brighten)
        painter.setPen(Qt.NoPen)
        painter.setCompositionMode(QPainter.CompositionMode_Plus)
        for i in range(4, 0, -1):
            ring_radius = int(pulse + i * 14 + level * 20)
            if ring_radius <= 0:
                continue
            alpha = max(0, 60 - i * 12 - int(level * 10))
            painter.setBrush(QColor(color[0], color[1], color[2], alpha))
            painter.drawEllipse(
                center[0] - ring_radius, center[1] - ring_radius,
                ring_radius * 2, ring_radius * 2,
            )
        painter.setCompositionMode(QPainter.CompositionMode_SourceOver)

        # core orb
        core_radius = max(1, int(pulse))
        painter.setBrush(QColor(color[0], color[1], color[2], 230))
        painter.drawEllipse(
            center[0] - core_radius, center[1] - core_radius,
            core_radius * 2, core_radius * 2,
        )

        # bright inner highlight for a bit of depth
        highlight_radius = max(4, int(core_radius * 0.35))
        painter.setBrush(QColor(255, 255, 255))
        painter.drawEllipse(
            center[0] - core_radius // 4 - highlight_radius,
            center[1] - core_radius // 4 - highlight_radius,
            highlight_radius * 2, highlight_radius * 2,
        )


class ActivityPanel(QWidget):
    """Current-activity label + scrollable recent-commands history.

    Reflects the most recent real thing the assistant said/did (the same
    points that already call speak()) — polled from AssistantState on a
    timer, same pattern as OrbWidget polling status/level.
    """

    POLL_INTERVAL_MS = 250

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self._state = state
        self._last_activity = None
        self._last_history = None

        layout = QVBoxLayout(self)

        activity_heading = QLabel("Current activity")
        activity_heading.setStyleSheet("color: #8a8fa3; font-size: 11px;")
        layout.addWidget(activity_heading)

        self.activity_label = QLabel("Idle")
        self.activity_label.setWordWrap(True)
        self.activity_label.setStyleSheet("color: #e8eaf0; font-size: 15px;")
        layout.addWidget(self.activity_label)

        history_heading = QLabel("Recent commands")
        history_heading.setStyleSheet("color: #8a8fa3; font-size: 11px; margin-top: 12px;")
        layout.addWidget(history_heading)

        self.history_list = QListWidget()
        self.history_list.setStyleSheet(
            "QListWidget { background-color: #14141f; color: #c8cbdc; "
            "border: 1px solid #262638; font-size: 12px; }"
        )
        layout.addWidget(self.history_list)
        self._render_history([])

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh)
        self._timer.start(self.POLL_INTERVAL_MS)

    def _refresh(self):
        activity, history = self._state.get_activity_snapshot()
        if activity != self._last_activity:
            self.activity_label.setText(activity)
            self._last_activity = activity
        if history != self._last_history:
            self._render_history(history)
            self._last_history = history

    def _render_history(self, history):
        self.history_list.clear()
        if not history:
            self.history_list.addItem(EMPTY_HISTORY_TEXT)
            return
        for entry in history:
            self.history_list.addItem(f"[{entry['timestamp']}] {entry['text']}")
        self.history_list.scrollToBottom()


HEALTH_DISPLAY = {
    # status -> (dot color, label). Honest backend health, not a network
    # connection state -- this process isn't networked to anything.
    "starting": ("#8a8fa3", "Starting…"),
    "ollama_unavailable": ("#e0a33c", "Ollama unavailable"),
    "healthy": ("#4fd18b", "Healthy"),
}


class HealthIndicator(QLabel):
    """Small, unobtrusive backend-health readout: a colored dot paired with
    plain-language text (never color alone) for whether Ollama is reachable
    and the wake-word model/mic stream are up. Polled from AssistantState on
    its own timer, same pattern as the orb and ActivityPanel.
    """

    POLL_INTERVAL_MS = 1000

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self._state = state
        self._last_status = None
        self.setStyleSheet("font-size: 12px; padding: 2px 6px;")
        self._refresh()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh)
        self._timer.start(self.POLL_INTERVAL_MS)

    def _refresh(self):
        status = self._state.get_health_status()
        if status == self._last_status:
            return
        color, text = HEALTH_DISPLAY.get(status, HEALTH_DISPLAY["starting"])
        self.setText(f"<span style='color:{color};'>●</span> {text}")
        self._last_status = status


class OrbWindow(QMainWindow):
    def __init__(self, state):
        super().__init__()
        self.setWindowTitle("Jairus")
        self.setMinimumSize(WINDOW_SIZE + 280, WINDOW_SIZE)

        central = QWidget(self)
        central.setStyleSheet("background-color: #0c0c14;")
        layout = QHBoxLayout(central)
        layout.addWidget(OrbWidget(state, central))
        layout.addWidget(ActivityPanel(state, central))
        self.setCentralWidget(central)

        status_bar = self.statusBar()
        status_bar.setStyleSheet(
            "QStatusBar { background-color: #0c0c14; color: #c8cbdc; "
            "border-top: 1px solid #262638; }"
        )
        status_bar.addPermanentWidget(HealthIndicator(state, self))


def run_orb(state):
    app = QApplication.instance() or QApplication(sys.argv)
    window = OrbWindow(state)
    window.show()
    app.exec()
    os._exit(0)  # background assistant thread is a daemon, so this cleanly ends everything
