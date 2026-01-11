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
BAR_WIDTH = 44
HISTORY_FILE = os.path.expanduser("~/.local/share/claude-usage.json")
CLAUDE_CREDS_PATH = os.path.expanduser("~/.claude/.credentials.json")
OPENCODE_CREDS_PATH = os.path.expanduser("~/.local/share/opencode/auth.json")
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_REFRESH_MARGIN = 300  # Refresh if token expires within 5 minutes

progress_chars = {
    "empty_left": "",
    "empty_mid": "",
    "empty_right": "",
    "full_left": "",
    "full_mid": "",
    "full_right": "",
}

hourglass_frames = [
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
]


def refresh_claude_token() -> Optional[str]:
    """Refresh Claude CLI OAuth token using refresh token. Returns new access token."""
    if not os.path.exists(CLAUDE_CREDS_PATH):
        return None

    try:
        with open(CLAUDE_CREDS_PATH) as f:
            data = json.load(f)

        oauth = data.get("claudeAiOauth", {})
        refresh_token = oauth.get("refreshToken")
        if not refresh_token:
            return None

        # Make refresh request
        payload = json.dumps(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": OAUTH_CLIENT_ID,
            }
        ).encode("utf-8")

        req = urllib.request.Request(
            OAUTH_TOKEN_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.load(response)

        # Update credentials file with new tokens
        new_access_token = result.get("access_token")
        new_refresh_token = result.get("refresh_token")
        expires_in = result.get("expires_in", 28800)

        if new_access_token:
            oauth["accessToken"] = new_access_token
            # expiresAt is in milliseconds
            oauth["expiresAt"] = int((time.time() + expires_in) * 1000)
            if new_refresh_token:
                oauth["refreshToken"] = new_refresh_token
            data["claudeAiOauth"] = oauth

            with open(CLAUDE_CREDS_PATH, "w") as f:
                json.dump(data, f)

            return new_access_token

    except (json.JSONDecodeError, urllib.error.URLError, IOError, KeyError) as e:
        print(f"Token refresh failed: {e}", file=sys.stderr)

    return None


def refresh_opencode_token() -> Optional[str]:
    """Refresh OpenCode OAuth token using refresh token. Returns new access token."""
    if not os.path.exists(OPENCODE_CREDS_PATH):
        return None

    try:
        with open(OPENCODE_CREDS_PATH) as f:
            data = json.load(f)

        anthropic = data.get("anthropic", {})
        refresh_token = anthropic.get("refresh")
        if not refresh_token:
            return None

        # Make refresh request
        payload = json.dumps(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": OAUTH_CLIENT_ID,
            }
        ).encode("utf-8")

        req = urllib.request.Request(
            OAUTH_TOKEN_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.load(response)

        # Update credentials file with new tokens
        new_access_token = result.get("access_token")
        new_refresh_token = result.get("refresh_token")
        expires_in = result.get("expires_in", 28800)

        if new_access_token:
            anthropic["access"] = new_access_token
            # expires is in milliseconds
            anthropic["expires"] = int((time.time() + expires_in) * 1000)
            if new_refresh_token:
                anthropic["refresh"] = new_refresh_token
            data["anthropic"] = anthropic

            with open(OPENCODE_CREDS_PATH, "w") as f:
                json.dump(data, f, indent=4)

            return new_access_token

    except (json.JSONDecodeError, urllib.error.URLError, IOError, KeyError) as e:
        print(f"OpenCode token refresh failed: {e}", file=sys.stderr)

    return None


def get_valid_token() -> Optional[str]:
    """Get a valid OAuth token from Claude CLI or OpenCode credentials.

    Will automatically refresh expired tokens if a refresh token is available.
    """
    now = time.time()

    # Try Claude CLI credentials first
    if os.path.exists(CLAUDE_CREDS_PATH):
        try:
            with open(CLAUDE_CREDS_PATH) as f:
                data = json.load(f)
            oauth = data.get("claudeAiOauth", {})
            token = oauth.get("accessToken")
            expires_at = oauth.get("expiresAt")
            if token and expires_at:
                # expiresAt is a unix timestamp in milliseconds
                expires_at_sec = expires_at / 1000
                if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                    return token
                # Token expired or about to expire, try to refresh
                if oauth.get("refreshToken"):
                    new_token = refresh_claude_token()
                    if new_token:
                        return new_token
        except (json.JSONDecodeError, KeyError, ValueError):
            pass

    # Try OpenCode credentials
    if os.path.exists(OPENCODE_CREDS_PATH):
        try:
            with open(OPENCODE_CREDS_PATH) as f:
                data = json.load(f)
            anthropic = data.get("anthropic", {})
            token = anthropic.get("access")
            expires_at = anthropic.get("expires")
            if token and expires_at:
                # expires is a unix timestamp in milliseconds
                expires_at_sec = expires_at / 1000
                if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                    return token
                # Token expired or about to expire, try to refresh
                if anthropic.get("refresh"):
                    new_token = refresh_opencode_token()
                    if new_token:
                        return new_token
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


def load_history() -> Dict:
    """Load usage history from disk."""
    if not os.path.exists(HISTORY_FILE):
        return {
            "version": 1,
            "current": {
                "session_5h": None,
                "window_7d": None,
            },
            "history": {
                "sessions_5h": [],
                "windows_7d": [],
            },
        }

    try:
        with open(HISTORY_FILE) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {
            "version": 1,
            "current": {
                "session_5h": None,
                "window_7d": None,
            },
            "history": {
                "sessions_5h": [],
                "windows_7d": [],
            },
        }


def save_history(history: Dict) -> None:
    """Save usage history to disk."""
    # Ensure directory exists
    os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)

    try:
        with open(HISTORY_FILE, "w") as f:
            json.dump(history, f, indent=2)
    except IOError as e:
        print(f"Failed to save history: {e}", file=sys.stderr)


def update_history(usage_data: Dict) -> None:
    """Update usage history with new data."""
    now = int(time.time())
    history = load_history()

    # Check if current 5h session should be archived
    current_5h = history["current"]["session_5h"]
    if current_5h and current_5h["reset_at"] != usage_data["5h_reset"]:
        # The reset_at changed, meaning the old session ended
        # Archive the old session
        history["history"]["sessions_5h"].append(
            {
                "reset_at": current_5h["reset_at"],
                "utilization": current_5h["utilization"],
                "recorded_at": current_5h["last_updated"],
            }
        )

    # Check if current 7d window should be archived
    current_7d = history["current"]["window_7d"]
    if current_7d and current_7d["reset_at"] != usage_data["7d_reset"]:
        # The reset_at changed, meaning the old window ended
        # Archive the old window
        history["history"]["windows_7d"].append(
            {
                "reset_at": current_7d["reset_at"],
                "utilization": current_7d["utilization"],
                "recorded_at": current_7d["last_updated"],
            }
        )

    # Update current sessions
    history["current"]["session_5h"] = {
        "reset_at": usage_data["5h_reset"],
        "utilization": usage_data["5h_utilization"],
        "last_updated": now,
    }
    history["current"]["window_7d"] = {
        "reset_at": usage_data["7d_reset"],
        "utilization": usage_data["7d_utilization"],
        "last_updated": now,
    }

    save_history(history)


def format_reset_time(reset_timestamp: int) -> str:
    """Format reset timestamp to human-readable time like 'in 2 hours (11:00)'."""
    if reset_timestamp == 0:
        return "unknown"
    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()
    # delta = reset_dt - now

    # Get relative time using humanize
    # relative = humanize.naturaldelta(delta)
    relative = format_reset_short(reset_timestamp)

    # Format the absolute time part
    if reset_dt.date() == now.date():
        absolute = reset_dt.strftime("%H:%M")
    elif (reset_dt.date() - now.date()).days == 1:
        absolute = f"tomorrow {reset_dt.strftime('%H:%M')}"
    else:
        absolute = reset_dt.strftime("%A %H:%M")

    return f"{relative} ({absolute})"


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
    bar_5h = get_progress_bar(int(util_5h), width=BAR_WIDTH)
    bar_7d = get_progress_bar(int(util_7d), width=BAR_WIDTH)

    time_elapsed_5h = get_time_elapsed_percentage(data["5h_reset"], 5.0)
    time_elapsed_7d = get_time_elapsed_percentage(data["7d_reset"], 7 * 24.0)
    time_bar_5h = get_time_bar(int(time_elapsed_5h), width=BAR_WIDTH)
    time_bar_7d = get_time_bar(int(time_elapsed_7d), width=BAR_WIDTH)
    hourglass_5h = get_hourglass_icon(time_elapsed_5h)
    hourglass_7d = get_hourglass_icon(time_elapsed_7d)

    end_time_5h = format_end_time(data["5h_reset"])
    end_time_7d = format_end_time(data["7d_reset"])
    remaining_5h = format_reset_short(data["5h_reset"])
    remaining_7d = format_reset_short(data["7d_reset"])

    active_claim = data["representative_claim"]
    zap = ""

    lines = []
    lines.append("")
    lines.append(
        f"5-hour session{' (active)' if active_claim == 'five_hour' else ''} {end_time_5h} ({remaining_5h})"
    )
    lines.append(f"{zap}  {bar_5h} {util_5h:4.1f}%")
    lines.append(f"{hourglass_5h}  {time_bar_5h} {time_elapsed_5h:4.1f}%")
    if data["5h_status"] != "allowed":
        lines.append(f"  Status: {data['5h_status']}")
    lines.append("")

    lines.append(
        f"7-day window{' (active)' if active_claim == 'seven_day' else ''} {end_time_7d} ({remaining_7d})"
    )
    lines.append(f"{zap}  {bar_7d} {util_7d:4.1f}%")
    lines.append(f"{hourglass_7d}  {time_bar_7d} {time_elapsed_7d:4.1f}%")
    if data["7d_status"] != "allowed":
        lines.append(f"  Status: {data['7d_status']}")

    if data["status"] != "allowed":
        lines.append("")
        lines.append(f"Overall status: {data['status']}")

    if last_check_time:
        lines.append("")
        lines.append(f"Last checked {format_relative_time(last_check_time)}")

    title = "Claude Max Usage"
    centered_title = title.center(max(len(line) for line in lines))

    return centered_title + "\n" + "\n".join(lines)


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


def get_time_bar(percentage: int, width: int) -> str:
    """Convert percentage to simple Unicode progress bar using ▰▱ characters."""
    filled_segments = min(width, percentage * width // 100)
    empty_segments = width - filled_segments
    return "▰" * filled_segments + "▱" * empty_segments


def get_hourglass_icon(elapsed_percentage: float) -> str:
    """Get the appropriate hourglass icon based on elapsed percentage."""
    num_frames = len(hourglass_frames)
    frame_index = int(elapsed_percentage * num_frames / 100)
    # Clamp to valid range
    frame_index = max(0, min(num_frames - 1, frame_index))
    return hourglass_frames[frame_index]


def get_time_elapsed_percentage(reset_timestamp: int, window_hours: float) -> float:
    """Calculate percentage of time elapsed in a window.

    Returns percentage from 0-100 where 100 means the window just reset
    and 0 means it's about to reset.
    """
    if reset_timestamp <= 0:
        return 0.0

    now = time.time()
    window_seconds = window_hours * 3600
    time_remaining = reset_timestamp - now

    if time_remaining <= 0:
        return 100.0  # Window has reset

    time_elapsed = window_seconds - time_remaining
    percentage = (time_elapsed / window_seconds) * 100
    return max(0.0, min(100.0, percentage))


def format_end_time(reset_timestamp: int) -> str:
    """Format reset timestamp to 'ends ...' phrase like 'ends at 14:00' or 'ends on Monday at 14:00'."""
    if reset_timestamp == 0:
        return "ends at unknown"
    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()

    time_str = reset_dt.strftime("%H:%M")
    if reset_dt.date() == now.date():
        return f"ends at {time_str}"
    elif (reset_dt.date() - now.date()).days == 1:
        return f"ends tomorrow at {time_str}"
    else:
        return f"ends on {reset_dt.strftime('%A')} at {time_str}"


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
    expired_5h_triggered: bool = False
    expired_7d_triggered: bool = False
    last_check_start: float = 0.0

    def run_check_async(result_container: list, lock: threading.Lock):
        try:
            result = fetch_usage_data()
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Background check error: {e}", file=sys.stderr)

    def start_check():
        nonlocal check_thread, last_check_start
        check_thread = threading.Thread(
            target=run_check_async,
            args=(check_result, check_lock),
            daemon=True,
        )
        check_thread.start()
        last_check_start = time.time()

    # Start initial check immediately
    start_check()

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
                            # Reset expiry triggers when we get new data
                            expired_5h_triggered = False
                            expired_7d_triggered = False
                            # Update history
                            update_history(data)
                        last_check_time = datetime.now()
                        check_result[0] = None
                check_thread = None

            # Check if either timer has expired and trigger a check
            should_check = False
            if usage_data:
                if (
                    usage_data["5h_reset"] > 0
                    and current_time >= usage_data["5h_reset"]
                ):
                    if not expired_5h_triggered:
                        expired_5h_triggered = True
                        should_check = True
                if (
                    usage_data["7d_reset"] > 0
                    and current_time >= usage_data["7d_reset"]
                ):
                    if not expired_7d_triggered:
                        expired_7d_triggered = True
                        should_check = True

            # Start new check if interval elapsed or timer expired
            if (should_check or current_time - last_check_start >= CHECK_INTERVAL) and (
                check_thread is None or not check_thread.is_alive()
            ):
                start_check()

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
