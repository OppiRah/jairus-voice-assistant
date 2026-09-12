"""Tool Registry, existing- and new-capability tool definitions, and the
executor that can run them."""

from .app_tools import APP_TOOLS, register_app_tools
from .browser_tools import BROWSER_TOOLS, register_browser_tools
from .developer_tools import DEVELOPER_TOOLS, register_developer_tools
from .executor import execute_tool
from .filesystem_tools import FILESYSTEM_TOOLS, register_filesystem_tools
from .game_tools import GAME_TOOLS, register_game_tools
from .media_tools import MEDIA_TOOLS, register_media_tools
from .registry import get_tool, list_tools, register_tool
from .windows_tools import WINDOWS_TOOLS, register_windows_tools

__all__ = [
    "register_tool",
    "get_tool",
    "list_tools",
    "MEDIA_TOOLS",
    "register_media_tools",
    "APP_TOOLS",
    "register_app_tools",
    "BROWSER_TOOLS",
    "register_browser_tools",
    "WINDOWS_TOOLS",
    "register_windows_tools",
    "GAME_TOOLS",
    "register_game_tools",
    "FILESYSTEM_TOOLS",
    "register_filesystem_tools",
    "DEVELOPER_TOOLS",
    "register_developer_tools",
    "execute_tool",
]
