"""
theme.py — shared visual theme for the Qt UI (Phase 7, UI polish).

Catalogs and formalizes every color already in use across orb_widget.py
from Phases 1-6, rather than inventing a new palette. Colors that carry
real state/permission meaning -- the orb's per-state colors (Phase 1), the
health indicator's status colors (Phase 3), and the Tools page's
permission-level colors (Phase 5) -- keep their EXACT existing hex values.
This module only gives each one a shared name instead of a scattered
literal; it never redefines what any of them mean. Notably, SUCCESS and
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
WHITE = "#ffffff"           # orb highlight, selected sidebar item text

# ---- Semantic status colors --------------------------------------------
# Meanings established in Phases 1-6; values unchanged here, just named
# and centralized so every consumer shares one definition instead of
# repeating the hex literal.
SUCCESS = "#4fd18b"      # Healthy (Phase 3) / Harmless (Phase 5) / "applies immediately" (Phase 6)
WARNING = "#e0a33c"      # Ollama unavailable (Phase 3) / Disruptive (Phase 5) / "restart required" (Phase 6)
DESTRUCTIVE = "#e0803c"  # Destructive permission tier (Phase 5)
ERROR = "#e0524f"        # Dangerous permission tier (Phase 5)

# ---- Orb per-state colors (Phase 1), unchanged --------------------------
ORB_COLORS = {
    "idle": (70, 130, 200),
    "listening": (60, 200, 140),
    "thinking": (170, 90, 220),
    "speaking": (250, 170, 60),
}

# ---- Spacing scale -------------------------------------------------------
SPACE_XS = 4
SPACE_SM = 8
SPACE_MD = 12
SPACE_LG = 16
SPACE_XL = 24

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
            background-color: {FIELD};
            color: {TEXT_SECONDARY};
            border: 1px solid {BORDER};
        }}
        QListWidget#Sidebar {{
            background-color: {SURFACE};
            border: none;
            border-right: 1px solid {BORDER};
            outline: 0;
        }}
        QListWidget#Sidebar::item {{
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
