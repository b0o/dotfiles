"""Time formatting and output formatting for Claude usage monitor."""

import re
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from .constants import BAR_WIDTH, CHART_HEIGHT, COLOR_DIM, COLOR_SUBDUED, ICONS
from .history import load_history
from .rendering import (
    _chart_gradient_color,
    _cumulative_gradient_color,
    _gradient_color,
    _time_gradient_color,
    calculate_7d_buckets_from_history,
    calculate_cumulative_7d_buckets,
    calculate_cumulative_buckets,
    calculate_usage_buckets,
    get_compact_time_bar,
    get_compact_usage_bar,
    get_hourglass_icon,
    get_progress_bar,
    get_progress_bar_colored,
    get_time_bar,
    get_time_bar_colored,
    get_time_elapsed_percentage,
    render_5h_time_labels,
    render_7d_day_labels,
    render_cumulative_chart_colored,
    render_usage_timeline_chart_colored,
)


def format_reset_time(reset_timestamp: int) -> str:
    """Format reset timestamp to human-readable time like 'in 2 hours (11:00)'."""
    if reset_timestamp == 0:
        return "unknown"
    reset_dt = datetime.fromtimestamp(reset_timestamp, tz=timezone.utc).astimezone()
    now = datetime.now(timezone.utc).astimezone()

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


def format_plan_name(profile: Optional[Dict[str, Any]]) -> Optional[str]:
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


def format_tooltip(
    data: Dict[str, Any],
    last_check_time: Optional[datetime] = None,
    profile: Optional[Dict[str, Any]] = None,
    cred_source: Optional[str] = None,
    cred_is_fallback: bool = False,
    prefer_source: Optional[str] = None,
    usage_snapshots: Optional[list[tuple[float, float]]] = None,
    show_cumulative_chart: bool = True,
    chart_mode: str = "cycle",
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

    header_5h = f'   <b>5-hour session</b> <span color="{COLOR_SUBDUED}">{ICONS["bullet"]} {end_time_5h} (in {remaining_5h})</span>'
    header_7d = f'   <b>7-day window</b> <span color="{COLOR_SUBDUED}">{ICONS["bullet"]} {end_time_7d} (in {remaining_7d})</span>'

    # Build plain-text lines for width calculation, then markup lines for display
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

    # Use warning/rejected icon based on status
    def _get_status_icon_and_color(status: str) -> tuple[str, str]:
        if status == "allowed_warning":
            return ICONS["allowed_warning"], "#FFB86C"
        elif status not in ("allowed", "allowed_warning"):
            return ICONS["rejected"], "#FF7D90"
        return ICONS["zap"], COLOR_SUBDUED

    icon_5h, icon_5h_color = _get_status_icon_and_color(data["5h_status"])
    icon_7d, icon_7d_color = _get_status_icon_and_color(data["7d_status"])

    bar_line_5h_plain = f"{icon_5h}  {bar_5h} {util_5h:4.1f}%"
    bar_line_5h_markup = f'<span color="{icon_5h_color}" alpha="85%">{icon_5h}</span>  {bar_5h_colored} <span color="{usage_5h_pct_color}">{util_5h:4.1f}%</span>'
    time_line_5h_plain = f"{hourglass_5h}  {time_bar_5h} {time_elapsed_5h:4.1f}%"
    time_line_5h_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{hourglass_5h}</span>  {time_bar_5h_colored} <span color="{time_5h_pct_color}">{time_elapsed_5h:4.1f}%</span>'

    bar_line_7d_plain = f"{icon_7d}  {bar_7d} {util_7d:4.1f}%"
    bar_line_7d_markup = f'<span color="{icon_7d_color}" alpha="85%">{icon_7d}</span>  {bar_7d_colored} <span color="{usage_7d_pct_color}">{util_7d:4.1f}%</span>'
    time_line_7d_plain = f"{hourglass_7d}  {time_bar_7d} {time_elapsed_7d:4.1f}%"
    time_line_7d_markup = f'<span color="{COLOR_SUBDUED}" alpha="85%">{hourglass_7d}</span>  {time_bar_7d_colored} <span color="{time_7d_pct_color}">{time_elapsed_7d:4.1f}%</span>'

    # Build header plain text for width calculation
    header_5h_plain = (
        f"   5-hour session {ICONS['bullet']} {end_time_5h} (in {remaining_5h})"
    )
    header_7d_plain = (
        f"   7-day window {ICONS['bullet']} {end_time_7d} (in {remaining_7d})"
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
    footer = f" {ICONS['bullet']} ".join(footer_parts) if footer_parts else None

    plan_name = format_plan_name(profile)
    bullet = f'<span color="{COLOR_SUBDUED}">{ICONS["bullet"]}</span>'
    if plan_name:
        title_plain = (
            f"Claude {ICONS['bullet']} Usage Monitor {ICONS['bullet']} {plan_name} Plan"
        )
        title_markup = f"Claude {bullet} Usage Monitor {bullet} {plan_name} Plan"
    else:
        title_plain = f"Claude {ICONS['bullet']} Usage Monitor"
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
    lines.append(f'<span line_height="0.60">{" "}</span>')
    lines.append(header_5h)
    # Calculate chart data
    buckets, raw_buckets = calculate_usage_buckets(
        usage_snapshots or [], data["5h_reset"], BAR_WIDTH
    )
    cumulative_5h, current_idx_5h = calculate_cumulative_buckets(
        usage_snapshots or [], data["5h_reset"], BAR_WIDTH
    )
    bucketed_rows_5h = render_usage_timeline_chart_colored(
        buckets, BAR_WIDTH, raw_buckets
    )
    cumulative_rows_5h = render_cumulative_chart_colored(
        cumulative_5h, BAR_WIDTH, current_idx_5h
    )

    # Icons for chart types
    bucketed_icon = (
        f'<span color="{_chart_gradient_color(0.7)}">{ICONS["delta"]}</span>'
    )
    cumulative_icon = (
        f'<span color="{_cumulative_gradient_color(0.7)}">{ICONS["epsilon"]}</span>'
    )

    if chart_mode == "stacked":
        # Stacked: bucketed chart above usage bar, cumulative below
        lines.append(f'<span line_height="0.40">{" "}</span>')
        bucketed_lines_5h = []
        for idx, row in enumerate(bucketed_rows_5h):
            if (len(bucketed_rows_5h) > 3 and idx == 2) or (
                len(bucketed_rows_5h) <= 3 and idx == 0
            ):
                bucketed_lines_5h.append(f"   {row} {bucketed_icon}")
            else:
                bucketed_lines_5h.append(f"   {row}")
        lines.append(
            f'<span line_height="0.85">{chr(10).join(bucketed_lines_5h)}</span>'
        )
        lines.append(bar_line_5h_markup)
        lines.append(f'<span line_height="0.40">{" "}</span>')
        cumulative_lines_5h = []
        for idx, row in enumerate(cumulative_rows_5h):
            if (len(cumulative_rows_5h) > 3 and idx == 2) or (
                len(cumulative_rows_5h) <= 3 and idx == 0
            ):
                cumulative_lines_5h.append(f"   {row} {cumulative_icon}")
            else:
                cumulative_lines_5h.append(f"   {row}")
        lines.append(
            f'<span line_height="0.85">{chr(10).join(cumulative_lines_5h)}</span>'
        )
    else:
        # Cycle: usage bar then alternating chart
        lines.append(bar_line_5h_markup)
        chart_rows_5h = (
            cumulative_rows_5h if show_cumulative_chart else bucketed_rows_5h
        )
        # Highlight the active chart's icon, dim the other
        bucketed_color = (
            _chart_gradient_color(0.7) if not show_cumulative_chart else COLOR_DIM
        )
        cumulative_color = (
            _cumulative_gradient_color(0.7) if show_cumulative_chart else COLOR_DIM
        )
        icon_top = f'<span color="{bucketed_color}">𝚫</span>'
        icon_bottom = f'<span color="{cumulative_color}">𝚺</span>'
        chart_lines_5h = []
        for idx, row in enumerate(chart_rows_5h):
            if idx == 0:
                chart_lines_5h.append(f"   {row} {icon_top}")
            elif idx == CHART_HEIGHT - 1:
                chart_lines_5h.append(f"   {row} {icon_bottom}")
            else:
                chart_lines_5h.append(f"   {row}")
        lines.append(f'<span line_height="0.85">{chr(10).join(chart_lines_5h)}</span>')
    lines.append(time_line_5h_markup)
    time_labels_5h = render_5h_time_labels(data["5h_reset"], BAR_WIDTH)
    lines.append(f"   {time_labels_5h}")
    lines.append("")

    lines.append(header_7d)
    # Calculate 7d chart data
    history = load_history()
    buckets_7d, raw_buckets_7d = calculate_7d_buckets_from_history(
        history, data["7d_reset"], BAR_WIDTH
    )
    cumulative_7d, current_idx_7d = calculate_cumulative_7d_buckets(
        history, data["7d_reset"], BAR_WIDTH, data["7d_utilization"]
    )
    bucketed_rows_7d = render_usage_timeline_chart_colored(
        buckets_7d, BAR_WIDTH, raw_buckets_7d
    )
    cumulative_rows_7d = render_cumulative_chart_colored(
        cumulative_7d, BAR_WIDTH, current_idx_7d
    )

    if chart_mode == "stacked":
        # Stacked: bucketed chart above usage bar, cumulative below
        lines.append(f'<span line_height="0.40">{" "}</span>')
        bucketed_lines_7d = []
        for idx, row in enumerate(bucketed_rows_7d):
            if (len(bucketed_rows_7d) > 3 and idx == 2) or (
                len(bucketed_rows_7d) <= 3 and idx == 0
            ):
                bucketed_lines_7d.append(f"   {row} {bucketed_icon}")
            else:
                bucketed_lines_7d.append(f"   {row}")
        lines.append(
            f'<span line_height="0.85">{chr(10).join(bucketed_lines_7d)}</span>'
        )
        lines.append(bar_line_7d_markup)
        lines.append(f'<span line_height="0.40">{" "}</span>')
        cumulative_lines_7d = []
        for idx, row in enumerate(cumulative_rows_7d):
            if (len(cumulative_rows_7d) > 3 and idx == 2) or (
                len(cumulative_rows_7d) <= 3 and idx == 0
            ):
                cumulative_lines_7d.append(f"   {row} {cumulative_icon}")
            else:
                cumulative_lines_7d.append(f"   {row}")
        lines.append(
            f'<span line_height="0.85">{chr(10).join(cumulative_lines_7d)}</span>'
        )
    else:
        # Cycle: usage bar then alternating chart
        lines.append(bar_line_7d_markup)
        chart_rows_7d = (
            cumulative_rows_7d if show_cumulative_chart else bucketed_rows_7d
        )
        bucketed_color_7d = (
            _chart_gradient_color(0.7) if not show_cumulative_chart else COLOR_DIM
        )
        cumulative_color_7d = (
            _cumulative_gradient_color(0.7) if show_cumulative_chart else COLOR_DIM
        )
        icon_top_7d = f'<span color="{bucketed_color_7d}">𝚫</span>'
        icon_bottom_7d = f'<span color="{cumulative_color_7d}">𝚺</span>'
        chart_lines_7d = []
        for idx, row in enumerate(chart_rows_7d):
            if idx == 0:
                chart_lines_7d.append(f"   {row} {icon_top_7d}")
            elif idx == CHART_HEIGHT - 1:
                chart_lines_7d.append(f"   {row} {icon_bottom_7d}")
            else:
                chart_lines_7d.append(f"   {row}")
        lines.append(f'<span line_height="0.85">{chr(10).join(chart_lines_7d)}</span>')
    lines.append(time_line_7d_markup)
    day_labels = render_7d_day_labels(data["7d_reset"], BAR_WIDTH)
    lines.append(f"   {day_labels}")

    if footer:
        lines.append(f'<span line_height="0.60">{" "}</span>')
        lines.append(f'<span color="{COLOR_SUBDUED}">{footer.center(max_width)}</span>')

    return "\n".join(lines)


def format_waybar_output(
    data: Optional[Dict[str, Any]],
    last_check_time: Optional[datetime] = None,
    show_alternate: bool = False,
    has_token: bool = True,
    profile: Optional[Dict[str, Any]] = None,
    cred_source: Optional[str] = None,
    cred_is_fallback: bool = False,
    prefer_source: Optional[str] = None,
    display_mode: str = "normal",
    usage_snapshots: Optional[list[tuple[float, float]]] = None,
    show_cumulative_chart: bool = True,
    token_error: Optional[str] = None,
    chart_mode: str = "cycle",
) -> Optional[Dict[str, Any]]:
    """Format output for Waybar.

    Display modes:
    - compact: alternates between "{icon} {pct}%" and "{icon} {time}"
    - normal: "{icon} {pct}% ({time})"
    - expanded: "{icon} {bar} {pct}%" alternating bar between usage and time elapsed
    """
    if not has_token:
        tooltip = "No active token"
        if token_error:
            tooltip += f"\n\n{token_error}"
        return {
            "text": ICONS["star"],
            "tooltip": tooltip,
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
        show_cumulative_chart,
        chart_mode,
    )

    # Format text based on display mode
    if display_mode == "compact":
        if show_alternate and is_5h_active:
            text = f"{ICONS['zap']} {reset_short}"
        else:
            text = f"{ICONS['zap']} {percentage}%"
    elif display_mode == "normal":
        hourglass = get_hourglass_icon(time_elapsed_pct)
        text = f"{ICONS['zap']} {percentage}%  {hourglass} {int(time_elapsed_pct)}%"
    elif display_mode == "expanded":
        if show_alternate and is_5h_active:
            hourglass = get_hourglass_icon(time_elapsed_pct)
            bar = get_compact_time_bar(int(time_elapsed_pct))
            text = f"{ICONS['zap']} {bar}  {hourglass} {int(time_elapsed_pct):2d}%"
        else:
            bar = get_compact_usage_bar(percentage)
            text = f"{ICONS['zap']} {bar}  {ICONS['zap']} {percentage:2d}%"
    else:
        text = f"{ICONS['zap']} {percentage}%"

    return {
        "text": text,
        "tooltip": tooltip,
        "percentage": percentage,
        "class": css_class,
    }
