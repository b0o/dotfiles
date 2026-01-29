"""Rendering functions for bars, charts, and labels."""

import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from .constants import COLOR_DIM, COLOR_SUBDUED, HOURGLASS_FRAMES, PROGRESS_CHARS


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
            PROGRESS_CHARS["empty_left"]
            + PROGRESS_CHARS["empty_mid"] * middle_segments
            + PROGRESS_CHARS["empty_right"]
        )
    elif filled_segments >= total_segments:
        # All full
        bar = (
            PROGRESS_CHARS["full_left"]
            + PROGRESS_CHARS["full_mid"] * middle_segments
            + PROGRESS_CHARS["full_right"]
        )
    elif filled_segments == 1:
        # Only left segment filled
        bar = (
            PROGRESS_CHARS["full_left"]
            + PROGRESS_CHARS["empty_mid"] * middle_segments
            + PROGRESS_CHARS["empty_right"]
        )
    elif filled_segments == total_segments - 1:
        # All but right segment filled
        bar = (
            PROGRESS_CHARS["full_left"]
            + PROGRESS_CHARS["full_mid"] * middle_segments
            + PROGRESS_CHARS["empty_right"]
        )
    else:
        # Partial fill in the middle
        filled_middle = filled_segments - 1
        empty_middle = middle_segments - filled_middle
        bar = (
            PROGRESS_CHARS["full_left"]
            + PROGRESS_CHARS["full_mid"] * filled_middle
            + PROGRESS_CHARS["empty_mid"] * empty_middle
            + PROGRESS_CHARS["empty_right"]
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
                PROGRESS_CHARS["full_left"]
                if is_filled
                else PROGRESS_CHARS["empty_left"]
            )
        elif i == total_segments - 1:
            char = (
                PROGRESS_CHARS["full_right"]
                if is_filled
                else PROGRESS_CHARS["empty_right"]
            )
        else:
            char = (
                PROGRESS_CHARS["full_mid"] if is_filled else PROGRESS_CHARS["empty_mid"]
            )

        if is_filled:
            # Color based on this segment's position in the bar
            pos = i / max(total_segments - 1, 1)
            color = _gradient_color(pos)
            parts.append(f'<span color="{color}" alpha="70%">{char}</span>')
        else:
            parts.append(f'<span color="{COLOR_DIM}">{char}</span>')

    return "".join(parts)


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


def get_hourglass_icon(elapsed_percentage: float) -> str:
    """Get the appropriate hourglass icon based on elapsed percentage."""
    num_frames = len(HOURGLASS_FRAMES)
    frame_index = int(elapsed_percentage * num_frames / 100)
    # Clamp to valid range
    frame_index = max(0, min(num_frames - 1, frame_index))
    return HOURGLASS_FRAMES[frame_index]


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


def get_compact_usage_bar(percentage: int, width: int = 10) -> str:
    """Get a compact usage progress bar (styled like tooltip usage bar)."""
    return get_progress_bar(percentage, width)


def get_compact_time_bar(percentage: int, width: int = 10) -> str:
    """Get a compact time progress bar (styled like tooltip time bar)."""
    return get_time_bar(percentage, width)


# Chart rendering functions


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
    history: Dict[str, Any], reset_time_7d: int, width: int
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
