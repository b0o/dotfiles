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
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional

import signal

CHECK_INTERVAL = 60.0
OUTPUT_INTERVAL = 5.0
BAR_WIDTH = 46
HISTORY_FILE = os.path.expanduser("~/.local/share/claude-usage.json")
CLAUDE_CREDS_PATH = os.path.expanduser("~/.claude/.credentials.json")
OPENCODE_CREDS_PATH = os.path.expanduser("~/.local/share/opencode/auth.json")
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_PROFILE_URL = "https://api.anthropic.com/api/oauth/profile"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_REFRESH_MARGIN = 300  # Refresh if token expires within 5 minutes

COLOR_SUBDUED = "#c3bae6"  # header details, footer, percentages <=85%, icons
COLOR_DIM = "#61557d"  # bar bg

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

icons = {
    "bullet": "·",
    "zap": "",
}


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


def get_valid_token(
    prefer: Optional[str] = None,
) -> tuple[Optional[str], Optional[str], bool]:
    """Get a valid OAuth token from Claude CLI or OpenCode credentials.

    Will automatically refresh expired tokens if a refresh token is available.

    Args:
        prefer: "cc" for Claude Code, "oc" for OpenCode, None for auto
                (auto mode tries the most recently modified credential file first)

    Returns:
        Tuple of (token, source, is_fallback) where source is "cc" or "oc",
        is_fallback is True if we had to use the non-preferred source,
        or (None, None, False) if no valid token.
    """
    now = time.time()

    def check_token_valid(
        path: str, token_key: str, expires_key: str, data_key: Optional[str] = None
    ) -> bool:
        """Check if a credential file has a valid (non-expired) token."""
        if not os.path.exists(path):
            return False
        try:
            with open(path) as f:
                data = json.load(f)
            if data_key:
                data = data.get(data_key, {})
            token = data.get(token_key)
            expires_at = data.get(expires_key)
            if token and expires_at:
                expires_at_sec = expires_at / 1000
                return expires_at_sec > now + TOKEN_REFRESH_MARGIN
        except (json.JSONDecodeError, KeyError, ValueError, IOError):
            pass
        return False

    def get_mtime(path: str) -> float:
        """Get file modification time, or 0 if file doesn't exist."""
        try:
            return os.path.getmtime(path)
        except OSError:
            return 0

    def try_claude_code() -> Optional[str]:
        if os.path.exists(CLAUDE_CREDS_PATH):
            try:
                with open(CLAUDE_CREDS_PATH) as f:
                    data = json.load(f)
                oauth = data.get("claudeAiOauth", {})
                token = oauth.get("accessToken")
                expires_at = oauth.get("expiresAt")
                if token and expires_at:
                    expires_at_sec = expires_at / 1000
                    if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                        return token
                    if oauth.get("refreshToken"):
                        new_token = refresh_claude_token()
                        if new_token:
                            return new_token
            except (json.JSONDecodeError, KeyError, ValueError):
                pass
        return None

    def try_opencode() -> Optional[str]:
        if os.path.exists(OPENCODE_CREDS_PATH):
            try:
                with open(OPENCODE_CREDS_PATH) as f:
                    data = json.load(f)
                anthropic = data.get("anthropic", {})
                token = anthropic.get("access")
                expires_at = anthropic.get("expires")
                if token and expires_at:
                    expires_at_sec = expires_at / 1000
                    if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                        return token
                    if anthropic.get("refresh"):
                        new_token = refresh_opencode_token()
                        if new_token:
                            return new_token
            except (json.JSONDecodeError, KeyError, ValueError):
                pass
        return None

    # Determine order based on preference
    if prefer == "oc":
        sources = [("oc", try_opencode), ("cc", try_claude_code)]
    elif prefer == "cc":
        sources = [("cc", try_claude_code), ("oc", try_opencode)]
    else:
        # Auto mode: if both have valid tokens, prefer the more recently modified file
        cc_valid = check_token_valid(
            CLAUDE_CREDS_PATH, "accessToken", "expiresAt", "claudeAiOauth"
        )
        oc_valid = check_token_valid(
            OPENCODE_CREDS_PATH, "access", "expires", "anthropic"
        )

        if cc_valid and oc_valid:
            # Both valid, use the one with more recent mtime
            cc_mtime = get_mtime(CLAUDE_CREDS_PATH)
            oc_mtime = get_mtime(OPENCODE_CREDS_PATH)
            if oc_mtime > cc_mtime:
                sources = [("oc", try_opencode), ("cc", try_claude_code)]
            else:
                sources = [("cc", try_claude_code), ("oc", try_opencode)]
        else:
            # Default order if not both valid
            sources = [("cc", try_claude_code), ("oc", try_opencode)]

    for i, (source, try_fn) in enumerate(sources):
        token = try_fn()
        if token:
            # is_fallback is True if we have a preference and this isn't the first choice
            is_fallback = prefer is not None and i > 0
            return token, source, is_fallback

    return None, None, False


def fetch_profile(token: str) -> Optional[Dict]:
    """Fetch user profile including plan/tier info."""
    req = urllib.request.Request(
        OAUTH_PROFILE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
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


def fetch_usage_data(
    previous_token: Optional[str] = None,
    prefer_source: Optional[str] = None,
) -> tuple[Optional[Dict], Optional[Dict], Optional[str], Optional[str], bool, bool]:
    """Fetch and parse usage data from the API.

    Returns (data, profile, token, source, is_fallback, has_token).
    Profile is only fetched if token changed from previous_token.
    Source is "cc" (Claude Code) or "oc" (OpenCode).
    is_fallback is True if using non-preferred source due to preferred being unavailable.
    """
    token, source, is_fallback = get_valid_token(prefer_source)
    if not token:
        return None, None, None, None, False, False

    headers = query_usage_headers(token)
    if not headers:
        return None, None, token, source, is_fallback, True

    usage_data = parse_usage_data(headers)

    # Only fetch profile if token changed (new login or refresh)
    profile = None
    if token != previous_token:
        profile = fetch_profile(token)

    return usage_data, profile, token, source, is_fallback, True


def empty_account_data() -> Dict:
    """Return empty account data structure."""
    return {
        "current": {
            "session_5h": None,
            "window_7d": None,
        },
        "history": {
            "sessions_5h": [],
            "windows_7d": [],
        },
    }


def load_history() -> Dict:
    """Load usage history and config from disk."""
    empty = {
        "version": 2,
        "config": {
            "prefer_source": None,  # "cc" or "oc" or None for auto
            "display_mode": "normal",  # "compact", "normal", or "expanded"
        },
        "accounts": {},
        "active_account": None,
    }

    if not os.path.exists(HISTORY_FILE):
        return empty

    try:
        with open(HISTORY_FILE) as f:
            data = json.load(f)
        # Ensure config section exists
        if "config" not in data:
            data["config"] = empty["config"]
        return data
    except (json.JSONDecodeError, IOError):
        return empty


def save_history(history: Dict) -> None:
    """Save usage history to disk."""
    # Ensure directory exists
    os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)

    try:
        with open(HISTORY_FILE, "w") as f:
            json.dump(history, f, indent=2)
    except IOError as e:
        print(f"Failed to save history: {e}", file=sys.stderr)


def save_pid() -> None:
    """Save current PID to history file."""
    history = load_history()
    history["pid"] = os.getpid()
    save_history(history)


def clear_pid() -> None:
    """Clear PID from history file on exit."""
    try:
        history = load_history()
        if history.get("pid") == os.getpid():
            history["pid"] = None
            save_history(history)
    except Exception:
        # Best effort cleanup, don't fail on exit
        pass


def is_pid_running(pid: int) -> bool:
    """Check if a process with the given PID is running."""
    try:
        os.kill(pid, 0)  # Signal 0 doesn't kill, just checks
        return True
    except (ProcessLookupError, PermissionError):
        return False


def check_existing_instance() -> Optional[int]:
    """Check if another instance is already running.

    Returns the PID of the running instance, or None if no instance is running.
    Cleans up stale PID if the process is no longer running.
    """
    history = load_history()
    pid = history.get("pid")
    if pid and pid != os.getpid():
        if is_pid_running(pid):
            return pid
        else:
            # Stale PID, clean it up
            history["pid"] = None
            save_history(history)
    return None


def signal_running_instance() -> bool:
    """Signal the running instance to refresh. Returns True if signal sent."""
    history = load_history()
    pid = history.get("pid")
    if pid:
        try:
            os.kill(pid, signal.SIGUSR1)
            return True
        except (ProcessLookupError, PermissionError):
            # Process doesn't exist or we can't signal it
            pass
    return False


def set_config(key: str, value) -> None:
    """Set a config value and signal running instance."""
    history = load_history()
    if "config" not in history:
        history["config"] = {}
    history["config"][key] = value
    save_history(history)
    signal_running_instance()


def load_current_snapshots() -> tuple[list[tuple[float, float]], int]:
    """Load snapshots for the current 5h session from history.

    Returns:
        Tuple of (snapshots list, reset_at timestamp).
        Returns empty list and 0 if no current session or snapshots.
    """
    history = load_history()
    active_account = history.get("active_account")
    if not active_account:
        return [], 0

    account = history.get("accounts", {}).get(active_account, {})
    current_5h = account.get("current", {}).get("session_5h")
    if not current_5h:
        return [], 0

    reset_at = current_5h.get("reset_at", 0)
    stored_snapshots = current_5h.get("snapshots", [])

    # Convert from [timestamp, utilization] lists back to tuples
    snapshots = [(float(s[0]), float(s[1])) for s in stored_snapshots]
    return snapshots, reset_at


def update_history(
    usage_data: Dict,
    profile: Optional[Dict] = None,
    snapshots: Optional[list[tuple[float, float]]] = None,
) -> None:
    """Update usage history with new data."""
    now = int(time.time())
    history = load_history()

    # Get account UUID from profile (required for storing history)
    account_uuid = None
    if profile:
        account_uuid = profile.get("account", {}).get("uuid")

    # If no profile provided, use active account from history
    if not account_uuid:
        account_uuid = history.get("active_account")

    # Can't store history without knowing which account
    if not account_uuid:
        return

    # Ensure account exists in history
    if account_uuid not in history["accounts"]:
        history["accounts"][account_uuid] = empty_account_data()

    account = history["accounts"][account_uuid]

    # Update account profile info if we have it
    if profile:
        org = profile.get("organization", {})
        account["email"] = profile.get("account", {}).get("email")
        account["organization_name"] = org.get("name")
        account["organization_type"] = org.get("organization_type")
        account["rate_limit_tier"] = org.get("rate_limit_tier")
        account["last_updated"] = now

    # Update active account
    history["active_account"] = account_uuid

    # Extract plan info for session records
    plan_info = None
    if account.get("organization_type"):
        plan_info = {
            "organization_type": account["organization_type"],
            "rate_limit_tier": account.get("rate_limit_tier"),
        }

    # Check if current 5h session should be archived
    current_5h = account["current"]["session_5h"]
    if current_5h and current_5h["reset_at"] != usage_data["5h_reset"]:
        # The reset_at changed, meaning the old session ended
        # Archive the old session with plan info (skip invalid entries with reset_at=0)
        if current_5h["reset_at"] > 0:
            archived = {
                "reset_at": current_5h["reset_at"],
                "utilization": current_5h["utilization"],
                "recorded_at": current_5h["last_updated"],
            }
            if current_5h.get("plan"):
                archived["plan"] = current_5h["plan"]
            if current_5h.get("snapshots"):
                archived["snapshots"] = current_5h["snapshots"]
            account["history"]["sessions_5h"].append(archived)

    # Check if current 7d window should be archived
    current_7d = account["current"]["window_7d"]
    if current_7d and current_7d["reset_at"] != usage_data["7d_reset"]:
        # The reset_at changed, meaning the old window ended
        # Archive the old window with plan info (skip invalid entries with reset_at=0)
        if current_7d["reset_at"] > 0:
            archived = {
                "reset_at": current_7d["reset_at"],
                "utilization": current_7d["utilization"],
                "recorded_at": current_7d["last_updated"],
            }
            if current_7d.get("plan"):
                archived["plan"] = current_7d["plan"]
            account["history"]["windows_7d"].append(archived)

    # Update current sessions with plan info and snapshots
    account["current"]["session_5h"] = {
        "reset_at": usage_data["5h_reset"],
        "utilization": usage_data["5h_utilization"],
        "last_updated": now,
    }
    if plan_info:
        account["current"]["session_5h"]["plan"] = plan_info
    if snapshots:
        # Store snapshots as list of [timestamp, utilization] for JSON
        account["current"]["session_5h"]["snapshots"] = [[t, u] for t, u in snapshots]

    account["current"]["window_7d"] = {
        "reset_at": usage_data["7d_reset"],
        "utilization": usage_data["7d_utilization"],
        "last_updated": now,
    }
    if plan_info:
        account["current"]["window_7d"]["plan"] = plan_info

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
    from waybar_utils import format_delta_short

    if reset_timestamp <= 0:
        return "0m"

    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()
    delta = reset_dt - now

    if delta.total_seconds() <= 0:
        return "0m"

    return format_delta_short(delta)


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


def format_plan_name(profile: Optional[Dict]) -> Optional[str]:
    """Format the plan name from profile data (without 'Claude' prefix)."""
    if not profile:
        return None
    org_type = profile.get("organization", {}).get("organization_type", "")
    tier = profile.get("organization", {}).get("rate_limit_tier", "")

    if not org_type:
        return None

    # Map organization_type to friendly name
    plan_names = {
        "claude_max": "Max",
        "claude_pro": "Pro",
        "claude_enterprise": "Enterprise",
        "claude_team": "Team",
    }
    plan = plan_names.get(
        org_type, org_type.replace("claude_", "").title() if org_type else ""
    )

    # Extract multiplier from tier (e.g., "default_claude_max_5x" -> "5x")
    multiplier = ""
    if tier:
        match = re.search(r"(\d+x)$", tier)
        if match:
            multiplier = f" {match.group(1)}"

    return f"{plan}{multiplier}" if plan else "Free"


def format_tooltip(
    data: Dict,
    last_check_time: Optional[datetime] = None,
    profile: Optional[Dict] = None,
    cred_source: Optional[str] = None,
    cred_is_fallback: bool = False,
    prefer_source: Optional[str] = None,
    usage_snapshots: Optional[list[tuple[float, float]]] = None,
) -> str:
    """Format the tooltip with usage information."""
    util_5h = data["5h_utilization"] * 100
    util_7d = data["7d_utilization"] * 100
    bar_5h = get_progress_bar(int(util_5h), width=BAR_WIDTH)
    bar_7d = get_progress_bar(int(util_7d), width=BAR_WIDTH)
    bar_5h_colored = get_progress_bar_colored(int(util_5h), width=BAR_WIDTH)
    bar_7d_colored = get_progress_bar_colored(int(util_7d), width=BAR_WIDTH)

    time_elapsed_5h = get_time_elapsed_percentage(data["5h_reset"], 5.0)
    time_elapsed_7d = get_time_elapsed_percentage(data["7d_reset"], 7 * 24.0)
    time_bar_5h = get_time_bar(int(time_elapsed_5h), width=BAR_WIDTH)
    time_bar_7d = get_time_bar(int(time_elapsed_7d), width=BAR_WIDTH)
    time_bar_5h_colored = get_time_bar_colored(int(time_elapsed_5h), width=BAR_WIDTH)
    time_bar_7d_colored = get_time_bar_colored(int(time_elapsed_7d), width=BAR_WIDTH)
    hourglass_5h = get_hourglass_icon(time_elapsed_5h)
    hourglass_7d = get_hourglass_icon(time_elapsed_7d)

    end_time_5h = format_end_time(data["5h_reset"])
    end_time_7d = format_end_time(data["7d_reset"])
    remaining_5h = format_reset_short(data["5h_reset"])
    remaining_7d = format_reset_short(data["7d_reset"])

    header_5h = f'   <b>5-hour session</b> <span color="{COLOR_SUBDUED}">{icons["bullet"]} {end_time_5h} (in {remaining_5h})</span>'
    header_7d = f'   <b>7-day window</b> <span color="{COLOR_SUBDUED}">{icons["bullet"]} {end_time_7d} (in {remaining_7d})</span>'

    # Build plain-text lines for width calculation, then markup lines for display
    # Build bar lines (plain text for width, markup for display)
    # Color percentages: use gradient color only if >85%, otherwise subdued
    usage_5h_pct_color = (
        _gradient_color(util_5h / 100) if util_5h > 85 else COLOR_SUBDUED
    )
    usage_7d_pct_color = (
        _gradient_color(util_7d / 100) if util_7d > 85 else COLOR_SUBDUED
    )
    time_5h_pct_color = (
        _time_gradient_color(time_elapsed_5h / 100)
        if time_elapsed_5h > 85
        else COLOR_SUBDUED
    )
    time_7d_pct_color = (
        _time_gradient_color(time_elapsed_7d / 100)
        if time_elapsed_7d > 85
        else COLOR_SUBDUED
    )

    bar_line_5h_plain = f"{icons['zap']}  {bar_5h} {util_5h:4.1f}%"
    bar_line_5h_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{icons["zap"]}</span>  {bar_5h_colored} <span color="{usage_5h_pct_color}">{util_5h:4.1f}%</span>'
    time_line_5h_plain = f"{hourglass_5h}  {time_bar_5h} {time_elapsed_5h:4.1f}%"
    time_line_5h_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{hourglass_5h}</span>  {time_bar_5h_colored} <span color="{time_5h_pct_color}">{time_elapsed_5h:4.1f}%</span>'

    bar_line_7d_plain = f"{icons['zap']}  {bar_7d} {util_7d:4.1f}%"
    bar_line_7d_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{icons["zap"]}</span>  {bar_7d_colored} <span color="{usage_7d_pct_color}">{util_7d:4.1f}%</span>'
    time_line_7d_plain = f"{hourglass_7d}  {time_bar_7d} {time_elapsed_7d:4.1f}%"
    time_line_7d_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{hourglass_7d}</span>  {time_bar_7d_colored} <span color="{time_7d_pct_color}">{time_elapsed_7d:4.1f}%</span>'

    # Build header plain text for width calculation
    header_5h_plain = (
        f"   5-hour session {icons['bullet']} {end_time_5h} (in {remaining_5h})"
    )
    header_7d_plain = (
        f"   7-day window {icons['bullet']} {end_time_7d} (in {remaining_7d})"
    )

    # Collect plain text lines for width calculation
    plain_lines = [
        "",
        header_5h_plain,
        bar_line_5h_plain,
        time_line_5h_plain,
        "",
        header_7d_plain,
        bar_line_7d_plain,
        time_line_7d_plain,
    ]

    # Footer with credential source, user info and last check time
    footer_parts = []
    if cred_source:
        if prefer_source is None:
            footer_parts.append(cred_source)
        elif cred_is_fallback:
            footer_parts.append(f"{cred_source} (fallback)")
        else:
            footer_parts.append(f"[{cred_source}]")
    if profile:
        email = profile.get("account", {}).get("email")
        if email:
            footer_parts.append(email)
    if last_check_time:
        footer_parts.append(f"checked {format_relative_time(last_check_time)}")
    footer = f" {icons['bullet']} ".join(footer_parts) if footer_parts else None

    plan_name = format_plan_name(profile)
    bullet = f'<span color="{COLOR_SUBDUED}">{icons["bullet"]}</span>'
    if plan_name:
        title_plain = (
            f"Claude {icons['bullet']} Usage Monitor {icons['bullet']} {plan_name} Plan"
        )
        title_markup = f"Claude {bullet} Usage Monitor {bullet} {plan_name} Plan"
    else:
        title_plain = f"Claude {icons['bullet']} Usage Monitor"
        title_markup = f"Claude {bullet} Usage Monitor"

    max_width = max(len(line) for line in plain_lines)
    # Center based on plain text width, then apply markup
    pad = max(0, max_width - len(title_plain))
    pad_left = pad // 2
    pad_right = pad - pad_left
    centered_title = " " * pad_left + title_markup + " " * pad_right

    # Build final markup output
    lines = []
    lines.append(f"<b>{centered_title}</b>")
    lines.append("")
    lines.append(header_5h)
    lines.append(bar_line_5h_markup)
    # Add usage timeline chart (between usage bar and time bar)
    buckets = calculate_usage_buckets(
        usage_snapshots or [], data["5h_reset"], BAR_WIDTH
    )
    top_row, bottom_row = render_usage_timeline_chart_colored(buckets, BAR_WIDTH)
    lines.append(f"   {top_row}")
    lines.append(f"   {bottom_row}")
    lines.append(time_line_5h_markup)
    time_labels_5h = render_5h_time_labels(data["5h_reset"], BAR_WIDTH)
    lines.append(f"   {time_labels_5h}")
    if data["5h_status"] != "allowed":
        lines.append(
            f'  Status: <span color="#FF7D90"><b>{data["5h_status"]}</b></span>'
        )
    lines.append("")

    lines.append(header_7d)
    lines.append(bar_line_7d_markup)
    # Add 7d usage timeline chart from session history (between usage bar and time bar)
    history = load_history()
    buckets_7d = calculate_7d_buckets_from_history(history, data["7d_reset"], BAR_WIDTH)
    top_row_7d, bottom_row_7d = render_usage_timeline_chart_colored(
        buckets_7d, BAR_WIDTH
    )
    lines.append(f"   {top_row_7d}")
    lines.append(f"   {bottom_row_7d}")
    lines.append(time_line_7d_markup)
    day_labels = render_7d_day_labels(data["7d_reset"], BAR_WIDTH)
    lines.append(f"   {day_labels}")
    if data["7d_status"] != "allowed":
        lines.append(
            f'  Status: <span color="#FF7D90"><b>{data["7d_status"]}</b></span>'
        )

    if data["status"] != "allowed":
        lines.append("")
        lines.append(
            f'Overall status: <span color="#FF7D90"><b>{data["status"]}</b></span>'
        )

    if footer:
        lines.append("")
        lines.append(f'<span color="{COLOR_SUBDUED}">{footer.center(max_width)}</span>')

    return "\n".join(lines)


def _interpolate_colors(colors: list[tuple[int, int, int]], position: float) -> str:
    """Interpolate through a list of evenly-spaced color stops.

    Duplicate a color to make it hold longer in the gradient.
    """
    position = max(0.0, min(1.0, position))
    n = len(colors)
    if n == 0:
        return "#FFFFFF"
    if n == 1:
        return f"#{colors[0][0]:02X}{colors[0][1]:02X}{colors[0][2]:02X}"

    scaled = position * (n - 1)
    i = min(int(scaled), n - 2)
    t = scaled - i
    c0, c1 = colors[i], colors[i + 1]
    r = int(c0[0] + (c1[0] - c0[0]) * t)
    g = int(c0[1] + (c1[1] - c0[1]) * t)
    b = int(c0[2] + (c1[2] - c0[2]) * t)
    return f"#{r:02X}{g:02X}{b:02X}"


def _gradient_color(position: float) -> str:
    """Return a hex color for a position 0.0-1.0 along the usage gradient.

    Colors are evenly distributed. Duplicate a color to hold it longer.
    """
    colors = [
        (0xDB, 0xFF, 0xB3),  # #DBFFB3
        (0xDB, 0xFF, 0xB3),
        (0xDB, 0xFF, 0xB3),
        (0xDB, 0xFF, 0xB3),
        (0xC4, 0xAE, 0x7A),  # #C4AE7A
        (0xC4, 0xAE, 0x7A),
        (0xF7, 0x95, 0x68),  # #F79568
        (0xF7, 0x95, 0x68),
        (0xED, 0x6E, 0x86),  # #ED6E86
    ]
    return _interpolate_colors(colors, position)


def get_progress_bar(percentage: int, width: int) -> str:
    """Convert percentage to Unicode progress bar (plain, no color)."""
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


def get_progress_bar_colored(percentage: int, width: int) -> str:
    """Convert percentage to Unicode progress bar with Pango color gradient on filled segments."""
    total_segments = width
    filled_segments = min(total_segments, percentage * total_segments // 100)

    parts = []
    for i in range(total_segments):
        is_filled = i < filled_segments
        if i == 0:
            char = (
                progress_chars["full_left"]
                if is_filled
                else progress_chars["empty_left"]
            )
        elif i == total_segments - 1:
            char = (
                progress_chars["full_right"]
                if is_filled
                else progress_chars["empty_right"]
            )
        else:
            char = (
                progress_chars["full_mid"] if is_filled else progress_chars["empty_mid"]
            )

        if is_filled:
            # Color based on this segment's position in the bar
            pos = i / max(total_segments - 1, 1)
            color = _gradient_color(pos)
            parts.append(f'<span color="{color}" alpha="70%">{char}</span>')
        else:
            parts.append(f'<span color="{COLOR_DIM}">{char}</span>')

    return "".join(parts)


def _time_gradient_color(position: float) -> str:
    """Return a hex color for a position 0.0-1.0 along the time gradient.

    Colors are evenly distributed across the gradient. Duplicate a color
    to make it hold longer.
    """
    colors = [
        (0xA5, 0x93, 0xEA),  # #A593EA
        (0xA5, 0x93, 0xEA),
        (0xA5, 0x93, 0xEA),
        (0xA5, 0x93, 0xEA),
        (0xA5, 0x93, 0xEA),
        (0xDA, 0xAC, 0xC5),  # #DAACC5
        (0xDA, 0xAC, 0xC5),
        (0xDA, 0xAC, 0xC5),
        (0xF5, 0x94, 0x67),  # #F59467
        (0xF5, 0x94, 0x67),
        (0xEF, 0x6F, 0x88),  # #EF6F88
    ]
    return _interpolate_colors(colors, position)


def get_time_bar(percentage: int, width: int) -> str:
    """Convert percentage to simple Unicode progress bar using ▰▱ characters (plain)."""
    filled_segments = min(width, round(percentage * width / 100))
    empty_segments = width - filled_segments
    return "▰" * filled_segments + "▱" * empty_segments


def get_time_bar_colored(percentage: int, width: int) -> str:
    """Convert percentage to Unicode time bar with Pango color gradient."""
    filled_segments = min(width, round(percentage * width / 100))
    parts = []
    for i in range(width):
        is_filled = i < filled_segments
        char = "▰" if is_filled else "▱"
        if is_filled:
            pos = i / max(width - 1, 1)
            color = _time_gradient_color(pos)
            parts.append(f'<span color="{color}" alpha="70%">{char}</span>')
        else:
            parts.append(f'<span color="{COLOR_DIM}">{char}</span>')
    return "".join(parts)


def calculate_usage_buckets(
    snapshots: list[tuple[float, float]], reset_time: int, width: int
) -> list[float]:
    """Calculate per-bucket usage deltas from snapshots.

    Args:
        snapshots: List of (timestamp, utilization) tuples, utilization is 0.0-1.0
        reset_time: Unix timestamp when the 5h session resets
        width: Number of buckets (chart width)

    Returns:
        List of bucket values, normalized so max bucket = 1.0
    """
    if not snapshots or width <= 0 or reset_time <= 0:
        return [0.0] * width

    session_start = reset_time - 5 * 3600
    bucket_duration = 5 * 3600 / width
    buckets = [0.0] * width

    # Calculate deltas between consecutive snapshots and assign to buckets
    for i in range(1, len(snapshots)):
        t_prev, u_prev = snapshots[i - 1]
        t_curr, u_curr = snapshots[i]
        delta = u_curr - u_prev

        # Skip negative deltas (shouldn't happen, but defensive)
        if delta <= 0:
            continue

        # Assign delta to the bucket where t_curr falls
        bucket_idx = int((t_curr - session_start) / bucket_duration)
        bucket_idx = max(0, min(width - 1, bucket_idx))
        buckets[bucket_idx] += delta

    # Normalize so max bucket = 1.0
    max_val = max(buckets) if buckets else 0
    if max_val > 0:
        buckets = [v / max_val for v in buckets]

    return buckets


def calculate_7d_buckets_from_history(
    history: Dict, reset_time_7d: int, width: int
) -> list[float]:
    """Calculate per-bucket usage from 5h session history for the 7d window.

    Each 5h session's utilization represents the total usage in that period,
    so we can directly map sessions to buckets.

    Args:
        history: The full history dict from load_history()
        reset_time_7d: Unix timestamp when the 7d window resets
        width: Number of buckets (chart width)

    Returns:
        List of bucket values, normalized so max bucket = 1.0
    """
    if width <= 0 or reset_time_7d <= 0:
        return [0.0] * width

    window_start = reset_time_7d - 7 * 24 * 3600
    bucket_duration = 7 * 24 * 3600 / width
    buckets = [0.0] * width

    # Get the active account's session history
    active_account = history.get("active_account")
    if not active_account:
        return [0.0] * width

    account = history.get("accounts", {}).get(active_account, {})
    sessions_5h = account.get("history", {}).get("sessions_5h", [])

    # Also include the current session if it exists
    current_5h = account.get("current", {}).get("session_5h")

    # Collect all sessions that fall within the 7d window
    all_sessions = []
    for session in sessions_5h:
        reset_at = session.get("reset_at", 0)
        utilization = session.get("utilization", 0)
        if reset_at > window_start:
            # Use the middle of the session for bucketing (reset_at - 2.5h)
            session_mid = reset_at - 2.5 * 3600
            all_sessions.append((session_mid, utilization))

    # Add current session (use its last_updated as the time reference)
    if current_5h:
        last_updated = current_5h.get("last_updated", 0)
        utilization = current_5h.get("utilization", 0)
        if last_updated > window_start:
            all_sessions.append((last_updated, utilization))

    # Map sessions to buckets
    for session_time, utilization in all_sessions:
        bucket_idx = int((session_time - window_start) / bucket_duration)
        bucket_idx = max(0, min(width - 1, bucket_idx))
        # If multiple sessions fall in same bucket, use the max utilization
        buckets[bucket_idx] = max(buckets[bucket_idx], utilization)

    # Normalize so max bucket = 1.0
    max_val = max(buckets) if buckets else 0
    if max_val > 0:
        buckets = [v / max_val for v in buckets]

    return buckets


def render_usage_timeline_chart(buckets: list[float], width: int) -> tuple[str, str]:
    """Render a 2-row usage timeline bar chart.

    Args:
        buckets: List of normalized bucket values (0.0-1.0)
        width: Chart width (should match len(buckets))

    Returns:
        Tuple of (top_row, bottom_row) strings
    """
    # Block characters for vertical bars (8 levels)
    blocks = "▁▂▃▄▅▆▇█"

    top_row = []
    bottom_row = []

    for i, value in enumerate(buckets):
        # Convert 0.0-1.0 to 0-16 levels
        level = int(value * 16)
        level = max(0, min(16, level))

        if level == 0:
            bottom_char = " "
            top_char = " "
        elif level <= 8:
            # Bottom row only (levels 1-8)
            bottom_char = blocks[level - 1]
            top_char = " "
        else:
            # Bottom full, top row fills (levels 9-16)
            bottom_char = "█"
            top_char = blocks[level - 9]

        bottom_row.append(bottom_char)
        top_row.append(top_char)

    return ("".join(top_row), "".join(bottom_row))


def render_5h_time_labels(reset_time_5h: int, width: int) -> str:
    """Render time labels for the 5h chart: start, midpoint, end.

    Args:
        reset_time_5h: Unix timestamp when the 5h session resets
        width: Chart width (number of buckets)

    Returns:
        String with times at left, center, right, colored subdued
    """
    if reset_time_5h <= 0 or width <= 0:
        return ""

    session_start = reset_time_5h - 5 * 3600
    session_mid = reset_time_5h - 2.5 * 3600
    session_end = reset_time_5h

    # Format times
    start_dt = datetime.fromtimestamp(session_start, tz=timezone.utc).astimezone()
    mid_dt = datetime.fromtimestamp(session_mid, tz=timezone.utc).astimezone()
    end_dt = datetime.fromtimestamp(session_end, tz=timezone.utc).astimezone()

    start_str = start_dt.strftime("%H:%M")
    mid_str = mid_dt.strftime("%H:%M")
    end_str = end_dt.strftime("%H:%M")

    # Build the label line: start left-aligned, mid centered, end right-aligned
    chars = [" "] * width

    # Place start time at left
    for i, c in enumerate(start_str):
        if i < width:
            chars[i] = c

    # Place mid time at center
    mid_pos = (width - len(mid_str)) // 2
    for i, c in enumerate(mid_str):
        if mid_pos + i < width:
            chars[mid_pos + i] = c

    # Place end time at right
    end_pos = width - len(end_str)
    for i, c in enumerate(end_str):
        if end_pos + i < width:
            chars[end_pos + i] = c

    label_line = "".join(chars)
    return f'<span color="{COLOR_SUBDUED}">{label_line}</span>'


def render_7d_day_labels(reset_time_7d: int, width: int) -> str:
    """Render day-of-week labels for the 7d chart.

    Args:
        reset_time_7d: Unix timestamp when the 7d window resets
        width: Chart width (number of buckets)

    Returns:
        String with day letters positioned at midnight boundaries, colored subdued
    """
    if reset_time_7d <= 0 or width <= 0:
        return ""

    window_start = reset_time_7d - 7 * 24 * 3600
    window_duration = 7 * 24 * 3600
    bucket_duration = window_duration / width

    # 3-letter day names (Monday = 0 to match Python's weekday())
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    # Build the label line
    chars = [" "] * width

    # Find the first midnight at or after window_start
    start_dt = datetime.fromtimestamp(window_start, tz=timezone.utc).astimezone()
    # Round up to next midnight
    if start_dt.hour > 0 or start_dt.minute > 0 or start_dt.second > 0:
        next_midnight = start_dt.replace(
            hour=0, minute=0, second=0, microsecond=0
        ) + timedelta(days=1)
    else:
        next_midnight = start_dt

    # Place day names at each midnight
    current_midnight = next_midnight
    window_end = reset_time_7d
    while current_midnight.timestamp() < window_end:
        # Calculate bucket index for this midnight
        time_offset = current_midnight.timestamp() - window_start
        bucket_idx = int(time_offset / bucket_duration)

        if 0 <= bucket_idx < width:
            dow = current_midnight.weekday()  # Monday = 0, Sunday = 6
            name = day_names[dow]
            for j, c in enumerate(name):
                if bucket_idx + j < width:
                    chars[bucket_idx + j] = c

        # Move to next day
        current_midnight += timedelta(days=1)

    label_line = "".join(chars)
    return f'<span color="{COLOR_SUBDUED}">{label_line}</span>'


def render_usage_timeline_chart_colored(
    buckets: list[float], width: int
) -> tuple[str, str]:
    """Render a 2-row usage timeline bar chart with Pango color gradient.

    Args:
        buckets: List of normalized bucket values (0.0-1.0)
        width: Chart width (should match len(buckets))

    Returns:
        Tuple of (top_row_markup, bottom_row_markup) strings
    """
    blocks = "▁▂▃▄▅▆▇█"

    top_parts = []
    bottom_parts = []

    for i, value in enumerate(buckets):
        level = int(value * 16)
        level = max(0, min(16, level))

        # Color based on position in timeline (left=start, right=end)
        pos = i / max(width - 1, 1)
        color = _time_gradient_color(pos)

        if level == 0:
            bottom_parts.append(" ")
            top_parts.append(" ")
        elif level <= 8:
            bottom_char = blocks[level - 1]
            bottom_parts.append(f'<span color="{color}">{bottom_char}</span>')
            top_parts.append(" ")
        else:
            bottom_char = "█"
            top_char = blocks[level - 9]
            bottom_parts.append(f'<span color="{color}">{bottom_char}</span>')
            top_parts.append(f'<span color="{color}">{top_char}</span>')

    # Wrap each row in a span with background color (dim at 25% opacity)
    bg_color = f"{COLOR_DIM}40"
    top_row = f'<span bgcolor="{bg_color}">{"".join(top_parts)}</span>'
    bottom_row = f'<span bgcolor="{bg_color}">{"".join(bottom_parts)}</span>'

    return (top_row, bottom_row)


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
    """Format reset timestamp to 'ends ...' phrase like 'ends at 14:00' or 'ends Monday at 14:00'."""
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
        return f"ends {reset_dt.strftime('%A')} at {time_str}"


def get_compact_usage_bar(percentage: int, width: int = 10) -> str:
    """Get a compact usage progress bar (styled like tooltip usage bar)."""
    return get_progress_bar(percentage, width)


def get_compact_time_bar(percentage: int, width: int = 10) -> str:
    """Get a compact time progress bar (styled like tooltip time bar)."""
    return get_time_bar(percentage, width)


def format_waybar_output(
    data: Optional[Dict],
    last_check_time: Optional[datetime] = None,
    show_alternate: bool = False,
    has_token: bool = True,
    profile: Optional[Dict] = None,
    cred_source: Optional[str] = None,
    cred_is_fallback: bool = False,
    prefer_source: Optional[str] = None,
    display_mode: str = "normal",
    usage_snapshots: Optional[list[tuple[float, float]]] = None,
) -> Optional[Dict]:
    """Format output for Waybar.

    Display modes:
    - compact: alternates between "{icon} {pct}%" and "{icon} {time}"
    - normal: "{icon} {pct}% ({time})"
    - expanded: "{icon} {bar} {pct}%" alternating bar between usage and time elapsed
    """
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
    is_5h_active = data["representative_claim"] == "five_hour"
    if is_5h_active:
        primary_util = data["5h_utilization"]
        reset_time = data["5h_reset"]
        time_elapsed_pct = get_time_elapsed_percentage(reset_time, 5.0)
    else:
        primary_util = data["7d_utilization"]
        reset_time = data["7d_reset"]
        time_elapsed_pct = get_time_elapsed_percentage(reset_time, 7 * 24.0)

    percentage = int(primary_util * 100)
    reset_short = format_reset_short(reset_time)

    # Determine CSS class based on status and usage percentage
    # Check if any status is not allowed - that's critical
    if (
        data["status"] != "allowed"
        or data["5h_status"] != "allowed"
        or data["7d_status"] != "allowed"
    ):
        css_class = "critical"
    elif not is_5h_active:
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
    tooltip = format_tooltip(
        data,
        last_check_time,
        profile,
        cred_source,
        cred_is_fallback,
        prefer_source,
        usage_snapshots,
    )

    # Format text based on display mode
    if display_mode == "compact":
        if show_alternate and is_5h_active:
            text = f"{icons['zap']} {reset_short}"
        else:
            text = f"{icons['zap']} {percentage}%"
    elif display_mode == "normal":
        hourglass = get_hourglass_icon(time_elapsed_pct)
        text = f"{icons['zap']} {percentage}%  {hourglass} {int(time_elapsed_pct)}%"
    elif display_mode == "expanded":
        if show_alternate and is_5h_active:
            hourglass = get_hourglass_icon(time_elapsed_pct)
            bar = get_compact_time_bar(int(time_elapsed_pct))
            text = f"{icons['zap']} {bar}  {hourglass} {int(time_elapsed_pct):2d}%"
        else:
            bar = get_compact_usage_bar(percentage)
            text = f"{icons['zap']} {bar}  {icons['zap']} {percentage:2d}%"
    else:
        text = f"{icons['zap']} {percentage}%"

    return {
        "text": text,
        "tooltip": tooltip,
        "percentage": percentage,
        "class": css_class,
    }


def monitor(prefer_source_override: Optional[str] = None):
    """Main monitoring loop."""
    # Check if another instance is already running
    existing_pid = check_existing_instance()
    if existing_pid:
        print(
            f"Another instance is already running (PID {existing_pid})", file=sys.stderr
        )
        sys.exit(1)

    last_check_time: Optional[datetime] = None
    last_output_json: Optional[str] = None
    usage_data: Optional[Dict] = None
    profile_data: Optional[Dict] = None
    current_token: Optional[str] = None
    cred_source: Optional[str] = None
    cred_is_fallback: bool = False
    has_token: bool = True
    check_thread: Optional[threading.Thread] = None
    check_result: list = [(None, None, None, None, False, True)]
    check_lock = threading.Lock()
    expired_5h_triggered: bool = False
    expired_7d_triggered: bool = False
    last_check_start: float = 0.0
    signal_received: list = [False]  # Use list for mutability in signal handler
    # Track usage snapshots for timeline chart - load from history if available
    loaded_snapshots, loaded_reset = load_current_snapshots()
    usage_snapshots: list[tuple[float, float]] = loaded_snapshots
    last_5h_reset: int = loaded_reset

    def get_prefer_source() -> Optional[str]:
        """Get prefer_source from override or config."""
        if prefer_source_override:
            return prefer_source_override
        history = load_history()
        return history.get("config", {}).get("prefer_source")

    def get_display_mode() -> str:
        """Get display_mode from config."""
        history = load_history()
        return history.get("config", {}).get("display_mode", "normal")

    def handle_refresh_signal(_signum, _frame):
        """Handle SIGUSR1 to trigger refresh."""
        signal_received[0] = True

    def handle_exit_signal(_signum, _frame):
        """Handle SIGTERM/SIGINT to clean up and exit."""
        clear_pid()
        sys.exit(0)

    signal.signal(signal.SIGUSR1, handle_refresh_signal)
    signal.signal(signal.SIGTERM, handle_exit_signal)
    signal.signal(signal.SIGINT, handle_exit_signal)

    def run_check_async(
        result_container: list, lock: threading.Lock, prev_token: Optional[str]
    ):
        try:
            result = fetch_usage_data(prev_token, get_prefer_source())
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Background check error: {e}", file=sys.stderr)

    def start_check():
        nonlocal check_thread, last_check_start
        check_thread = threading.Thread(
            target=run_check_async,
            args=(check_result, check_lock, current_token),
            daemon=True,
        )
        check_thread.start()
        last_check_start = time.time()

    # Save PID and register cleanup
    save_pid()
    import atexit

    atexit.register(clear_pid)

    # Start initial check immediately
    start_check()

    try:
        while True:
            current_time = time.time()

            # Check if signal received (triggers immediate refresh)
            if signal_received[0]:
                signal_received[0] = False
                if check_thread is None or not check_thread.is_alive():
                    start_check()

            # Check if background thread completed
            if check_thread is not None and not check_thread.is_alive():
                with check_lock:
                    if check_result[0] is not None:
                        data, profile, token, source, is_fallback, token_valid = (
                            check_result[0]
                        )
                        has_token = token_valid
                        if data is not None:
                            # Check if 5h session reset (new session started)
                            if data["5h_reset"] != last_5h_reset:
                                usage_snapshots.clear()
                                last_5h_reset = data["5h_reset"]
                            # Record snapshot for timeline chart
                            usage_snapshots.append(
                                (current_time, data["5h_utilization"])
                            )
                            usage_data = data
                            current_token = token
                            cred_source = source
                            cred_is_fallback = is_fallback
                            # Only update profile if we got new one (token changed)
                            if profile is not None:
                                profile_data = profile
                            # Reset expiry triggers when we get new data
                            expired_5h_triggered = False
                            expired_7d_triggered = False
                            # Update history with profile info and snapshots
                            update_history(
                                data,
                                profile if profile else profile_data,
                                usage_snapshots,
                            )
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

            # Determine alternation cycle: 15s primary, 15s alternate
            cycle_position = int(current_time) % 30
            show_alternate = cycle_position >= 15

            # Format and output
            prefer_source = get_prefer_source()
            display_mode = get_display_mode()
            output = format_waybar_output(
                usage_data,
                last_check_time,
                show_alternate,
                has_token,
                profile_data,
                cred_source,
                cred_is_fallback,
                prefer_source,
                display_mode,
                usage_snapshots,
            )
            if output:
                output_json = json.dumps(output)
                if output_json != last_output_json:
                    print(output_json, flush=True)
                    last_output_json = output_json

            time.sleep(OUTPUT_INTERVAL)

    except KeyboardInterrupt:
        clear_pid()
        sys.exit(0)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Claude usage monitor for Waybar")

    # Runtime preference override (for the monitor)
    runtime_group = parser.add_mutually_exclusive_group()
    runtime_group.add_argument(
        "--prefer-cc",
        action="store_true",
        help="Prefer Claude Code credentials (falls back to OpenCode)",
    )
    runtime_group.add_argument(
        "--prefer-oc",
        action="store_true",
        help="Prefer OpenCode credentials (falls back to Claude Code)",
    )

    # One-shot commands to configure and signal running instance
    action_group = parser.add_mutually_exclusive_group()
    action_group.add_argument(
        "--set-prefer-cc",
        action="store_true",
        help="Set preference to Claude Code and signal refresh",
    )
    action_group.add_argument(
        "--set-prefer-oc",
        action="store_true",
        help="Set preference to OpenCode and signal refresh",
    )
    action_group.add_argument(
        "--set-prefer-auto",
        action="store_true",
        help="Set preference to auto (try Claude Code first) and signal refresh",
    )
    action_group.add_argument(
        "--refresh",
        action="store_true",
        help="Signal running instance to refresh",
    )
    action_group.add_argument(
        "--set-mode-compact",
        action="store_true",
        help="Set display mode to compact",
    )
    action_group.add_argument(
        "--set-mode-normal",
        action="store_true",
        help="Set display mode to normal",
    )
    action_group.add_argument(
        "--set-mode-expanded",
        action="store_true",
        help="Set display mode to expanded",
    )
    action_group.add_argument(
        "--cycle-mode-up",
        action="store_true",
        help="Cycle display mode: compact -> normal -> expanded -> compact",
    )
    action_group.add_argument(
        "--cycle-mode-down",
        action="store_true",
        help="Cycle display mode: compact <- normal <- expanded <- compact",
    )

    args = parser.parse_args()

    # Handle one-shot config commands
    if args.set_prefer_cc:
        set_config("prefer_source", "cc")
        print("Set preference to Claude Code")
        return
    elif args.set_prefer_oc:
        set_config("prefer_source", "oc")
        print("Set preference to OpenCode")
        return
    elif args.set_prefer_auto:
        set_config("prefer_source", None)
        print("Set preference to auto")
        return
    elif args.refresh:
        if signal_running_instance():
            print("Signaled running instance to refresh")
        else:
            print("No running instance found")
        return
    elif args.set_mode_compact:
        set_config("display_mode", "compact")
        print("Set display mode to compact")
        return
    elif args.set_mode_normal:
        set_config("display_mode", "normal")
        print("Set display mode to normal")
        return
    elif args.set_mode_expanded:
        set_config("display_mode", "expanded")
        print("Set display mode to expanded")
        return
    elif args.cycle_mode_up:
        history = load_history()
        current = history.get("config", {}).get("display_mode", "normal")
        modes = ["compact", "normal", "expanded"]
        next_mode = modes[(modes.index(current) + 1) % len(modes)]
        set_config("display_mode", next_mode)
        print(f"Display mode: {next_mode}")
        return
    elif args.cycle_mode_down:
        history = load_history()
        current = history.get("config", {}).get("display_mode", "normal")
        modes = ["compact", "normal", "expanded"]
        next_mode = modes[(modes.index(current) - 1) % len(modes)]
        set_config("display_mode", next_mode)
        print(f"Display mode: {next_mode}")
        return

    # Start monitor with optional runtime override
    prefer_source = None
    if args.prefer_cc:
        prefer_source = "cc"
    elif args.prefer_oc:
        prefer_source = "oc"

    monitor(prefer_source)


if __name__ == "__main__":
    main()
