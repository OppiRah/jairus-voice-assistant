"""ToolResult — outcome of executing a ToolCall, plus its failure taxonomy."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any


class FailureCategory(str, Enum):
    """Structured reason a tool call or task did not succeed.

    The full set from JAIRUS_ARCHITECTURE.md Part 32. Retry behaviour (Part 33)
    is decided per-category by the Policy Engine / Agent Core, not by this
    model.
    """

    VALIDATION_ERROR = "validation_error"
    PERMISSION_DENIED = "permission_denied"
    CONFIRMATION_REQUIRED = "confirmation_required"
    NOT_FOUND = "not_found"
    TIMEOUT = "timeout"
    EXECUTION_ERROR = "execution_error"
    BACKEND_UNAVAILABLE = "backend_unavailable"
    OBSERVATION_FAILED = "observation_failed"
    VERIFICATION_FAILED = "verification_failed"
    UNKNOWN_ERROR = "unknown_error"
    CANCELLED = "cancelled"
    RECOVERING = "recovering"
    INTERRUPTED = "interrupted"


@dataclass
class ToolResult:
    """Outcome of executing a ToolCall.

    `success` is the Tool Executor's report that the call ran to completion.
    Whether the world actually changed as intended is a separate verification
    step (JAIRUS_ARCHITECTURE.md Part 30: "tool executed != task succeeded").

    Fields
    ------
    success:           True if the call completed without error.
    data:              structured output from the tool, when it produced any.
    error:             human-readable error message on failure.
    failure_category:  classification of the failure, when not successful.
    """

    success: bool
    data: dict[str, Any] | None = None
    error: str | None = None
    failure_category: FailureCategory | None = None
