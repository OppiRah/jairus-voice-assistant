"""Agent Core — minimal, single-shot tool selection.

JAIRUS_ARCHITECTURE.md Part 14.12 (migration Phase 10), Part 11 (LLM
role — chooses among available tools, "cannot invent tools," "cannot
bypass confirmation"), Part 12 (agent execution model — this phase
implements only RECEIVE -> UNDERSTAND -> PLAN -> VALIDATE -> EXECUTE for
exactly one tool call; OBSERVE/VERIFY/RECOVER are later), Part 16 (tool
registry — "the LLM cannot invent capabilities"; "Tool not found" ->
REJECT), Part 66 (incremental tool decisions — one action at a time, not
a blind multi-step plan), Part 67 (structured LLM output), and Part 68
(the validation pipeline this module follows: parse -> schema validate ->
tool exists? -> policy check -> confirmation if required -> execute).

**THIS IS THE FIRST PHASE WHERE AN LLM MAKES A REAL DECISION.** Every tool
since Phase 5 has been pre-registered data that nothing selected between;
here, an LLM call actually picks which one of a small, explicit set of
tools to run. Treated accordingly:

- ``ALLOWED_TOOLS`` below is a deliberately small, HARDCODED allow-list —
  not derived from the full Tool Registry, and not meant to casually grow.
  It exists to prove the mechanism end-to-end (an unguarded HARMLESS path
  and a guarded DISRUPTIVE path) without exposing the full ~20-tool
  registry to LLM selection on day one.
- The LLM can NEVER select a tool outside this list, even if that tool is
  registered elsewhere (e.g. ``windows.invoke``, ``browser.navigate``) —
  and a hallucinated tool name that doesn't exist anywhere is rejected the
  same way. Both cases return a ``NOT_FOUND`` ``ToolResult`` without ever
  calling ``execute_tool()``.
- This module does not create a ``Command`` or a ``Task`` — it is
  standalone, meant to be tested with raw text goals, not wired into
  ``command_gateway.py`` or ``handle_command()``. That integration is a
  later phase.
- No multi-step planning, retries, or recovery — one goal, one tool call,
  one ``ToolResult``, full stop.

Registration is the caller's responsibility, same as every prior phase:
``run_goal()`` does not call ``register_media_tools()``/
``register_app_tools()`` itself — the registry must already be populated
before a call here can succeed.
"""

from __future__ import annotations

import json
from typing import Any

import requests

from jairus.application.policy import evaluate, request_confirmation
from jairus.domain.tools import FailureCategory, ToolResult
from jairus.tools import execute_tool, get_tool

OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_MODEL_NAME = "qwen2.5:7b"

# Deliberately small and hardcoded — see module docstring. The LLM may
# select ONLY from these five, regardless of what else is registered.
ALLOWED_TOOLS = [
    "media.pause",
    "media.resume",
    "media.skip",
    "apps.launch",
    "apps.close",
]

# A separate, standalone prompt — NOT a modification of intent_parser.py's
# SYSTEM_PROMPT, and not shared code with it. Loosely follows Part 67's
# structured-output shape (type/tool/arguments/message), narrowed to the
# two outcomes this single-shot phase actually needs: "tool_call" (one of
# the listed tools fits) or "no_match" (none genuinely do). Part 67's
# other two types, "ask_user" and "recover", both imply a multi-turn
# planning loop this phase deliberately doesn't build.
SYSTEM_PROMPT_TEMPLATE = """You select AT MOST ONE tool to satisfy a user's goal, from the exact list below. This list is deliberately short — if none of these genuinely satisfy the goal, say so; do not pick the closest-sounding one.

Available tools:
{tool_descriptions}

Return ONLY a JSON object, no other text, no markdown fences, in this exact shape:
{{"type": "tool_call" | "no_match", "tool": "<one of the tool names above, or null>", "arguments": {{}}, "message": "<null, or a short reason if no_match>"}}

Rules:
- "type": "tool_call" only if one of the listed tools genuinely satisfies the goal. "arguments" must match that tool's own input schema shown above.
- "type": "no_match" if nothing listed genuinely fits — e.g. the goal needs a capability that isn't in the list above, or is unrelated to all of them. Put a short reason in "message". Never pick a tool from the list just because it's the closest available option.
- "tool" must be exactly one of the names listed above, or null for "no_match". Never invent a tool name that isn't listed.
- Never include explanations outside the JSON object.
"""


def _build_system_prompt() -> str:
    """Pulls each allowed tool's description/input_schema straight from
    its actual registered ToolDefinition — no duplicated tool-description
    text lives in this prompt."""
    lines = []
    for name in ALLOWED_TOOLS:
        tool = get_tool(name)
        if tool is None:
            # Can happen if the caller hasn't registered every allow-listed
            # tool yet — rather than describe a tool that isn't actually
            # real right now, it's simply left out of what the LLM is told
            # exists (the registry stays the source of truth, per Part 16).
            continue
        lines.append(f"- {tool.name}: {tool.description} (arguments: {tool.input_schema})")
    return SYSTEM_PROMPT_TEMPLATE.format(tool_descriptions="\n".join(lines))


def _call_ollama(goal_text: str) -> dict[str, Any]:
    # Same HTTP pattern intent_parser.py already uses (requests.post to
    # localhost:11434/api/generate) — duplicated deliberately rather than
    # imported, to keep this module decoupled from intent_parser.py.
    full_prompt = f'{_build_system_prompt()}\n\nGoal: "{goal_text}"\nJSON:'
    response = requests.post(
        OLLAMA_URL,
        json={
            "model": OLLAMA_MODEL_NAME,
            "prompt": full_prompt,
            "stream": False,
            "options": {"temperature": 0},
            "keep_alive": "30m",
        },
        timeout=60,
    )
    response.raise_for_status()
    raw_output = response.json().get("response", "").strip()
    raw_output = raw_output.replace("```json", "").replace("```", "").strip()
    return json.loads(raw_output)


def run_goal(goal_text: str) -> ToolResult:
    """Asks the LLM to pick one tool (from ``ALLOWED_TOOLS`` only) for
    ``goal_text``, validates that choice, gates it through the Policy
    Engine, and — if allowed or approved — runs it through the EXISTING
    Tool Executor (Phase 6, unmodified). Returns the resulting
    ``ToolResult``; a "no suitable tool" outcome or a declined
    confirmation are both normal, reportable results here, not raised
    exceptions.

    Follows Part 68's validation pipeline: parse -> schema check -> tool
    exists (in the allow-list AND the registry) -> policy check ->
    confirmation if required -> execute.
    """
    print(f"[agent] goal: '{goal_text}'")

    try:
        decision = _call_ollama(goal_text)
    except (requests.RequestException, ValueError) as exc:
        # ValueError covers json.loads failing on a malformed LLM response —
        # Part 68: invalid output is rejected, not guessed at.
        print(f"[agent] LLM call/parse failed: {exc}")
        return ToolResult(success=False, error=str(exc), failure_category=FailureCategory.BACKEND_UNAVAILABLE)

    if not isinstance(decision, dict):
        return ToolResult(
            success=False,
            error="LLM output was not a JSON object",
            failure_category=FailureCategory.VALIDATION_ERROR,
        )

    decision_type = decision.get("type")
    tool_name = decision.get("tool")
    arguments = decision.get("arguments") or {}
    if not isinstance(arguments, dict):
        return ToolResult(
            success=False,
            error="LLM output's 'arguments' was not a JSON object",
            failure_category=FailureCategory.VALIDATION_ERROR,
        )

    if decision_type != "tool_call" or not tool_name:
        message = decision.get("message") or "no suitable tool for this goal"
        print(f"[agent] no tool selected: {message}")
        return ToolResult(success=False, error=message, failure_category=FailureCategory.NOT_FOUND)

    # Part 16: "the registry says Tool not found -> REJECT, never guess or
    # substitute." Checked against BOTH the hardcoded allow-list and the
    # actual registry — the LLM cannot reach a tool by picking a name
    # outside this phase's allow-list even if it's registered elsewhere,
    # and it cannot reach a hallucinated name that isn't registered at all.
    if tool_name not in ALLOWED_TOOLS:
        print(f"[agent] rejected: '{tool_name}' is not in this phase's allow-list")
        return ToolResult(
            success=False,
            error=f"'{tool_name}' is outside the allowed tool list for this phase",
            failure_category=FailureCategory.NOT_FOUND,
        )

    tool_definition = get_tool(tool_name)
    if tool_definition is None:
        print(f"[agent] rejected: '{tool_name}' is not registered")
        return ToolResult(
            success=False,
            error=f"no tool registered as '{tool_name}'",
            failure_category=FailureCategory.NOT_FOUND,
        )

    policy_decision = evaluate(tool_definition)
    if policy_decision == "confirm":
        approved = request_confirmation(tool_definition, arguments)
        if not approved:
            print(f"[agent] '{tool_name}' declined by user")
            return ToolResult(
                success=False,
                error="user declined confirmation",
                failure_category=FailureCategory.PERMISSION_DENIED,
            )

    print(f"[agent] running '{tool_name}' with {arguments}")
    return execute_tool(tool_name, arguments)
