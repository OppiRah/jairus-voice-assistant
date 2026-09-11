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

**Phase 11 (Part 14.13) adds two parameters to ``run_goal()``, both
opt-in, neither changing a single existing call's behavior:**

- ``allowed_tools`` — overrides the module-level ``ALLOWED_TOOLS`` default
  for that one call. Phase 11's shadow mode (`assistant_loop.py`) passes
  its own, separate, media-only allow-list; every existing caller that
  omits this argument keeps getting Phase 10's original 5-tool list,
  unchanged.
- ``dry_run`` — Phase 11's shadow mode: still makes a real LLM call and a
  real policy evaluation, but STRUCTURALLY guarantees neither
  ``request_confirmation()`` (which blocks on a terminal ``input()``) nor
  ``execute_tool()`` is ever reached. A live, unattended voice session
  must never freeze waiting for a keypress that will never come, and must
  never have shadow evaluation actually affect what the user hears — see
  the ``if dry_run:`` branch in ``run_goal()`` for where that guarantee
  actually lives in the code, not merely in this comment.
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


def _build_system_prompt(allowed_tools: list[str]) -> str:
    """Pulls each allowed tool's description/input_schema straight from
    its actual registered ToolDefinition — no duplicated tool-description
    text lives in this prompt."""
    lines = []
    for name in allowed_tools:
        tool = get_tool(name)
        if tool is None:
            # Can happen if the caller hasn't registered every allow-listed
            # tool yet — rather than describe a tool that isn't actually
            # real right now, it's simply left out of what the LLM is told
            # exists (the registry stays the source of truth, per Part 16).
            continue
        lines.append(f"- {tool.name}: {tool.description} (arguments: {tool.input_schema})")
    return SYSTEM_PROMPT_TEMPLATE.format(tool_descriptions="\n".join(lines))


def _call_ollama(goal_text: str, allowed_tools: list[str]) -> dict[str, Any]:
    # Same HTTP pattern intent_parser.py already uses (requests.post to
    # localhost:11434/api/generate) — duplicated deliberately rather than
    # imported, to keep this module decoupled from intent_parser.py.
    full_prompt = f'{_build_system_prompt(allowed_tools)}\n\nGoal: "{goal_text}"\nJSON:'
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


def run_goal(goal_text: str, allowed_tools: list[str] | None = None, dry_run: bool = False) -> ToolResult:
    """Asks the LLM to pick one tool (from ``allowed_tools``, defaulting to
    Phase 10's ``ALLOWED_TOOLS`` if omitted) for ``goal_text``, validates
    that choice, gates it through the Policy Engine, and — if allowed or
    approved — runs it through the EXISTING Tool Executor (Phase 6,
    unmodified). Returns the resulting ``ToolResult``; a "no suitable
    tool" outcome or a declined confirmation are both normal, reportable
    results here, not raised exceptions.

    Follows Part 68's validation pipeline: parse -> schema check -> tool
    exists (in the allow-list AND the registry) -> policy check ->
    confirmation if required -> execute.

    ``dry_run=True`` (Phase 11's shadow mode) still performs the real LLM
    call and the real policy check, but stops there: neither
    ``request_confirmation()`` nor ``execute_tool()`` is ever called. See
    the module docstring for why that guarantee has to be structural, not
    incidental.
    """
    if allowed_tools is None:
        allowed_tools = ALLOWED_TOOLS

    print(f"[agent] goal: '{goal_text}'" + (" [dry run]" if dry_run else ""))

    try:
        decision = _call_ollama(goal_text, allowed_tools)
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
    # substitute." Checked against BOTH the given allow-list and the actual
    # registry — the LLM cannot reach a tool by picking a name outside this
    # call's allow-list even if it's registered elsewhere, and it cannot
    # reach a hallucinated name that isn't registered at all.
    if tool_name not in allowed_tools:
        print(f"[agent] rejected: '{tool_name}' is not in the allowed tool list for this call")
        return ToolResult(
            success=False,
            error=f"'{tool_name}' is outside the allowed tool list",
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

    if dry_run:
        # STRUCTURAL guarantee, not a happy coincidence: request_confirmation()
        # (which blocks on a terminal input()) and execute_tool() are simply
        # unreachable code from this branch — there is no path from here to
        # either call, regardless of what policy_decision says. A shadow
        # evaluation can never freeze a live voice session waiting for a
        # keypress, and can never affect what the user hears/sees.
        print(
            f"[shadow] would call: {tool_name} args={arguments} "
            f"(policy={policy_decision}, dry run, not executed)"
        )
        return ToolResult(
            success=True,
            data={
                "would_call": tool_name,
                "arguments": arguments,
                "policy_decision": policy_decision,
                "dry_run": True,
            },
        )

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
