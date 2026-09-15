"""
theme.py — shared visual theme for the Qt UI (Phase 7, UI polish).

Catalogs and formalizes every color already in use across orb_widget.py
from Phases 1-6, rather than inventing a new palette. Colors that carry
real state/permission meaning -- the health indicator's status colors
(Phase 3) and the Tools page's permission-level colors (Phase 5) -- keep
their EXACT existing hex values. This module only gives each one a shared
name instead of a scattered literal; it never redefines what any of them
mean. Notably, SUCCESS and
WARNING below are literally the same hex values Phases 3/5/6 had already
converged on independently for "good/immediate" and "needs attention/an
extra step" (Healthy == Harmless == "applies immediately"; Ollama
unavailable == Disruptive == "restart required") -- this phase formalizes
that convergence, it didn't invent it.

Neutral/structural colors (backgrounds, borders, text shades used for
chrome rather than state) are consolidated from the small set of near-
duplicate grays that had organically emerged across pages, into one
coherent scale.
"""

from PySide6.QtGui import QFont, QFontDatabase
import qtawesome as qta

# ---- Neutral / structural colors --------------------------------------
# A subtle three-step elevation scale that had already emerged across
# Phases 1-6 (window background < sidebar < input/list fields) -- kept as
# three distinct steps rather than collapsed, since each was already being
# used consistently for its own layer.
BG = "#0c0c14"        # window/page background
SURFACE = "#101018"   # sidebar background
FIELD = "#14141f"     # list/input backgrounds (history lists, text fields)
BORDER = "#262638"    # borders, dividers, and the "Requires confirmation" chip background
SELECTED = "#1c1c2c"  # sidebar selected-row background, row dividers

TEXT_PRIMARY = "#e8eaf0"    # headings, primary labels
TEXT_SECONDARY = "#c8cbdc"  # list items, badges, sidebar text, status bar text
TEXT_MUTED = "#8a8fa3"      # section sub-headings, descriptions, secondary notes
TEXT_DISABLED = "#4a4d5e"   # disabled sidebar items
WHITE = "#ffffff"           # selected sidebar item text

# ---- Semantic status colors --------------------------------------------
# Meanings established in Phases 1-6; values unchanged here, just named
# and centralized so every consumer shares one definition instead of
# repeating the hex literal.
SUCCESS = "#4fd18b"      # Healthy (Phase 3) / Harmless (Phase 5) / "applies immediately" (Phase 6)
WARNING = "#e0a33c"      # Ollama unavailable (Phase 3) / Disruptive (Phase 5) / "restart required" (Phase 6)
DESTRUCTIVE = "#e0803c"  # Destructive permission tier (Phase 5)
ERROR = "#e0524f"        # Dangerous permission tier (Phase 5)

# ---- Spacing scale -------------------------------------------------------
SPACE_XS = 4
SPACE_SM = 8
SPACE_MD = 12
SPACE_LG = 16
SPACE_XL = 24

CARD_RADIUS = 6  # rounded-corner radius for history/recent-commands and Tools cards (Phase 8)

# ---- Icons (Phase 8) -------------------------------------------------------
# Chosen over Qt's own QStyle.standardIcon() after actually testing it on
# this machine: several needed icons (SP_MediaPlay, SP_MediaPause,
# SP_MediaSkipForward, SP_MediaVolume) rendered as BLANK on this platform's
# style, and the ones that did render (folders, a monitor, message-box
# glyphs) came out as colorful, Windows-native bitmaps that can't be
# recolored to match this theme -- reintroducing exactly the visual
# inconsistency Phase 7 worked to eliminate. qtawesome is a small (~2.6MB),
# MIT-licensed, actively-maintained wrapper around the Font Awesome icon
# font: every icon needed here (home/history/tools/cog, music/apps/globe/
# window/gamepad/folder/code, play/pause/forward/volume/sync/question/
# warning) exists in its solid set, renders identically across platforms,
# and can be recolored with theme.TEXT_SECONDARY like any other themed
# element -- verified by rendering the full set before choosing it. No new
# icon asset files are bundled in the repo; qtawesome ships its own font
# resources internally.
ICON_COLOR = TEXT_SECONDARY

NAV_ICONS = {
    "Home": "fa5s.home",
    "History": "fa5s.history",
    "Tools": "fa5s.tools",
    "Settings": "fa5s.cog",
}

CATEGORY_ICONS = {
    "media": "fa5s.music",
    "apps": "fa5s.th-large",
    "browser": "fa5s.globe",
    "windows": "fa5s.window-restore",
    "game": "fa5s.gamepad",
    "filesystem": "fa5s.folder",
    "developer": "fa5s.code",
}

# Maps assistant_loop.py's REAL action type (the same value that already
# drives handle_command()'s if/elif dispatch, captured alongside each
# history entry -- see AssistantState.add_history_entry()) to an icon.
# "unknown" (the parser couldn't determine a real action) and "error" (the
# action raised) are real, honest outcomes captured at their own call
# sites, not guesses.
ACTION_TYPE_ICONS = {
    "play": "fa5s.play",
    "queue": "fa5s.list",
    "pause": "fa5s.pause",
    "resume": "fa5s.play",
    "skip": "fa5s.forward",
    "correct": "fa5s.sync",
    "volume_up": "fa5s.volume-up",
    "volume_down": "fa5s.volume-down",
    "whats_playing": "fa5s.info-circle",
    "unknown": "fa5s.question",
    "error": "fa5s.exclamation-triangle",
}
FALLBACK_ICON = "fa5s.question"  # any action type with no specific icon above


def icon(name: str, color: str = ICON_COLOR):
    """Returns a themed QIcon for a qtawesome glyph name."""
    return qta.icon(name, color=color)


def nav_icon(label: str):
    return icon(NAV_ICONS.get(label, FALLBACK_ICON))


def category_icon(category: str):
    return icon(CATEGORY_ICONS.get(category, FALLBACK_ICON))


def action_icon(action_type: str):
    return icon(ACTION_TYPE_ICONS.get(action_type, FALLBACK_ICON))

# ---- Typography -----------------------------------------------------------
# UI_UX_CONTEXT.md calls for "Inter or similar clean sans-serif." Inter is
# a font file this project doesn't ship or depend on, so rather than adding
# a new font-file dependency, this checks what's actually installed and
# falls back gracefully -- Segoe UI (Windows' own modern system sans-serif)
# reads as "clean sans-serif" just as well and needs nothing extra.
PREFERRED_FONT_FAMILIES = ["Inter", "Segoe UI", "Arial"]

BASE_FONT_SIZE = 13


def resolve_font_family() -> str:
    """Picks the first available font from PREFERRED_FONT_FAMILIES using
    QFontDatabase. Never crashes or silently fails if none of them are
    installed -- falls back to Qt's own platform default font in that case.
    """
    available = set(QFontDatabase.families())
    for name in PREFERRED_FONT_FAMILIES:
        if name in available:
            return name
    return QFont().defaultFamily()


def build_stylesheet(font_family: str) -> str:
    """One global QSS stylesheet, meant to be set once at the QApplication
    level (see orb_widget.run_orb()), covering the chrome shared by every
    page: backgrounds, borders, base text color, and form controls. Page-
    specific semantic labels (headings, muted notes, permission/health
    badges) still set their own color via this module's named constants
    rather than a raw hex literal, since QSS type-selectors can't express
    "this specific label is a section heading" without adding an object
    name to every single label -- but the values they use all come from
    here, so there's exactly one place any of these colors is defined.
    """
    return f"""
        * {{
            font-family: "{font_family}";
        }}
        QWidget {{
            background-color: {BG};
            color: {TEXT_SECONDARY};
            font-size: {BASE_FONT_SIZE}px;
        }}
        QMainWindow {{
            background-color: {BG};
        }}
        QScrollArea {{
            border: none;
            background-color: transparent;
        }}
        QListWidget {{
            background-color: {BG};
            color: {TEXT_SECONDARY};
            border: 1px solid {BORDER};
            outline: 0;
        }}
        QListWidget::item {{
            background-color: {FIELD};
            border: 1px solid {BORDER};
            border-radius: {CARD_RADIUS}px;
            padding: {SPACE_SM}px {SPACE_SM + 2}px;
            margin: 3px 4px;
        }}
        QListWidget#Sidebar {{
            background-color: {SURFACE};
            border: none;
            border-right: 1px solid {BORDER};
            outline: 0;
        }}
        QListWidget#Sidebar::item {{
            background-color: transparent;
            border: none;
            border-radius: 0px;
            margin: 0px;
            padding: {SPACE_SM + 2}px {SPACE_MD + 2}px;
        }}
        QListWidget#Sidebar::item:selected {{
            background-color: {SELECTED};
            color: {WHITE};
        }}
        QListWidget#Sidebar::item:disabled {{
            color: {TEXT_DISABLED};
        }}
        QStatusBar {{
            background-color: {BG};
            color: {TEXT_SECONDARY};
            border-top: 1px solid {BORDER};
        }}
        QPushButton {{
            background-color: {SURFACE};
            color: {TEXT_SECONDARY};
            border: 1px solid {BORDER};
            border-radius: 4px;
            padding: {SPACE_XS + 2}px {SPACE_MD + 2}px;
        }}
        QPushButton:hover {{
            background-color: {SELECTED};
        }}
        QPushButton:pressed {{
            background-color: {BORDER};
        }}
        QLineEdit, QComboBox, QDoubleSpinBox {{
            background-color: {FIELD};
            color: {TEXT_SECONDARY};
            border: 1px solid {BORDER};
            border-radius: 4px;
            padding: {SPACE_XS}px {SPACE_SM}px;
        }}
    """
