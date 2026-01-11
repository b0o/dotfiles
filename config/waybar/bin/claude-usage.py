#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.8"
# dependencies = ["humanize"]
# ///

import json
import os
import re
import sys
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from typing import Dict, Optional

import humanize  # pyright: ignore

CHECK_INTERVAL = 60.0
OUTPUT_INTERVAL = 1.0
BAR_WIDTH = 30

progress_chars = {
    "empty_left": "",
    "empty_mid": "",
    "empty_right": "",
    "full_left": "",
    "full_mid": "",
    "full_right": "",
}


def get_valid_token() -> Optional[str]:
    """Get a valid OAuth token from Claude CLI or OpenCode credentials."""
    now = time.time()

    # Try Claude CLI credentials first
    claude_creds_path = os.path.expanduser("~/.claude/.credentials.json")
    if os.path.exists(claude_creds_path):
        try:
            with open(claude_creds_path) as f:
                data = json.load(f)
            oauth = data.get("claudeAiOauth", {})
            token = oauth.get("accessToken")
            expires_at = oauth.get("expiresAt")
            if token and expires_at:
                # expiresAt is a unix timestamp in milliseconds
                if expires_at / 1000 > now:
                    return token
        except (json.JSONDecodeError, KeyError, ValueError):
            pass

    # Try OpenCode credentials
    opencode_creds_path = os.path.expanduser("~/.local/share/opencode/auth.json")
    if os.path.exists(opencode_creds_path):
        try:
            with open(opencode_creds_path) as f:
                data = json.load(f)
            anthropic = data.get("anthropic", {})
            token = anthropic.get("access")
            expires_at = anthropic.get("expires")
            if token and expires_at:
                # expires is a unix timestamp in milliseconds
                if expires_at / 1000 > now:
                    return token
        except (json.JSONDecodeError, KeyError, ValueError):
            pass

    return None


def query_usage_headers(token: str) -> Optional[Dict[str, str]]:
    """Query the Anthropic API and return rate limit headers."""
    url = "https://api.anthropic.com/v1/messages?beta=true"
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "oauth-2025-04-20,interleaved-thinking-2025-05-14",
        "anthropic-dangerous-direct-browser-access": "true",
        "x-app": "cli",
        "User-Agent": "claude-cli/2.1.3 (external, cli)",
    }
    payload = json.dumps(
        {
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "quota"}],
        }
    ).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return {k.lower(): v for k, v in response.headers.items()}
    except urllib.error.HTTPError as e:
        # Even on error responses, we can get headers
        return {k.lower(): v for k, v in e.headers.items()}
    except (urllib.error.URLError, TimeoutError):
        return None


def parse_usage_data(headers: Dict[str, str]) -> Optional[Dict]:
    """Parse rate limit headers into usage data."""
    try:
        data = {
            "status": headers.get("anthropic-ratelimit-unified-status", "unknown"),
            "5h_status": headers.get(
                "anthropic-ratelimit-unified-5h-status", "unknown"
            ),
            "5h_reset": int(headers.get("anthropic-ratelimit-unified-5h-reset", 0)),
            "5h_utilization": float(
                headers.get("anthropic-ratelimit-unified-5h-utilization", 0)
            ),
            "7d_status": headers.get(
                "anthropic-ratelimit-unified-7d-status", "unknown"
            ),
            "7d_reset": int(headers.get("anthropic-ratelimit-unified-7d-reset", 0)),
            "7d_utilization": float(
                headers.get("anthropic-ratelimit-unified-7d-utilization", 0)
            ),
            "representative_claim": headers.get(
                "anthropic-ratelimit-unified-representative-claim", ""
            ),
            "fallback_percentage": float(
                headers.get("anthropic-ratelimit-unified-fallback-percentage", 0)
            ),
        }
        return data
    except (ValueError, TypeError):
        return None


def fetch_usage_data() -> tuple[Optional[Dict], bool]:
    """Fetch and parse usage data from the API. Returns (data, has_token)."""
    token = get_valid_token()
    if not token:
        return None, False

    headers = query_usage_headers(token)
    if not headers:
        return None, True

    return parse_usage_data(headers), True


def format_reset_time(reset_timestamp: int) -> str:
    """Format reset timestamp to human-readable time like 'in 2 hours (11:00)'."""
    if reset_timestamp == 0:
        return "unknown"
    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()
    delta = reset_dt - now

    # Get relative time using humanize
    relative = humanize.naturaldelta(delta)

    # Format the absolute time part
    if reset_dt.date() == now.date():
        absolute = reset_dt.strftime("%H:%M")
    elif (reset_dt.date() - now.date()).days == 1:
        absolute = f"tomorrow {reset_dt.strftime('%H:%M')}"
    else:
        absolute = reset_dt.strftime("%A %H:%M")

    return f"in {relative} ({absolute})"


def format_reset_short(reset_timestamp: int) -> str:
    """Format reset timestamp to short form like '3h' or '12m'."""
    if reset_timestamp <= 0:
        return "0m"

    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()
    delta = reset_dt - now

    if delta.total_seconds() <= 0:
        return "0m"

    result = humanize.naturaldelta(delta)

    # Handle "a moment" for very small deltas
    if result == "a moment":
        return "0s"

    # Handle "a/an" forms like "an hour" -> "1h", "a minute" -> "1m"
    result = re.sub(r"\ba\s+second\b", "1s", result)
    result = re.sub(r"\ba\s+minute\b", "1m", result)
    result = re.sub(r"\ban\s+hour\b", "1h", result)
    result = re.sub(r"\ba\s+day\b", "1d", result)
    result = re.sub(r"\ba\s+month\b", "1mo", result)
    result = re.sub(r"\ba\s+year\b", "1y", result)

    # Shorten "X units" -> "Xu" forms
    result = re.sub(r"(\d+)\s*seconds?", r"\1s", result)
    result = re.sub(r"(\d+)\s*minutes?", r"\1m", result)
    result = re.sub(r"(\d+)\s*hours?", r"\1h", result)
    result = re.sub(r"(\d+)\s*days?", r"\1d", result)
    result = re.sub(r"(\d+)\s*months?", r"\1mo", result)
    result = re.sub(r"(\d+)\s*years?", r"\1y", result)

    # Clean up compound forms like "1y, 2mo" -> just use the largest unit
    # For a short display, we only want the primary unit
    result = re.sub(r"^(\d+[a-z]+),?\s+.*", r"\1", result)

    return result


def format_relative_time(dt: datetime) -> str:
    """Format a datetime as a human-readable relative time."""
    delta = datetime.now() - dt
    seconds = int(delta.total_seconds())

    if seconds < 5:
        return "just now"
    elif seconds < 60:
        return f"{seconds} seconds ago"
    elif seconds < 120:
        return "1 minute ago"
    elif seconds < 3600:
        return f"{seconds // 60} minutes ago"
    elif seconds < 7200:
        return "1 hour ago"
    else:
        return f"{seconds // 3600} hours ago"


def format_tooltip(data: Dict, last_check_time: Optional[datetime] = None) -> str:
    """Format the tooltip with usage information."""
    util_5h = data["5h_utilization"] * 100
    util_7d = data["7d_utilization"] * 100
    reset_5h = format_reset_time(data["5h_reset"])
    reset_7d = format_reset_time(data["7d_reset"])
    bar_5h = get_progress_bar(int(util_5h), width=BAR_WIDTH)
    bar_7d = get_progress_bar(int(util_7d), width=BAR_WIDTH)

    tooltip = "Claude API Usage\n"

    if last_check_time:
        tooltip += f"Last check: {format_relative_time(last_check_time)}\n"

    active_claim = data["representative_claim"]

    tooltip += "\n"
    tooltip += f"5-hour window{' (active)' if active_claim == 'five_hour' else ''}\n"
    tooltip += f"{bar_5h} {util_5h:.1f}%\n"
    if data["5h_status"] != "allowed":
        tooltip += f"Status: {data['5h_status']}\n"
    tooltip += f"Resets {reset_5h}\n"
    tooltip += "\n"

    tooltip += f"7-day window{' (active)' if active_claim == 'seven_day' else ''}\n"
    tooltip += f"{bar_7d} {util_7d:.1f}%\n"
    if data["7d_status"] != "allowed":
        tooltip += f"Status: {data['7d_status']}\n"
    tooltip += f"Resets {reset_7d}\n"
    if data["status"] != "allowed":
        tooltip += "\n"
        tooltip += f"Overall status: {data['status']}\n"

    return tooltip


def get_progress_bar(percentage: int, width: int) -> str:
    """Convert percentage to Unicode progress bar."""
    total_segments = width
    middle_segments = total_segments - 2

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


def format_waybar_output(
    data: Optional[Dict],
    last_check_time: Optional[datetime] = None,
    show_time_remaining: bool = False,
    has_token: bool = True,
) -> Optional[Dict]:
    """Format output for Waybar."""
    if not has_token:
        return {
            "text": "󰛄",
            "tooltip": "No active token",
            "percentage": 0,
            "class": "inactive",
        }

    if not data:
        return None

    # Use the representative claim to determine which utilization to show
    # "five_hour" means the 5h limit is the active constraint
    if data["representative_claim"] == "five_hour":
        primary_util = data["5h_utilization"]
    else:
        primary_util = data["7d_utilization"]

    percentage = int(primary_util * 100)

    # Determine CSS class based on status and usage percentage
    # Check if any status is not allowed - that's critical
    if (
        data["status"] != "allowed"
        or data["5h_status"] != "allowed"
        or data["7d_status"] != "allowed"
    ):
        css_class = "critical"
    elif data["representative_claim"] != "five_hour":
        css_class = "inactive"
    elif percentage == 0:
        css_class = "inactive"
    elif percentage <= 33:
        css_class = "low"
    elif percentage <= 66:
        css_class = "med"
    elif percentage <= 90:
        css_class = "high"
    else:
        css_class = "critical"

    # Format tooltip
    tooltip = format_tooltip(data, last_check_time)

    # Format text - alternate between percentage and time remaining
    if data["representative_claim"] == "five_hour":
        reset_short = format_reset_short(data["5h_reset"])
    else:
        reset_short = format_reset_short(data["7d_reset"])

    # Only alternate if there's an active 5h session
    if show_time_remaining and data["representative_claim"] == "five_hour":
        text = f"󰛄 {reset_short}"
    else:
        text = f"󰛄 {percentage}%"

    return {
        "text": text,
        "tooltip": tooltip,
        "percentage": percentage,
        "class": css_class,
    }


def monitor():
    """Main monitoring loop."""
    last_check_time: Optional[datetime] = None
    last_output_json: Optional[str] = None
    usage_data: Optional[Dict] = None
    has_token: bool = True
    check_thread: Optional[threading.Thread] = None
    check_result: list = [(None, True)]
    check_lock = threading.Lock()

    def run_check_async(result_container: list, lock: threading.Lock):
        try:
            result = fetch_usage_data()
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Background check error: {e}", file=sys.stderr)

    # Start initial check immediately
    check_thread = threading.Thread(
        target=run_check_async,
        args=(check_result, check_lock),
        daemon=True,
    )
    check_thread.start()
    last_check_start = time.time()

    try:
        while True:
            current_time = time.time()

            # Check if background thread completed
            if check_thread is not None and not check_thread.is_alive():
                with check_lock:
                    if check_result[0] is not None:
                        data, token_valid = check_result[0]
                        has_token = token_valid
                        if data is not None:
                            usage_data = data
                        last_check_time = datetime.now()
                        check_result[0] = None
                check_thread = None

            # Start new check if interval elapsed
            if current_time - last_check_start >= CHECK_INTERVAL and (
                check_thread is None or not check_thread.is_alive()
            ):
                check_thread = threading.Thread(
                    target=run_check_async,
                    args=(check_result, check_lock),
                    daemon=True,
                )
                check_thread.start()
                last_check_start = current_time

            # Determine display mode: 15s percentage, 5s time remaining
            cycle_position = int(current_time) % 20
            show_time_remaining = cycle_position >= 15

            # Format and output
            output = format_waybar_output(
                usage_data, last_check_time, show_time_remaining, has_token
            )
            if output:
                output_json = json.dumps(output)
                if output_json != last_output_json:
                    print(output_json, flush=True)
                    last_output_json = output_json

            time.sleep(OUTPUT_INTERVAL)

    except KeyboardInterrupt:
        sys.exit(0)


def main():
    monitor()


if __name__ == "__main__":
    main()
