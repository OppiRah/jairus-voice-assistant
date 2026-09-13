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
from pathlib import Path

from PySide6.QtCore import QSize, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPainter
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QDoubleSpinBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QPushButton,
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

from jairus.configuration import settings
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

import theme
from assistant_state import AssistantStatus

SIDEBAR_WIDTH = 150

EMPTY_HISTORY_TEXT = "Nothing yet — say \"hey jairus\" to get started"


def _render_history_items(list_widget, history):
    """Shared by ActivityPanel's inline list and HistoryPage's focused
    list -- both render the exact same AssistantState history data, just
    at different sizes, so the rendering rule lives in one place. Each
    entry's icon comes from its real action_type (assistant_loop.py's
    actual dispatch value, captured at each handle_command() call site --
    see AssistantState.add_history_entry()), never guessed from the text.
    """
    list_widget.clear()
    if not history:
        list_widget.addItem(EMPTY_HISTORY_TEXT)
        return
    for entry in history:
        item = QListWidgetItem(f"[{entry['timestamp']}] {entry['text']}")
        item.setIcon(theme.action_icon(entry.get("action_type", "unknown")))
        list_widget.addItem(item)
    list_widget.scrollToBottom()


WINDOW_SIZE = 480
FPS = 60
BASE_RADIUS = 70


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

        painter.fillRect(self.rect(), QColor(theme.BG))  # near-black background so the glow pops

        status, level = self._state.get_snapshot()
        color = theme.ORB_COLORS.get(status, theme.ORB_COLORS[AssistantStatus.IDLE])
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
        painter.setBrush(QColor(theme.WHITE))
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
        activity_heading.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 11px;")
        layout.addWidget(activity_heading)

        self.activity_label = QLabel("Idle")
        self.activity_label.setWordWrap(True)
        self.activity_label.setStyleSheet(f"color: {theme.TEXT_PRIMARY}; font-size: 15px;")
        layout.addWidget(self.activity_label)

        history_heading = QLabel("Recent commands")
        history_heading.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 11px; margin-top: {theme.SPACE_MD}px;")
        layout.addWidget(history_heading)

        self.history_list = QListWidget()
        self.history_list.setStyleSheet("QListWidget { font-size: 12px; }")  # smaller than the app default; colors/border come from the global theme stylesheet
        self.history_list.setIconSize(QSize(14, 14))
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
        heading.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 13px;")
        layout.addWidget(heading)

        # Colors/border/font-size all come from the global theme stylesheet
        # (matches the app's base font size, unlike ActivityPanel's smaller inline list).
        self.history_list = QListWidget()
        self.history_list.setIconSize(QSize(16, 16))
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
    # UI_UX_CONTEXT.md -- never color alone. Colors are theme.SUCCESS/
    # WARNING/DESTRUCTIVE/ERROR -- unchanged values from Phase 5, just
    # sourced from the shared theme module now.
    PermissionLevel.HARMLESS: (theme.SUCCESS, "Harmless"),
    PermissionLevel.DISRUPTIVE: (theme.WARNING, "Disruptive"),
    PermissionLevel.DESTRUCTIVE: (theme.DESTRUCTIVE, "Destructive"),
    PermissionLevel.DANGEROUS: (theme.ERROR, "Dangerous"),
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
    """One registered tool, styled as its own card: name, permission
    badge, an explicit "Requires confirmation" tag when true, and its
    full description -- all always visible. Deliberately has no click
    handler: the complete description is already shown inline, so
    there's nothing left for a click to reveal, and no interaction
    surface that could later be mistaken for -- or repurposed into -- a
    way to run the tool.
    """

    def __init__(self, tool, parent=None):
        super().__init__(parent)
        # QSS background/border only paint on a plain QWidget with this
        # attribute set (Qt doesn't style-paint custom QWidget backgrounds
        # by default).
        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setStyleSheet(
            f"ToolRow {{ background-color: {theme.FIELD}; border: 1px solid {theme.BORDER}; "
            f"border-radius: {theme.CARD_RADIUS}px; }}"
        )
        layout = QVBoxLayout(self)
        layout.setContentsMargins(theme.SPACE_SM + 2, theme.SPACE_SM, theme.SPACE_SM + 2, theme.SPACE_SM)
        layout.setSpacing(theme.SPACE_XS)

        top_row = QHBoxLayout()
        name_label = QLabel(tool.name)
        name_label.setStyleSheet(f"color: {theme.TEXT_PRIMARY}; font-size: 13px; font-weight: 600;")
        top_row.addWidget(name_label)

        color, text = PERMISSION_DISPLAY.get(tool.permission_level, PERMISSION_DISPLAY[PermissionLevel.HARMLESS])
        badge = QLabel(f"<span style='color:{color};'>●</span> {text}")
        badge.setStyleSheet(f"font-size: 11px; color: {theme.TEXT_SECONDARY};")
        top_row.addWidget(badge)

        if tool.requires_confirmation:
            confirm_tag = QLabel("Requires confirmation")
            confirm_tag.setStyleSheet(
                f"color: {theme.TEXT_SECONDARY}; background-color: {theme.BORDER}; font-size: 10px; "
                f"padding: 1px {theme.SPACE_SM}px; border-radius: 3px;"
            )
            top_row.addWidget(confirm_tag)

        top_row.addStretch()
        layout.addLayout(top_row)

        desc_label = QLabel(tool.description)
        desc_label.setWordWrap(True)
        desc_label.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 12px;")
        layout.addWidget(desc_label)


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
        heading.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 13px;")
        outer.addWidget(heading)

        # Border/background come from the global theme stylesheet's QScrollArea rule.
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)

        content = QWidget()
        content_layout = QVBoxLayout(content)
        content_layout.setSpacing(theme.SPACE_SM)

        tools = list_tools()
        if not tools:
            empty = QLabel("No tools are registered right now.")
            empty.setStyleSheet(f"color: {theme.TEXT_MUTED}; font-size: 13px;")
            content_layout.addWidget(empty)
        else:
            by_category = {}
            for tool in tools:
                category = tool.name.split(".", 1)[0]
                by_category.setdefault(category, []).append(tool)

            for category in CATEGORY_ORDER:
                if category not in by_category:
                    continue
                content_layout.addLayout(self._category_heading(category))
                for tool in sorted(by_category[category], key=lambda t: t.name):
                    content_layout.addWidget(ToolRow(tool))

        content_layout.addStretch()
        scroll.setWidget(content)
        outer.addWidget(scroll)

    def _category_heading(self, category):
        row = QHBoxLayout()
        row.setSpacing(theme.SPACE_XS + 2)
        icon_label = QLabel()
        icon_label.setPixmap(theme.category_icon(category).pixmap(QSize(16, 16)))
        row.addWidget(icon_label)
        text_label = QLabel(CATEGORY_LABELS.get(category, category.title()))
        text_label.setStyleSheet(
            f"color: {theme.TEXT_PRIMARY}; font-size: 14px; font-weight: 600; "
            f"margin-top: {theme.SPACE_MD + 2}px;"
        )
        row.addWidget(text_label)
        row.addStretch()
        return row


WHISPER_MODEL_SIZES = ["tiny", "base", "small", "medium", "large-v2", "large-v3"]


class SettingsPage(QWidget):
    """Real, config-file-backed settings for the vetted list of genuinely
    user-facing values -- see SETTINGS_SYSTEM.md for the full reasoning on
    which project-wide constants made the cut (and which didn't). Every
    field here actually changes real behavior when saved via
    jairus.configuration.settings; each field honestly states whether that
    happens immediately or needs a restart, per UI_UX_CONTEXT.md's "truth
    over illusion" -- nothing here claims an instant effect that isn't real.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        outer = QVBoxLayout(self)
        outer.setContentsMargins(theme.SPACE_LG, theme.SPACE_LG, theme.SPACE_LG, theme.SPACE_LG)
        outer.setSpacing(theme.SPACE_XS)

        heading = QLabel("Settings")
        heading.setStyleSheet(f"color: {theme.TEXT_PRIMARY}; font-size: 16px; font-weight: 600;")
        outer.addWidget(heading)

        current = settings.all_settings()

        outer.addWidget(self._section_label("Wake-word sensitivity"))
        self.sensitivity_spin = QDoubleSpinBox()
        self.sensitivity_spin.setRange(0.05, 1.0)
        self.sensitivity_spin.setSingleStep(0.05)
        self.sensitivity_spin.setValue(float(current["wake_word_sensitivity"]))
        outer.addWidget(self.sensitivity_spin)
        outer.addWidget(self._note(
            "Higher = fewer false triggers, but you may need to say \"hey jairus\" more "
            "clearly. Applies immediately -- no restart needed.",
            live=True,
        ))

        outer.addWidget(self._section_label("Whisper model size"))
        self.model_size_combo = QComboBox()
        self.model_size_combo.addItems(WHISPER_MODEL_SIZES)
        idx = self.model_size_combo.findText(str(current["whisper_model_size"]))
        self.model_size_combo.setCurrentIndex(idx if idx >= 0 else 0)
        outer.addWidget(self.model_size_combo)
        outer.addWidget(self._note(
            "Larger = more accurate transcription, slower, more VRAM. "
            "Restart Jairus to apply.",
            live=False,
        ))

        outer.addWidget(self._section_label("Music library folder"))
        folder_row = QHBoxLayout()
        self.library_edit = QLineEdit(str(current["music_library_dir"] or ""))
        self.library_edit.setPlaceholderText("Leave empty to disable local library lookup")
        folder_row.addWidget(self.library_edit)
        browse_button = QPushButton("Browse…")
        browse_button.clicked.connect(self._browse_folder)
        folder_row.addWidget(browse_button)
        outer.addLayout(folder_row)
        outer.addWidget(self._note(
            "Local files here play instead of falling back to YouTube. "
            "Restart Jairus to apply.",
            live=False,
        ))

        outer.addWidget(self._section_label("Music match threshold (advanced)"))
        self.match_spin = QDoubleSpinBox()
        self.match_spin.setRange(0.0, 1.0)
        self.match_spin.setSingleStep(0.05)
        self.match_spin.setValue(float(current["music_match_threshold"]))
        outer.addWidget(self.match_spin)
        outer.addWidget(self._note(
            "How closely a spoken request must match a local filename before it's used "
            "instead of YouTube. Applies immediately -- no restart needed.",
            live=True,
        ))

        outer.addWidget(self._section_label("Android pairing code"))
        self.pairing_edit = QLineEdit(str(current["android_pairing_code"]))
        outer.addWidget(self.pairing_edit)
        outer.addWidget(self._note(
            "Shared secret an Android device must send to control Jairus over the LAN "
            "-- change this from the default. The Android Gateway (run_gateway.py) runs "
            "as its own separate process, not part of this window, so this takes effect "
            "the next time that process is started, not by restarting Jairus itself.",
            live=False,
        ))

        outer.addStretch()

        save_row = QHBoxLayout()
        self.save_button = QPushButton("Save")
        self.save_button.clicked.connect(self._save)
        save_row.addWidget(self.save_button)
        self.status_label = QLabel("")
        self.status_label.setStyleSheet(f"color: {theme.SUCCESS}; font-size: 12px;")
        save_row.addWidget(self.status_label)
        save_row.addStretch()
        outer.addLayout(save_row)

    def _section_label(self, text):
        label = QLabel(text)
        label.setStyleSheet(
            f"color: {theme.TEXT_PRIMARY}; font-size: 13px; font-weight: 600; "
            f"margin-top: {theme.SPACE_MD}px;"
        )
        return label

    def _note(self, text, live: bool):
        label = QLabel(text)
        label.setWordWrap(True)
        color = theme.SUCCESS if live else theme.WARNING
        label.setStyleSheet(f"color: {color}; font-size: 11px;")
        return label

    def _browse_folder(self):
        start_dir = self.library_edit.text().strip() or str(Path.home())
        folder = QFileDialog.getExistingDirectory(self, "Choose music library folder", start_dir)
        if folder:
            self.library_edit.setText(folder)

    def _save(self):
        settings.save({
            "wake_word_sensitivity": self.sensitivity_spin.value(),
            "whisper_model_size": self.model_size_combo.currentText(),
            "music_library_dir": self.library_edit.text().strip() or None,
            "music_match_threshold": self.match_spin.value(),
            "android_pairing_code": self.pairing_edit.text().strip(),
        })
        self.status_label.setText("Saved.")


NAV_ITEMS = [
    # (label, enabled, tooltip-when-disabled)
    ("Home", True, None),
    ("History", True, None),
    ("Tools", True, None),
    ("Settings", True, None),
]


class Sidebar(QListWidget):
    """Persistent left nav. All four items are real, clickable destinations
    as of Phase 6; NAV_ITEMS still supports disabling a future item with a
    "coming soon" tooltip (per UI_UX_CONTEXT.md's "truth over illusion") --
    Qt skips disabled items for both mouse and keyboard selection, so
    clicking/arrowing onto one is a no-op, not an error.
    """

    ICON_SIZE = 16

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedWidth(SIDEBAR_WIDTH)
        self.setIconSize(QSize(self.ICON_SIZE, self.ICON_SIZE))
        # Colors/spacing come from the global theme stylesheet's
        # QListWidget#Sidebar rules (see theme.build_stylesheet()).
        self.setObjectName("Sidebar")
        for label, enabled, tooltip in NAV_ITEMS:
            item = QListWidgetItem(theme.nav_icon(label), label)
            if not enabled:
                item.setFlags(item.flags() & ~Qt.ItemIsEnabled)
                if tooltip:
                    item.setToolTip(tooltip)
            self.addItem(item)
        self.setCurrentRow(0)


HEALTH_DISPLAY = {
    # status -> (dot color, label). Honest backend health, not a network
    # connection state -- this process isn't networked to anything. Colors
    # unchanged from Phase 3, now sourced from the shared theme module.
    "starting": (theme.TEXT_MUTED, "Starting…"),
    "ollama_unavailable": (theme.WARNING, "Ollama unavailable"),
    "healthy": (theme.SUCCESS, "Healthy"),
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
        self.setStyleSheet(f"font-size: 12px; padding: {theme.SPACE_XS}px {theme.SPACE_SM}px;")
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

        # Background comes from the global theme stylesheet's QWidget rule.
        central = QWidget(self)
        layout = QHBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        sidebar = Sidebar(central)
        self.stack = QStackedWidget(central)
        self.stack.addWidget(HomePage(state, self.stack))  # row 0
        self.stack.addWidget(HistoryPage(state, self.stack))  # row 1
        self.stack.addWidget(ToolsPage(self.stack))  # row 2
        self.stack.addWidget(SettingsPage(self.stack))  # row 3
        sidebar.currentRowChanged.connect(self._on_nav_changed)

        layout.addWidget(sidebar)
        layout.addWidget(self.stack)
        self.setCentralWidget(central)

        # Colors/border come from the global theme stylesheet's QStatusBar rule.
        status_bar = self.statusBar()
        status_bar.addPermanentWidget(HealthIndicator(state, self))

    def _on_nav_changed(self, row):
        # Home (0), History (1), Tools (2), Settings (3) are all real,
        # enabled stack pages now (Phase 6).
        if 0 <= row < self.stack.count():
            self.stack.setCurrentIndex(row)


def run_orb(state):
    app = QApplication.instance() or QApplication(sys.argv)

    # Phase 7 (UI polish): one theme applied once at the QApplication level,
    # rather than each page/widget picking its own font and repeating color
    # literals. resolve_font_family() falls back gracefully if the
    # preferred font isn't installed -- never crashes or silently fails.
    font_family = theme.resolve_font_family()
    app.setFont(QFont(font_family, theme.BASE_FONT_SIZE))
    app.setStyleSheet(theme.build_stylesheet(font_family))

    window = OrbWindow(state)
    window.show()
    app.exec()
    os._exit(0)  # background assistant thread is a daemon, so this cleanly ends everything
