"""History file management for Claude usage monitor."""

import json
import os
import signal
import sys
import time
from typing import Any, Dict, Optional

from .constants import HISTORY_FILE


def empty_account_data() -> Dict[str, Any]:
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


def load_history() -> Dict[str, Any]:
    """Load usage history and config from disk."""
    empty: Dict[str, Any] = {
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


def save_history(history: Dict[str, Any]) -> None:
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


def set_config(key: str, value: Any) -> None:
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
    usage_data: Dict[str, Any],
    profile: Optional[Dict[str, Any]] = None,
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
            archived: Dict[str, Any] = {
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
