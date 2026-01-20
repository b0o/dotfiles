"""Centralized notification system for the daemon."""

import subprocess
from enum import IntEnum


class NotifyLevel(IntEnum):
    """Notification level configuration (ordered by verbosity)."""

    NONE = 0  # No notifications
    ERROR = 1  # Only errors
    WARNING = 2  # Errors + warnings
    ALL = 3  # All notifications (errors + warnings + info)


# Global notification level, set by config
_notify_level: NotifyLevel = NotifyLevel.ALL


def set_notify_level(level: NotifyLevel) -> None:
    """Set the global notification level."""
    global _notify_level
    _notify_level = level


def get_notify_level() -> NotifyLevel:
    """Get the current notification level."""
    return _notify_level


def notify_error(title: str, message: str) -> None:
    """Send an error notification (shown if level >= ERROR)."""
    if _notify_level < NotifyLevel.ERROR:
        return
    _send_notification(title, message, urgency="critical")


def notify_warning(title: str, message: str) -> None:
    """Send a warning notification (shown if level >= WARNING)."""
    if _notify_level < NotifyLevel.WARNING:
        return
    _send_notification(title, message, urgency="normal", timeout_ms=5000)


def notify_info(title: str, message: str, timeout_ms: int = 2000) -> None:
    """Send an info notification (shown only if level is ALL)."""
    if _notify_level < NotifyLevel.ALL:
        return
    _send_notification(title, message, urgency="low", timeout_ms=timeout_ms)


def _send_notification(
    title: str,
    message: str,
    *,
    urgency: str | None = None,
    timeout_ms: int | None = None,
) -> None:
    """Send a notification via notify-send."""
    try:
        cmd = ["notify-send", "-a", "niri-tools"]
        if urgency:
            cmd.extend(["-u", urgency])
        if timeout_ms:
            cmd.extend(["-t", str(timeout_ms)])
        cmd.extend([title, message])
        subprocess.run(cmd, check=False)
    except Exception:
        pass
