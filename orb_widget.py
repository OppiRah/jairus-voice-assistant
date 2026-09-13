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
    QListWidgetItem,
    QMainWindow,
    QScrollArea,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

# --- Jairus migration: make src/ importable, same pattern assistant_loop.py
# already uses, so ToolsPage can read the Tool Registry Phases 5/7/8/9/15/16/17
# populate. This is a read-only display concern, not a dispatch/execution one. ---
_SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.tools import (
    list_tools,
    register_app_tools,
    register_browser_tools,
    register_developer_tools,
    register_filesystem_tools,
    register_game_tools,
    register_media_tools,
    register_windows_tools,
)

SIDEBAR_WIDTH = 150

EMPTY_HISTORY_TEXT = "Nothing yet — say \"hey jairus\" to get started"


def _render_history_items(list_widget, history):
    """Shared by ActivityPanel's inline list and HistoryPage's focused
    list -- both render the exact same AssistantState history data, just
    at different sizes, so the rendering rule lives in one place.
    """
    list_widget.clear()
    if not history:
        list_widget.addItem(EMPTY_HISTORY_TEXT)
        return
    for entry in history:
        list_widget.addItem(f"[{entry['timestamp']}] {entry['text']}")
    list_widget.scrollToBottom()


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
        _render_history_items(self.history_list, [])

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh)
        self._timer.start(self.POLL_INTERVAL_MS)

    def _refresh(self):
        activity, history = self._state.get_activity_snapshot()
        if activity != self._last_activity:
            self.activity_label.setText(activity)
            self._last_activity = activity
        if history != self._last_history:
            _render_history_items(self.history_list, history)
            self._last_history = history


class HomePage(QWidget):
    """The orb + current activity + recent commands -- exactly what the
    window showed before the sidebar existed, just living in a page now
    instead of being the window's only content.
    """

    def __init__(self, state, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.addWidget(OrbWidget(state, self))
        layout.addWidget(ActivityPanel(state, self))


class HistoryPage(QWidget):
    """A focused, full-size view of the same bounded history AssistantState
    already tracks (Phase 2's deque) -- not a different or richer dataset,
    just more room than ActivityPanel's inline list gives it.
    """

    POLL_INTERVAL_MS = 250

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self._state = state
        self._last_history = None

        layout = QVBoxLayout(self)

        heading = QLabel("Recent commands")
        heading.setStyleSheet("color: #8a8fa3; font-size: 13px;")
        layout.addWidget(heading)

        self.history_list = QListWidget()
        self.history_list.setStyleSheet(
            "QListWidget { background-color: #14141f; color: #c8cbdc; "
            "border: 1px solid #262638; font-size: 13px; }"
        )
        layout.addWidget(self.history_list)
        _render_history_items(self.history_list, [])

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh)
        self._timer.start(self.POLL_INTERVAL_MS)

    def _refresh(self):
        _, history = self._state.get_activity_snapshot()
        if history != self._last_history:
            _render_history_items(self.history_list, history)
            self._last_history = history


CATEGORY_ORDER = ["media", "apps", "browser", "windows", "game", "filesystem", "developer"]

CATEGORY_LABELS = {
    "media": "Media",
    "apps": "Apps",
    "browser": "Browser",
    "windows": "Windows",
    "game": "Games",
    "filesystem": "Filesystem",
    "developer": "Developer",
}

PERMISSION_DISPLAY = {
    # level -> (dot color, label). Pairs color with text per
    # UI_UX_CONTEXT.md -- never color alone.
    PermissionLevel.HARMLESS: ("#4fd18b", "Harmless"),
    PermissionLevel.DISRUPTIVE: ("#e0a33c", "Disruptive"),
    PermissionLevel.DESTRUCTIVE: ("#e0803c", "Destructive"),
    PermissionLevel.DANGEROUS: ("#e0524f", "Dangerous"),
}


def _register_all_tools_for_display():
    """Registration-for-DISPLAY only -- calling these just adds descriptive
    ToolDefinition data to the Tool Registry's in-memory dict
    (jairus/tools/registry.py); it never invokes any tool's underlying
    function or wires anything into command dispatch. Safe to call
    unconditionally and repeatedly: register_tool() is a plain
    dict-assignment keyed by name, so re-registering is a no-op in effect.

    Only register_media_tools() is ever called on the live app's startup
    path today (assistant_loop.py's shadow-mode setup); the other six --
    Phases 7/8/9/15/16/17's register_app_tools/register_browser_tools/
    register_windows_tools/register_game_tools/register_filesystem_tools/
    register_developer_tools -- are otherwise only called from each
    phase's own tests. Without this call, this page would only be able to
    show media.* tools.
    """
    register_media_tools()
    register_app_tools()
    register_browser_tools()
    register_windows_tools()
    register_game_tools()
    register_filesystem_tools()
    register_developer_tools()


class ToolRow(QWidget):
    """One registered tool: name, permission badge, an explicit
    "Requires confirmation" tag when true, and its full description --
    all always visible. Deliberately has no click handler: the complete
    description is already shown inline, so there's nothing left for a
    click to reveal, and no interaction surface that could later be
    mistaken for -- or repurposed into -- a way to run the tool.
    """

    def __init__(self, tool, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(4)

        top_row = QHBoxLayout()
        name_label = QLabel(tool.name)
        name_label.setStyleSheet("color: #e8eaf0; font-size: 13px; font-weight: 600;")
        top_row.addWidget(name_label)

        color, text = PERMISSION_DISPLAY.get(tool.permission_level, PERMISSION_DISPLAY[PermissionLevel.HARMLESS])
        badge = QLabel(f"<span style='color:{color};'>●</span> {text}")
        badge.setStyleSheet("font-size: 11px; color: #c8cbdc;")
        top_row.addWidget(badge)

        if tool.requires_confirmation:
            confirm_tag = QLabel("Requires confirmation")
            confirm_tag.setStyleSheet(
                "color: #c8cbdc; background-color: #262638; font-size: 10px; "
                "padding: 1px 6px; border-radius: 3px;"
            )
            top_row.addWidget(confirm_tag)

        top_row.addStretch()
        layout.addLayout(top_row)

        desc_label = QLabel(tool.description)
        desc_label.setWordWrap(True)
        desc_label.setStyleSheet("color: #9296a8; font-size: 12px;")
        layout.addWidget(desc_label)

        self.setStyleSheet("border-bottom: 1px solid #1c1c2c;")


class ToolsPage(QWidget):
    """Read-only catalog of every tool ever registered across this
    project's capability phases (media/apps/browser/windows/games/
    filesystem/developer) -- an inspection view, not a way to run
    anything. No button or click handler anywhere on this page calls
    execute_tool() or any tool's underlying function.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        _register_all_tools_for_display()

        outer = QVBoxLayout(self)
        heading = QLabel("Registered tools")
        heading.setStyleSheet("color: #8a8fa3; font-size: 13px;")
        outer.addWidget(heading)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("QScrollArea { border: none; background-color: transparent; }")

        content = QWidget()
        content_layout = QVBoxLayout(content)

        tools = list_tools()
        if not tools:
            empty = QLabel("No tools are registered right now.")
            empty.setStyleSheet("color: #9296a8; font-size: 13px;")
            content_layout.addWidget(empty)
        else:
            by_category = {}
            for tool in tools:
                category = tool.name.split(".", 1)[0]
                by_category.setdefault(category, []).append(tool)

            for category in CATEGORY_ORDER:
                if category not in by_category:
                    continue
                category_heading = QLabel(CATEGORY_LABELS.get(category, category.title()))
                category_heading.setStyleSheet(
                    "color: #e8eaf0; font-size: 14px; font-weight: 600; margin-top: 14px;"
                )
                content_layout.addWidget(category_heading)
                for tool in sorted(by_category[category], key=lambda t: t.name):
                    content_layout.addWidget(ToolRow(tool))

        content_layout.addStretch()
        scroll.setWidget(content)
        outer.addWidget(scroll)


NAV_ITEMS = [
    # (label, enabled, tooltip-when-disabled)
    ("Home", True, None),
    ("History", True, None),
    ("Tools", True, None),
    ("Settings", False, "Coming soon — no configurable settings yet"),
]


class Sidebar(QListWidget):
    """Persistent left nav. Home/History are real, clickable destinations.
    Tools/Settings are shown for correct visual shape but disabled --
    no real content exists behind them yet, so per UI_UX_CONTEXT.md's
    "truth over illusion" they're not clickable rather than leading to a
    fake page. Qt skips disabled items for both mouse and keyboard
    selection, so clicking/arrowing onto them is a no-op, not an error.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedWidth(SIDEBAR_WIDTH)
        self.setStyleSheet(
            "QListWidget { background-color: #101018; color: #c8cbdc; "
            "border: none; border-right: 1px solid #262638; font-size: 13px; "
            "outline: 0; }"
            "QListWidget::item { padding: 10px 14px; }"
            "QListWidget::item:selected { background-color: #1c1c2c; color: #ffffff; }"
            "QListWidget::item:disabled { color: #4a4d5e; }"
        )
        for label, enabled, tooltip in NAV_ITEMS:
            item = QListWidgetItem(label)
            if not enabled:
                item.setFlags(item.flags() & ~Qt.ItemIsEnabled)
                if tooltip:
                    item.setToolTip(tooltip)
            self.addItem(item)
        self.setCurrentRow(0)


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
        self.setMinimumSize(WINDOW_SIZE + 280 + SIDEBAR_WIDTH, WINDOW_SIZE)

        central = QWidget(self)
        central.setStyleSheet("background-color: #0c0c14;")
        layout = QHBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        sidebar = Sidebar(central)
        self.stack = QStackedWidget(central)
        self.stack.addWidget(HomePage(state, self.stack))  # row 0
        self.stack.addWidget(HistoryPage(state, self.stack))  # row 1
        self.stack.addWidget(ToolsPage(self.stack))  # row 2
        sidebar.currentRowChanged.connect(self._on_nav_changed)

        layout.addWidget(sidebar)
        layout.addWidget(self.stack)
        self.setCentralWidget(central)

        status_bar = self.statusBar()
        status_bar.setStyleSheet(
            "QStatusBar { background-color: #0c0c14; color: #c8cbdc; "
            "border-top: 1px solid #262638; }"
        )
        status_bar.addPermanentWidget(HealthIndicator(state, self))

    def _on_nav_changed(self, row):
        # Home (0), History (1), Tools (2) are real stack pages; Settings
        # is disabled in the sidebar so this never fires for that row.
        if 0 <= row < self.stack.count():
            self.stack.setCurrentIndex(row)


def run_orb(state):
    app = QApplication.instance() or QApplication(sys.argv)
    window = OrbWindow(state)
    window.show()
    app.exec()
    os._exit(0)  # background assistant thread is a daemon, so this cleanly ends everything
