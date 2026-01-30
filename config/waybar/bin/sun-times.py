#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["astral", "humanize", "airportsdata", "tzlocal", "timezonefinder"]
# ///

import argparse
import json
import math
import re
import sys
import time

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from astral import Observer
from astral.sun import sunrise, sunset
import airportsdata
from timezonefinder import TimezoneFinder
from tzlocal import get_localzone

from waybar_utils import format_relative_short, format_relative_long

ICON_SUNRISE = "󰖜"
ICON_SUNSET = "󰖛"

UPDATE_INTERVAL = 60  # seconds
PROXIMITY_MINUTES = 45  # minutes within sunrise/sunset to highlight
NOW_MINUTES = 10  # minutes after sunrise/sunset to still show "now"


def get_timezone_centroid(tz_name: str) -> tuple[float, float] | None:
    """Find the geographic centroid of all airports in a timezone.

    Returns (lat, lon) of the airport closest to the centroid, or None if
    no airports found for the timezone.
    """
    airports = airportsdata.load("IATA")

    # Group airports by timezone
    tz_airports = [a for a in airports.values() if a.get("tz") == tz_name]

    if not tz_airports:
        return None

    # Calculate centroid
    avg_lat = sum(a["lat"] for a in tz_airports) / len(tz_airports)
    avg_lon = sum(a["lon"] for a in tz_airports) / len(tz_airports)

    # Find airport closest to centroid
    def distance_to_centroid(a: dict) -> float:
        return math.sqrt((a["lat"] - avg_lat) ** 2 + (a["lon"] - avg_lon) ** 2)

    closest = min(tz_airports, key=distance_to_centroid)
    return closest["lat"], closest["lon"]


def parse_location(location: str | None) -> tuple[float, float, str, ZoneInfo]:
    """Parse location string into (lat, lon, display_name, timezone).

    Accepts:
    - Airport IATA code (e.g., "PDX")
    - Lat,lon string (e.g., "45.5,-122.6")
    - None (uses system timezone to find central location)
    """
    airports = airportsdata.load("IATA")

    if location is None:
        # Get IANA timezone name from system
        tz_name = get_localzone().key

        centroid = get_timezone_centroid(tz_name)
        if centroid:
            lat, lon = centroid
            tz_display = tz_name.replace("_", " ")
            display = f"{tz_display} ({lat:.2f}, {lon:.2f})"
            return lat, lon, display, ZoneInfo(tz_name)

        # Fallback: couldn't determine location
        tz_display = tz_name or "unknown"
        print(
            f"Could not determine location from timezone '{tz_display}'",
            file=sys.stderr,
        )
        print(
            "Please specify --location with an airport code or lat,lon", file=sys.stderr
        )
        sys.exit(1)

    # At this point, location is definitely a string
    assert location is not None

    # Check if it looks like lat,lon (contains comma and numbers)
    latlon_match = re.match(r"^(-?\d+\.?\d*),\s*(-?\d+\.?\d*)$", location.strip())
    if latlon_match:
        lat = float(latlon_match.group(1))
        lon = float(latlon_match.group(2))
        tf = TimezoneFinder()
        tz_name = tf.timezone_at(lat=lat, lng=lon)
        if tz_name:
            tz_display = tz_name.replace("_", " ")
            display = f"{tz_display} ({lat:.2f}, {lon:.2f})"
            tz = ZoneInfo(tz_name)
        else:
            display = f"{lat:.4f}, {lon:.4f}"
            tz = get_localzone()
        return lat, lon, display, tz

    # Otherwise treat as airport code
    code = location.strip().upper()
    airport = airports.get(code)
    if airport:
        display = format_airport_location(airport)
        tz_name = airport.get("tz")
        tz = ZoneInfo(tz_name) if tz_name else get_localzone()
        return airport["lat"], airport["lon"], display, tz

    print(f"Unknown airport code: {code}", file=sys.stderr)
    sys.exit(1)


def format_airport_location(airport: dict) -> str:
    """Format airport info as 'City, State, Country (CODE)'."""
    parts = [airport["city"]]
    if airport.get("subd"):
        parts.append(airport["subd"])
    parts.append(airport["country"])
    return f"{', '.join(parts)} ({airport['iata']})"


def get_sun_times(lat: float, lon: float, date: datetime) -> tuple[datetime, datetime]:
    """Get sunrise and sunset times for a given location and date."""
    observer = Observer(latitude=lat, longitude=lon, elevation=0)
    tz = date.tzinfo or ZoneInfo("UTC")

    sunrise_time = sunrise(observer, date.date(), tzinfo=tz)
    sunset_time = sunset(observer, date.date(), tzinfo=tz)

    return sunrise_time, sunset_time


def format_output(
    lat: float, lon: float, location_name: str, now: datetime, tz: ZoneInfo
) -> dict:
    """Format the waybar JSON output."""
    # Convert now to the target timezone for display
    now = now.astimezone(tz)
    sunrise_time, sunset_time = get_sun_times(lat, lon, now)

    proximity_threshold = timedelta(minutes=PROXIMITY_MINUTES)
    now_threshold = timedelta(minutes=NOW_MINUTES)

    # Calculate time differences (positive = future, negative = past)
    time_to_sunrise = (sunrise_time - now).total_seconds()
    time_to_sunset = (sunset_time - now).total_seconds()

    # Check if we're in the "now" window (within NOW_MINUTES after sunrise/sunset)
    sunrise_just_happened = -now_threshold.total_seconds() <= time_to_sunrise < 0
    sunset_just_happened = -now_threshold.total_seconds() <= time_to_sunset < 0

    # Determine next event and display
    if sunrise_just_happened:
        # Sunrise just happened - show "now" with sunrise icon
        display_icon = ICON_SUNRISE
        text = f"{display_icon} now"
        css_class = "sunrise-soon"
    elif sunset_just_happened:
        # Sunset just happened - show "now" with sunset icon
        display_icon = ICON_SUNSET
        text = f"{display_icon} now"
        css_class = "sunset-soon"
    elif now < sunrise_time:
        # Before sunrise
        next_time = sunrise_time
        next_icon = ICON_SUNRISE
        relative_short = format_relative_short(next_time, now)
        text = f"{next_icon} {relative_short}"
        if abs(time_to_sunrise) <= proximity_threshold.total_seconds():
            css_class = "sunrise-soon"
        else:
            css_class = "sunrise"
    elif now < sunset_time:
        # After sunrise, before sunset
        next_time = sunset_time
        next_icon = ICON_SUNSET
        relative_short = format_relative_short(next_time, now)
        text = f"{next_icon} {relative_short}"
        if abs(time_to_sunset) <= proximity_threshold.total_seconds():
            css_class = "sunset-soon"
        else:
            css_class = "sunset"
    else:
        # After sunset - get tomorrow's sunrise
        tomorrow = now + timedelta(days=1)
        tomorrow_sunrise, _ = get_sun_times(lat, lon, tomorrow)
        next_time = tomorrow_sunrise
        next_icon = ICON_SUNRISE
        relative_short = format_relative_short(next_time, now)
        text = f"{next_icon} {relative_short}"
        css_class = "sunrise"

    # Determine adjacent sunrise/sunset pair
    # We always want one in the past and one in the future
    # - Daytime (after sunrise, before sunset): show today's sunrise (past) and today's sunset (future)
    # - Nighttime after sunset: show today's sunset (past) and tomorrow's sunrise (future)
    # - Nighttime before sunrise: show yesterday's sunset (past) and today's sunrise (future)
    if now < sunrise_time:
        # Before sunrise - it's night, show yesterday's sunset and today's sunrise
        yesterday = now - timedelta(days=1)
        _, tooltip_sunset = get_sun_times(lat, lon, yesterday)
        tooltip_sunrise = sunrise_time
    elif now >= sunset_time and not sunset_just_happened:
        # After sunset - it's night, show today's sunset and tomorrow's sunrise
        tomorrow = now + timedelta(days=1)
        tooltip_sunrise, _ = get_sun_times(lat, lon, tomorrow)
        tooltip_sunset = sunset_time
    else:
        # Daytime (or sunset just happened) - show today's sunrise and sunset
        tooltip_sunrise = sunrise_time
        tooltip_sunset = sunset_time

    # Build raw text for each line (without markup) to calculate widths
    location_text = location_name
    date_text = f"{now.strftime('%a %b %d %Y')} · {now.strftime('%H:%M')}"

    sunrise_time_str = tooltip_sunrise.strftime("%H:%M")
    sunrise_relative = format_relative_long(tooltip_sunrise, now)
    sunrise_in_past = tooltip_sunrise < now
    # Icon + 2 spaces + "Sunrise" + 2 spaces + time + 3 spaces + relative
    sunrise_text = f"X  Sunrise  {sunrise_time_str}   {sunrise_relative}"

    sunset_time_str = tooltip_sunset.strftime("%H:%M")
    sunset_relative = format_relative_long(tooltip_sunset, now)
    sunset_text = f"X  Sunset   {sunset_time_str}   {sunset_relative}"

    # Find the longest line
    max_width = max(
        len(location_text), len(date_text), len(sunrise_text), len(sunset_text)
    )

    # Center the header lines
    location_centered = location_text.center(max_width)
    date_centered = date_text.center(max_width)

    # Format tooltip with Pango markup
    header = f'<b>{location_centered}</b>\n<span alpha="75%">{date_centered}</span>'

    # Sunrise line with Pango markup - yellow icon, monospace time
    sunrise_line = f'<span color="#FFD080">{ICON_SUNRISE}</span>  Sunrise  <tt><b>{sunrise_time_str}</b></tt>  <span alpha="75%">{sunrise_relative}</span>'

    # Sunset line with Pango markup - orange icon, monospace time
    sunset_line = f'<span color="#ff9969">{ICON_SUNSET}</span>  Sunset   <tt><b>{sunset_time_str}</b></tt>  <span alpha="75%">{sunset_relative}</span>'

    # Order lines so past event is on top, future event is on bottom
    if sunrise_in_past:
        tooltip = f"{header}\n\n{sunrise_line}\n{sunset_line}"
    else:
        tooltip = f"{header}\n\n{sunset_line}\n{sunrise_line}"

    return {
        "text": text,
        "tooltip": tooltip,
        "class": css_class,
    }


def monitor(lat: float, lon: float, location_name: str, tz: ZoneInfo):
    """Main monitoring loop - emit JSON updates every 60 seconds."""
    last_output_json = None

    try:
        while True:
            now = datetime.now().astimezone()
            output = format_output(lat, lon, location_name, now, tz)
            output_json = json.dumps(output)

            # Only print if output changed
            if output_json != last_output_json:
                print(output_json, flush=True)
                last_output_json = output_json

            time.sleep(UPDATE_INTERVAL)

    except KeyboardInterrupt:
        sys.exit(0)


def main():
    parser = argparse.ArgumentParser(
        description="Sunrise/sunset times module for Waybar"
    )
    parser.add_argument(
        "--location",
        "-l",
        type=str,
        default=None,
        help="Location: airport IATA code (e.g., 'PDX') or lat,lon (e.g., '45.5,-122.6')",
    )
    parser.add_argument(
        "--time",
        "-t",
        type=str,
        default=None,
        help="Use specific time instead of current time (format: HH:MM or YYYY-MM-DD HH:MM)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Output once and exit (for use with waybar interval)",
    )

    args = parser.parse_args()

    # Parse location
    lat, lon, location_name, tz = parse_location(args.location)

    # If --time is provided, output once and exit (pretty-printed for debugging)
    if args.time:
        now = datetime.now().astimezone()
        try:
            if " " in args.time:
                # Full datetime format
                parsed = datetime.strptime(args.time, "%Y-%m-%d %H:%M")
            else:
                # Time only - use today's date
                parsed = datetime.strptime(args.time, "%H:%M")
                parsed = parsed.replace(year=now.year, month=now.month, day=now.day)
            # Apply local timezone
            test_time = parsed.replace(tzinfo=now.tzinfo)
        except ValueError:
            print(f"Invalid time format: {args.time}", file=sys.stderr)
            sys.exit(1)

        output = format_output(lat, lon, location_name, test_time, tz)
        print(json.dumps(output, indent=2))
        return

    # If --once, output once and exit
    if args.once:
        now = datetime.now().astimezone()
        output = format_output(lat, lon, location_name, now, tz)
        print(json.dumps(output))
        return

    monitor(lat, lon, location_name, tz)


if __name__ == "__main__":
    main()
