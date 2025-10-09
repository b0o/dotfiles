#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.11"
# dependencies = [
# ]
# ///

import json
import time
from pathlib import Path
from typing import Dict, Any

STATUS_FILE = Path("/tmp/command-center-status.json")
SPINNER_CHARS = [
    "",
    "",
    "",
    "",
    "",
    "",
]

# Tool icons mapping
TOOL_ICONS = {
    "mcp__speech__speak": " ",
    "Read": " ",
    "Write": "󱇨 ",
    "Edit": "󱇨 ",
    "MultiEdit": "󱇨 ",
    "Bash": " ",
    "Task": " ",
    "Grep": "󰱽 ",
    "Glob": " ",
    "LS": "󰙅 ",
    "WebFetch": " ",
    "WebSearch": "󰖟 ",
    "TodoWrite": "󰝖 ",
    "NotebookRead": "󰠮 ",
    "NotebookEdit": "󱓧 ",
}


def get_tool_icon(tool_name: str) -> str:
    """Get icon for a tool, with prefix matching for MCP tools."""
    if not tool_name:
        return ""

    # Direct match first
    if tool_name in TOOL_ICONS:
        return TOOL_ICONS[tool_name]

    # Check for prefix matches (for MCP tools)
    if tool_name.startswith("mcp__linear__"):
        return "󰪡 "
    elif tool_name.startswith("mcp__context7__"):
        return "󱂛 "

    return " "  # Default tool icon


def get_status() -> Dict[str, Any]:
    """Read current status from file."""
    if not STATUS_FILE.exists():
        return {
            "state": "idle",
            "message": "Ready",
            "last_activity": 0,
            "current_tool": None,
            "started_at": None,
        }

    try:
        with open(STATUS_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {
            "state": "idle",
            "message": "Ready",
            "last_activity": 0,
            "current_tool": None,
            "started_at": None,
        }


def format_waybar_output(status: Dict[str, Any]) -> Dict[str, Any]:
    """Format status for waybar display."""
    state = status.get("state", "idle")
    message = status.get("message", "Ready")
    current_tool = status.get("current_tool")
    started_at = status.get("started_at")

    # Determine icon and text based on state
    if state == "idle":
        text = ""
        css_class = ["command-center", "state-idle"]
        tooltip = "Command Center: Ready"

    elif state == "processing":
        # Animated spinner for processing
        elapsed = int(time.time() * 10 - started_at * 10) if started_at else 0
        spinner = SPINNER_CHARS[elapsed % len(SPINNER_CHARS)]
        text = f"{spinner}"
        css_class = ["command-center", "state-processing"]
        tooltip = f"Command Center: {message}"

    elif state == "tool_execution":
        # New version with tool icons
        elapsed = int(time.time() * 10 - started_at * 10) if started_at else 0
        spinner = SPINNER_CHARS[elapsed % len(SPINNER_CHARS)]
        tool_icon = get_tool_icon(current_tool or "")
        text = f"{tool_icon} {spinner}"
        css_class = ["command-center", "state-tool"]
        tooltip = f"Command Center: Executing {current_tool}"

    elif state == "waiting_permission":
        text = "󰗻"
        css_class = ["command-center", "state-waiting"]
        tooltip = "Command Center: Waiting for permission"

    else:
        text = ""
        css_class = ["command-center", "state-unknown"]
        tooltip = f"Command Center: {state}"

    return {
        "text": text,
        "tooltip": tooltip,
        "class": css_class,
        "alt": f"command-center-{state}",
    }


def main():
    """Main execution - continuous monitoring."""
    last_output = None
    last_mtime = 0

    while True:
        try:
            # Check if status file was modified
            current_mtime = STATUS_FILE.stat().st_mtime if STATUS_FILE.exists() else 0

            # Always update output
            status = get_status()
            output = format_waybar_output(status)
            output_json = json.dumps(output)

            # Only print if output changed or file was modified
            if output_json != last_output or current_mtime != last_mtime:
                print(output_json, flush=True)
                last_output = output_json
                last_mtime = current_mtime

            # Update frequency - faster for active states for smooth spinner
            if status.get("state") in ["processing", "tool_execution"]:
                time.sleep(0.1)
            else:
                time.sleep(0.5)

        except Exception as e:
            # Always output valid JSON for waybar
            error_output = {
                "text": "",
                "tooltip": f"Command Center Error: {str(e)}",
                "class": ["command-center", "state-error"],
                "alt": "command-center-error",
            }
            print(json.dumps(error_output), flush=True)
            time.sleep(1)


if __name__ == "__main__":
    main()
