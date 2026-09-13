"""
orb_widget.py — the visual companion window: a glowing, pulsing orb that
reflects the assistant's current state (idle / listening / thinking /
speaking) and reacts to live audio level. PySide6/Qt port of orb_ui.py's
pygame rendering — same colors, same breathing/pulse math, same read-only
relationship to AssistantState.

Runs on the main thread — Qt owns the window/event loop. The actual voice
assistant logic runs in a background thread and just updates a shared
AssistantState object; this file only ever reads from it.

Closing the orb window shuts down the whole assistant (simplest v1
behavior, same as before).
"""

import math
import os
import sys
import time

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QApplication, QMainWindow, QWidget

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


class OrbWindow(QMainWindow):
    def __init__(self, state):
        super().__init__()
        self.setWindowTitle("Jairus")
        self.setFixedSize(WINDOW_SIZE, WINDOW_SIZE)
        self.setCentralWidget(OrbWidget(state, self))


def run_orb(state):
    app = QApplication.instance() or QApplication(sys.argv)
    window = OrbWindow(state)
    window.show()
    app.exec()
    os._exit(0)  # background assistant thread is a daemon, so this cleanly ends everything
