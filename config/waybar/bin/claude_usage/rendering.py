"""Rendering functions for bars, charts, and labels."""

import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from .constants import (
    CHART_HEIGHT,
    COLOR_DIM,
    COLOR_SHADOW,
    COLOR_SUBDUED,
    HOURGLASS_FRAMES,
    PROGRESS_CHARS,
)


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


def _chart_gradient_color(position: float) -> str:
    """Return a hex color for a position 0.0-1.0 along the chart gradient.

    Purple scale with increasing saturation/brightness for timeline charts.
    """
    colors = [
        (0x4A, 0x3A, 0x5C),  # #4A3A5C - dark muted purple
        (0x5D, 0x4A, 0x72),  # #5D4A72
        (0x72, 0x5A, 0x8C),  # #725A8C
        (0x87, 0x6A, 0xA6),  # #876AA6
        (0x9D, 0x7A, 0xC2),  # #9D7AC2
        (0xB3, 0x8A, 0xDE),  # #B38ADE
        (0xC9, 0x9A, 0xFA),  # #C99AFA - bright saturated purple
    ]
    return _interpolate_colors(colors, position)


def _cumulative_gradient_color(position: float) -> str:
    """Return a hex color for a position 0.0-1.0 along the cumulative chart gradient.

    Orange scale with increasing saturation/brightness for cumulative usage charts.
    """
    colors = [
        (0x7B, 0x49, 0x37),  # #7B4937 - dark burnt orange
        (0x9A, 0x55, 0x3B),  # #9A553B
        (0xB5, 0x5A, 0x3D),  # #B55A3D
        (0xC3, 0x61, 0x42),  # #C36142
        (0xC6, 0x61, 0x3F),  # #C6613F
        (0xD0, 0x6C, 0x4A),  # #D06C4A
        (0xD9, 0x77, 0x57),  # #D97757 - bright orange
        (0xD9, 0x6A, 0x7A),  # #D96A7A
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
) -> tuple[list[float], list[float]]:
    """Calculate per-bucket usage deltas from snapshots.

    Args:
        snapshots: List of (timestamp, utilization) tuples, utilization is 0.0-1.0
        reset_time: Unix timestamp when the 5h session resets
        width: Number of buckets (chart width)

    Returns:
        Tuple of (normalized_buckets, raw_buckets) where:
        - normalized_buckets: values scaled so max bucket = 1.0 (for bar height)
        - raw_buckets: cumulative utilization at each bucket (for color)
    """
    if not snapshots or width <= 0 or reset_time <= 0:
        return ([0.0] * width, [0.0] * width)

    session_start = reset_time - 5 * 3600
    bucket_duration = 5 * 3600 / width
    delta_buckets = [0.0] * width

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
        delta_buckets[bucket_idx] += delta

    # Calculate cumulative utilization for each bucket (for coloring)
    # This represents the total usage up to and including that bucket
    raw_buckets = [0.0] * width
    cumulative = 0.0
    for i, delta in enumerate(delta_buckets):
        cumulative += delta
        raw_buckets[i] = cumulative

    # Normalize deltas so max bucket = 1.0 (for bar height)
    max_val = max(delta_buckets) if delta_buckets else 0
    if max_val > 0:
        normalized_buckets = [v / max_val for v in delta_buckets]
    else:
        normalized_buckets = [0.0] * width

    return (normalized_buckets, raw_buckets)


def calculate_7d_buckets_from_history(
    history: Dict[str, Any], reset_time_7d: int, width: int
) -> tuple[list[float], list[float]]:
    """Calculate per-bucket usage from 5h session history for the 7d window.

    Each 5h session's utilization represents the total usage in that period,
    so we can directly map sessions to buckets.

    Args:
        history: The full history dict from load_history()
        reset_time_7d: Unix timestamp when the 7d window resets
        width: Number of buckets (chart width)

    Returns:
        Tuple of (normalized_buckets, raw_buckets) where:
        - normalized_buckets: values scaled so max bucket = 1.0 (for bar height)
        - raw_buckets: actual utilization values 0.0-1.0 (for color)
    """
    if width <= 0 or reset_time_7d <= 0:
        return ([0.0] * width, [0.0] * width)

    window_start = reset_time_7d - 7 * 24 * 3600
    bucket_duration = 7 * 24 * 3600 / width
    raw_buckets = [0.0] * width

    # Get the active account's session history
    active_account = history.get("active_account")
    if not active_account:
        return ([0.0] * width, [0.0] * width)

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

    # Map sessions to buckets - raw_buckets stores actual utilization (0.0-1.0)
    for session_time, utilization in all_sessions:
        bucket_idx = int((session_time - window_start) / bucket_duration)
        bucket_idx = max(0, min(width - 1, bucket_idx))
        # If multiple sessions fall in same bucket, use the max utilization
        raw_buckets[bucket_idx] = max(raw_buckets[bucket_idx], utilization)

    # Normalize so max bucket = 1.0 (for bar height display)
    max_val = max(raw_buckets) if raw_buckets else 0
    if max_val > 0:
        normalized_buckets = [v / max_val for v in raw_buckets]
    else:
        normalized_buckets = [0.0] * width

    return (normalized_buckets, raw_buckets)


def render_usage_timeline_chart_colored(
    buckets: list[float], width: int, raw_buckets: list[float] | None = None
) -> list[str]:
    """Render a multi-row usage timeline bar chart with Pango color gradient.

    Args:
        buckets: List of normalized bucket values (0.0-1.0) for bar height
        width: Chart width (should match len(buckets))
        raw_buckets: Optional list of raw utilization values (0.0-1.0) for color.
                     If provided, color is based on absolute usage, not relative height.

    Returns:
        List of row markup strings (top to bottom), length = CHART_HEIGHT
    """
    blocks = "▁▂▃▄▅▆▇█"
    max_level = CHART_HEIGHT * 8

    # Initialize row parts (top to bottom)
    row_parts: list[list[str]] = [[] for _ in range(CHART_HEIGHT)]

    for i, value in enumerate(buckets):
        level = int(value * max_level)
        level = max(0, min(max_level, level))

        # Color based on absolute utilization if raw_buckets provided, else normalized value
        color_value = raw_buckets[i] if raw_buckets else value
        color = _chart_gradient_color(color_value)

        # Fill rows from bottom (index CHART_HEIGHT-1) to top (index 0)
        for row in range(CHART_HEIGHT):
            # Row 0 is top, row CHART_HEIGHT-1 is bottom
            # Bottom row covers levels 1-8, next row 9-16, etc.
            row_from_bottom = CHART_HEIGHT - 1 - row
            row_min_level = row_from_bottom * 8 + 1
            row_max_level = (row_from_bottom + 1) * 8

            if level < row_min_level:
                # Level doesn't reach this row
                row_parts[row].append(" ")
            elif level >= row_max_level:
                # Level fills this row completely
                row_parts[row].append(f'<span color="{color}">█</span>')
            else:
                # Partial fill in this row
                partial = level - row_min_level + 1
                char = blocks[partial - 1]
                row_parts[row].append(f'<span color="{color}">{char}</span>')

    # Wrap each row in a span with background color (dim at 25% opacity)
    bg_color = f"{COLOR_DIM}40"
    rows = [
        f'<span bgcolor="{bg_color}">{"".join(parts)}</span>' for parts in row_parts
    ]

    return rows


def calculate_cumulative_buckets(
    snapshots: list[tuple[float, float]], reset_time: int, width: int
) -> tuple[list[float], int]:
    """Calculate cumulative usage at each bucket from snapshots.

    The snapshots already contain cumulative utilization values (0.0-1.0).
    Buckets after current time are set to 0 (no data yet).

    Args:
        snapshots: List of (timestamp, utilization) tuples, utilization is 0.0-1.0
        reset_time: Unix timestamp when the 5h session resets
        width: Number of buckets (chart width)

    Returns:
        Tuple of (buckets, current_index) where:
        - buckets: List of cumulative utilization values (0.0-1.0) at each bucket
        - current_index: Index of the last bucket with actual data (-1 if no data)
    """
    if not snapshots or width <= 0 or reset_time <= 0:
        return ([0.0] * width, -1)

    now = time.time()
    session_start = reset_time - 5 * 3600
    bucket_duration = 5 * 3600 / width
    buckets = [0.0] * width
    current_index = -1

    # Sort snapshots by timestamp
    sorted_snapshots = sorted(snapshots, key=lambda x: x[0])

    # For each bucket, find the utilization at that point in time
    # Buckets in the future (after now) stay at 0
    for i in range(width):
        bucket_end = session_start + (i + 1) * bucket_duration
        if bucket_end > now:
            # Future bucket - no data yet
            break
        # Find the last snapshot before or at bucket_end
        last_util = 0.0
        for ts, util in sorted_snapshots:
            if ts <= bucket_end:
                last_util = util
            else:
                break
        buckets[i] = last_util
        current_index = i

    return (buckets, current_index)


def calculate_cumulative_7d_buckets(
    history: Dict[str, Any], reset_time_7d: int, width: int, current_utilization: float
) -> tuple[list[float], int]:
    """Calculate cumulative usage at each bucket for the 7d window.

    Args:
        history: The full history dict from load_history()
        reset_time_7d: Unix timestamp when the 7d window resets
        width: Number of buckets (chart width)
        current_utilization: Current 7d utilization (0.0-1.0) from API

    Returns:
        Tuple of (buckets, current_index) where:
        - buckets: List of cumulative utilization values (0.0-1.0) at each bucket
        - current_index: Index of the last bucket with actual data (-1 if no data)
    """
    if width <= 0 or reset_time_7d <= 0:
        return ([0.0] * width, -1)

    now = time.time()
    window_start = reset_time_7d - 7 * 24 * 3600
    bucket_duration = 7 * 24 * 3600 / width
    buckets = [0.0] * width
    current_index = -1

    # Get the active account's session history
    active_account = history.get("active_account")
    if not active_account:
        return ([0.0] * width, -1)

    account = history.get("accounts", {}).get(active_account, {})
    sessions_5h = account.get("history", {}).get("sessions_5h", [])

    # Collect historical sessions with their timestamps and utilizations
    # These are completed 5h sessions within the 7d window
    all_sessions = []
    for session in sessions_5h:
        reset_at = session.get("reset_at", 0)
        utilization = session.get("utilization", 0)
        if reset_at > window_start:
            all_sessions.append((reset_at, utilization))

    # Sort by timestamp
    all_sessions.sort(key=lambda x: x[0])

    # Calculate the cumulative utilization at each bucket
    # We need to interpolate: at the end (now), it should equal current_utilization
    # Historical sessions contribute proportionally

    # First, calculate running sum at each historical session point
    cumulative_at_sessions = []
    running_sum = 0.0
    for ts, util in all_sessions:
        running_sum += util
        cumulative_at_sessions.append((ts, running_sum))

    # The total from historical sessions
    historical_total = running_sum

    # For each bucket up to current time, interpolate the cumulative value
    for i in range(width):
        bucket_end = window_start + (i + 1) * bucket_duration
        if bucket_end > now:
            # Future bucket - no data yet
            break

        # Find cumulative usage up to this bucket
        cumulative = 0.0
        for ts, cum_util in cumulative_at_sessions:
            if ts <= bucket_end:
                cumulative = cum_util
            else:
                break

        # Scale so that at current time we match current_utilization
        # The API's 7d_utilization is the authoritative value
        if historical_total > 0:
            # Scale historical data to match current utilization
            buckets[i] = (cumulative / historical_total) * current_utilization
        else:
            # No historical data, just use current utilization for the current bucket
            buckets[i] = (
                current_utilization if bucket_end >= now - bucket_duration else 0.0
            )
        current_index = i

    return (buckets, current_index)


def render_cumulative_chart_colored(
    buckets: list[float], width: int, current_index: int = -1
) -> list[str]:
    """Render a multi-row cumulative usage chart with Pango color gradient.

    Buckets after current_index are rendered as a "shadow" at the current height,
    indicating the minimum guaranteed usage level.

    Args:
        buckets: List of cumulative utilization values (0.0-1.0)
        width: Chart width (should match len(buckets))
        current_index: Index of the last bucket with actual data (-1 to disable shadow)

    Returns:
        List of row markup strings (top to bottom), length = CHART_HEIGHT
    """
    blocks = "▁▂▃▄▅▆▇█"
    max_level = CHART_HEIGHT * 8

    # Initialize row parts (top to bottom)
    row_parts: list[list[str]] = [[] for _ in range(CHART_HEIGHT)]

    # Get the current value for shadow projection
    current_value = buckets[current_index] if current_index >= 0 else 0.0

    for i, value in enumerate(buckets):
        is_shadow = current_index >= 0 and i > current_index

        if is_shadow:
            # Shadow: render at current_value height with dim color and low opacity
            level = int(current_value * max_level)
            level = max(0, min(max_level, level))
            color = COLOR_SHADOW
        else:
            level = int(value * max_level)
            level = max(0, min(max_level, level))
            # Color based on absolute cumulative value
            color = _cumulative_gradient_color(value)

        # Fill rows from bottom to top
        for row in range(CHART_HEIGHT):
            row_from_bottom = CHART_HEIGHT - 1 - row
            row_min_level = row_from_bottom * 8 + 1
            row_max_level = (row_from_bottom + 1) * 8

            if level < row_min_level:
                row_parts[row].append(" ")
            elif level >= row_max_level:
                row_parts[row].append(f'<span color="{color}">█</span>')
            else:
                partial = level - row_min_level + 1
                char = blocks[partial - 1]
                row_parts[row].append(f'<span color="{color}">{char}</span>')

    # Wrap each row in a span with background color (dim at 25% opacity)
    bg_color = f"{COLOR_DIM}40"
    rows = [
        f'<span bgcolor="{bg_color}">{"".join(parts)}</span>' for parts in row_parts
    ]

    return rows


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
