"""Shared utilities for waybar custom modules."""
# /// script
# requires-python = ">=3.11"
# dependencies = ["humanize"]
# ///

import re
from datetime import datetime, timedelta

import humanize


def format_delta_short(delta: timedelta) -> str:
    """Format a timedelta as a short string like '3h' or '12m'.

    Handles positive deltas only. For negative deltas, use abs() first.
    """
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


def format_relative_short(dt: datetime, now: datetime) -> str:
    """Format a datetime as a short relative time like '2h' or '30m ago'."""
    delta = dt - now

    if delta.total_seconds() < 0:
        return format_delta_short(abs(delta)) + " ago"
    else:
        return format_delta_short(delta)


def format_delta_hm(delta: timedelta) -> str:
    """Format a timedelta as hours and minutes like '8h 32m'.

    Handles positive deltas only. For negative deltas, use abs() first.
    """
    total_seconds = int(delta.total_seconds())
    if total_seconds <= 0:
        return "0m"

    hours, remainder = divmod(total_seconds, 3600)
    minutes = remainder // 60

    if hours > 0 and minutes > 0:
        return f"{hours}h {minutes}m"
    elif hours > 0:
        return f"{hours}h"
    else:
        return f"{minutes}m"


def format_relative_long(dt: datetime, now: datetime) -> str:
    """Format a datetime as a longer relative time like '8h 32m ago' or 'in 8h 32m'."""
    delta = dt - now

    if delta.total_seconds() < 0:
        return format_delta_hm(abs(delta)) + " ago"
    else:
        return "in " + format_delta_hm(delta)
