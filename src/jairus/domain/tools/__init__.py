"""Tool domain models."""

from .tool_call import ToolCall
from .tool_definition import ToolDefinition
from .tool_result import FailureCategory, ToolResult

__all__ = ["ToolCall", "ToolDefinition", "ToolResult", "FailureCategory"]
