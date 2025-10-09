#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.8"
# dependencies = []
# ///

import json
import subprocess
from datetime import datetime, timezone
from typing import Dict, Optional

progress_chars = {
    "empty_left": "",
    "empty_mid": "",
    "empty_right": "",
    "full_left": "",
    "full_mid": "",
    "full_right": "",
}


def run_command(cmd: str) -> Optional[str]:
    """Run a command and return its output."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, subprocess.SubprocessError):
        pass
    return None


def get_claude_usage_data() -> Optional[Dict]:
    """Get Claude Code usage data from ccusage command."""
    output = run_command("bunx ccusage blocks --active --json")
    if not output:
        return None

    try:
        data = json.loads(output)
        if data and "blocks" in data and data["blocks"]:
            return data["blocks"][0]
    except json.JSONDecodeError:
        pass

    return None


def calculate_percentages(block: Dict) -> int:
    """Calculate time, current, and projected percentages."""
    # Time percentage
    start_time = datetime.fromisoformat(block["startTime"].replace("Z", "+00:00"))
    end_time = datetime.fromisoformat(block["endTime"].replace("Z", "+00:00"))
    now = datetime.now(start_time.tzinfo)

    total_duration = (end_time - start_time).total_seconds()
    elapsed = (now - start_time).total_seconds()
    time_percentage = min(100, int(elapsed * 100 / total_duration))

    return time_percentage


def format_tooltip(block: Dict) -> str:
    """Format the tooltip with comprehensive usage information."""
    # Parse UTC times
    start_time_utc = datetime.fromisoformat(block["startTime"].replace("Z", "+00:00"))
    end_time_utc = datetime.fromisoformat(block["endTime"].replace("Z", "+00:00"))

    # Convert to local time for display
    start_time_local = start_time_utc.replace(tzinfo=timezone.utc).astimezone()
    end_time_local = end_time_utc.replace(tzinfo=timezone.utc).astimezone()
    now = datetime.now(timezone.utc)

    elapsed = now - start_time_utc
    elapsed_hours = int(elapsed.total_seconds() // 3600)
    elapsed_minutes = int((elapsed.total_seconds() % 3600) // 60)

    remaining_minutes = block["projection"]["remainingMinutes"]
    if remaining_minutes >= 60:
        hours = remaining_minutes // 60
        minutes = remaining_minutes % 60
        remaining_text = f"{hours}h {minutes}m"
    else:
        remaining_text = f"{remaining_minutes}m"

    # Get usage data
    total_tokens = block["totalTokens"]
    total_cost = block["costUSD"]
    projected_tokens = block["projection"]["totalTokens"]
    projected_cost = block["projection"]["totalCost"]
    tokens_per_minute = int(block["burnRate"]["tokensPerMinute"])
    cost_per_hour = block["burnRate"]["costPerHour"]

    tooltip = "Claude Code Usage\n"
    tooltip += f"Session: {start_time_local.strftime('%H:%M')} - {end_time_local.strftime('%H:%M')}\n"
    tooltip += f"Elapsed: {elapsed_hours}h {elapsed_minutes}m\n"
    tooltip += f"Remaining: {remaining_text}\n"
    tooltip += "\n"
    tooltip += f"Current Usage: {total_tokens:,} tokens (${total_cost:.2f})\n"
    tooltip += f"Projected: {projected_tokens:,} tokens (${projected_cost:.2f})\n"
    tooltip += "\n"
    tooltip += f"Burn Rate: {tokens_per_minute:,} tokens/min\n"
    tooltip += f"Cost Rate: ${cost_per_hour:.2f}/hr"

    return tooltip


def get_progress_bar(percentage: int) -> str:
    """Convert percentage to Unicode progress bar."""
    # 8 characters total: 1 left + 6 middle + 1 right
    total_segments = 8
    middle_segments = 6

    # Calculate how many segments should be filled
    filled_segments = min(total_segments, percentage * total_segments // 100)

    # Build the bar
    if filled_segments == 0:
        # All empty
        bar = (
            progress_chars["empty_left"]
            + progress_chars["empty_mid"] * middle_segments
            + progress_chars["empty_right"]
        )
    elif filled_segments >= total_segments:
        # All full
        bar = (
            progress_chars["full_left"]
            + progress_chars["full_mid"] * middle_segments
            + progress_chars["full_right"]
        )
    elif filled_segments == 1:
        # Only left segment filled
        bar = (
            progress_chars["full_left"]
            + progress_chars["empty_mid"] * middle_segments
            + progress_chars["empty_right"]
        )
    elif filled_segments == total_segments - 1:
        # All but right segment filled
        bar = (
            progress_chars["full_left"]
            + progress_chars["full_mid"] * middle_segments
            + progress_chars["empty_right"]
        )
    else:
        # Partial fill in the middle
        filled_middle = filled_segments - 1
        empty_middle = middle_segments - filled_middle
        bar = (
            progress_chars["full_left"]
            + progress_chars["full_mid"] * filled_middle
            + progress_chars["empty_mid"] * empty_middle
            + progress_chars["empty_right"]
        )

    return bar


def output_json(text: str, tooltip: str, percentage: int, css_class: str):
    """Output JSON for Waybar."""
    output = {
        "text": text,
        "tooltip": tooltip,
        "percentage": percentage,
        "class": css_class,
    }
    print(json.dumps(output))


def main():
    # Get Claude usage data
    block = get_claude_usage_data()
    if not block:
        # output_json("No active session", "No active Claude Code session", 0, "inactive")
        return

    # Calculate percentages
    time_pct = calculate_percentages(block)

    # Format tooltip with comprehensive information
    tooltip = format_tooltip(block)

    # Output time module
    bar = get_progress_bar(time_pct)
    output_json(f"󰚩  {bar}", tooltip, time_pct, "time")


if __name__ == "__main__":
    main()

