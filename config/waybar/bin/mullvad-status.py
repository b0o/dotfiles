#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
# ]
# ///

import argparse
import hashlib
import json
import os
import requests
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Dict, List, Optional


def run_command(cmd: str, timeout: int = 5) -> Optional[str]:
    """Run a shell command and return its output."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, subprocess.SubprocessError):
        pass
    return None


def safe_verify_ip(ip: str, cache: Dict[str, bool]) -> bool:
    """Verify IP with caching to avoid redundant checks in formatting."""
    if ip in cache:
        return cache[ip]
    result = verify_ip(ip)
    cache[ip] = result
    return result


# Constants
NETWORK_CHECK_INTERVAL = 1.0  # Check local network state every second
MULLVAD_CHECK_INTERVAL = 30.0  # Full API check every 30 seconds
STALE_DATA_THRESHOLD = 300  # 5 minutes before marking data as stale
DNS_LEAK_REQUESTS = 6  # Number of DNS leak check requests
REQUEST_TIMEOUT = 6  # HTTP request timeout in seconds

ICON_SECURE = "󰌾"  # Lock icon when secure
ICON_LEAK = "󱙱"  # Lock failed icon when leaking
ICON_LOADING_FRAMES = [
    "",
    "",
    "",
    "",
    "",
    "",
]

# Cache file location (stores status and approved DNS list)
CACHE_DIR = Path(os.getenv("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE_FILE = CACHE_DIR / "mullvad-waybar-status.json"


def check_ipv4() -> Optional[Dict]:
    """Check IPv4 connection via Mullvad API.

    Returns connection details including:
    - ip, country, city, latitude, longitude
    - mullvad_exit_ip (bool)
    - mullvad_exit_ip_hostname
    - mullvad_server_type (e.g., "WireGuard")
    - organization (provider)
    - blacklisted info
    """
    try:
        response = requests.get(
            "https://ipv4.am.i.mullvad.net/json", timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            return response.json()
    except Exception as e:
        print(f"IPv4 check error: {e}", file=sys.stderr)
    return None


def check_ipv6() -> Optional[Dict]:
    """Check IPv6 connection via Mullvad API.

    Returns connection details including:
    - ip, country, city, latitude, longitude
    - mullvad_exit_ip (bool)
    - mullvad_exit_ip_hostname
    - mullvad_server_type (e.g., "WireGuard")
    - organization (provider)
    - blacklisted info

    Returns None if IPv6 is not available on the network.
    """
    try:
        response = requests.get(
            "https://ipv6.am.i.mullvad.net/json", timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            return response.json()
    except Exception:
        # IPv6 not available is normal, don't print error
        pass
    return None


def verify_ip(ip: str) -> bool:
    """Verify if an IP address is a Mullvad exit IP.

    Uses the check-ip endpoint to double-check IP addresses.
    """
    try:
        response = requests.get(
            f"https://am.i.mullvad.net/check-ip/{ip}", timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            data = response.json()
            return data.get("mullvad_exit_ip", False)
    except Exception as e:
        print(f"IP verification error for {ip}: {e}", file=sys.stderr)
    return False


def load_cache_file() -> Optional[Dict]:
    """Load cache file containing status and approved DNS list.

    Returns dict with:
    - status: Last known status (or None)
    - approved_dns_ips: List of approved DNS server IPs
    """
    if not CACHE_FILE.exists():
        return None

    try:
        with open(CACHE_FILE, "r") as f:
            data = json.load(f)
            return data
    except Exception as e:
        print(f"Error loading cache file: {e}", file=sys.stderr)
        return None


def save_cache_file(
    status: Optional[Dict] = None, approved_dns_ips: Optional[List[str]] = None
) -> None:
    """Save status and/or approved DNS list to cache file.

    Args:
        status: Current status dict (if None, preserves existing status)
        approved_dns_ips: List of approved DNS IPs (if None, preserves existing list)
    """
    # Load existing data
    existing = load_cache_file() or {}

    # Update with new data (preserve existing if not provided)
    data = {
        "status": status if status is not None else existing.get("status"),
        "approved_dns_ips": approved_dns_ips
        if approved_dns_ips is not None
        else existing.get("approved_dns_ips", []),
    }

    # Create parent directory if needed
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

    with open(CACHE_FILE, "w") as f:
        json.dump(data, f, indent=2)


def load_dns_approved() -> List[str]:
    """Load DNS approved list from cache file.

    Returns list of approved DNS server IPs.
    """
    cache = load_cache_file()
    if cache:
        return cache.get("approved_dns_ips", [])
    return []


def check_dns_leaks(quiet: bool = False) -> List[Dict]:
    """Check for DNS leaks using UUID-based subdomains.

    Makes multiple requests to unique subdomains. Each DNS server
    that resolves the request will be reported by the API.

    Args:
        quiet: If True, suppress console output

    Returns list of unique DNS servers (deduplicated by IP).
    """
    dns_servers = []

    if not quiet:
        print(f"Running {DNS_LEAK_REQUESTS} DNS leak checks...", end="", flush=True)

    for i in range(DNS_LEAK_REQUESTS):
        try:
            uuid_str = str(uuid.uuid4())
            response = requests.get(
                f"https://{uuid_str}.dnsleak.am.i.mullvad.net",
                headers={"Accept": "application/json"},
                timeout=REQUEST_TIMEOUT,
            )
            if response.ok:
                # API returns list of DNS servers
                servers = response.json()
                if isinstance(servers, list):
                    dns_servers.extend(servers)
            if not quiet:
                print(".", end="", flush=True)
        except Exception:
            if not quiet:
                print("x", end="", flush=True)
            continue

    if not quiet:
        print()  # New line after progress

    # Remove duplicates based on IP
    unique_servers = {}
    for server in dns_servers:
        ip = server.get("ip")
        if ip and ip not in unique_servers:
            unique_servers[ip] = server

    return list(unique_servers.values())


def get_network_state_hash() -> str:
    """Get hash of current network configuration.

    Monitors: routing table, interface states, IP addresses, DNS config.
    Returns SHA256 hash to detect any network topology changes.
    """
    try:
        route_output = run_command("ip route show") or ""
        link_output = run_command("ip link show") or ""
        addr_output = run_command("ip addr show") or ""

        # Read DNS config
        resolv_conf = ""
        try:
            resolv_path = Path("/etc/resolv.conf")
            if resolv_path.exists():
                resolv_conf = resolv_path.read_text()
        except Exception:
            pass

        # Combine and hash
        combined = f"{route_output}\n{link_output}\n{addr_output}\n{resolv_conf}"
        return hashlib.sha256(combined.encode()).hexdigest()
    except Exception as e:
        print(f"Error getting network state: {e}", file=sys.stderr)
        return ""


def perform_mullvad_checks(quiet: bool = False) -> Dict:
    """Run all Mullvad API checks and return combined status.

    Returns dict with:
    - secure: bool (overall security status)
    - issues: list of problem descriptions
    - ipv4_data: IPv4 connection data
    - ipv6: IPv6 address or None
    - dns_servers: List of DNS servers
    - timestamp: When check was performed

    Args:
        quiet: If True, suppress console output
    """
    if not quiet:
        print("\n" + "=" * 50)
        print("PERFORMING MULLVAD SECURITY CHECKS")
        print("=" * 50)

    timestamp = time.time()
    issues = []

    # IPv4 check
    if not quiet:
        print("\n[1/3] Checking IPv4...")
    ipv4_data = check_ipv4()
    if not ipv4_data:
        issues.append("IPv4 check failed")
    elif not ipv4_data.get("mullvad_exit_ip"):
        issues.append("IPv4 leak detected - not using Mullvad exit IP")
        if not quiet:
            print(f"  ✗ IP: {ipv4_data.get('ip')} (NOT MULLVAD)")
    else:
        if not quiet:
            print(
                f"  ✓ IP: {ipv4_data.get('ip')} via {ipv4_data.get('mullvad_exit_ip_hostname')}"
            )

    # IPv6 check
    if not quiet:
        print("\n[2/3] Checking IPv6...")
    ipv6_data = check_ipv6()
    if ipv6_data:
        ipv6 = ipv6_data.get("ip", "Unknown")
        is_mullvad = ipv6_data.get("mullvad_exit_ip", False)
        if not is_mullvad:
            issues.append("IPv6 leak detected - not using Mullvad exit IP")
            if not quiet:
                print(f"  ✗ IPv6: {ipv6} (NOT MULLVAD)")
        else:
            if not quiet:
                server = ipv6_data.get("mullvad_exit_ip_hostname", "")
                print(f"  ✓ IPv6: {ipv6} ({server})")
    else:
        if not quiet:
            print("  ○ IPv6 not available (OK)")

    # DNS leak check
    if not quiet:
        print("\n[3/3] Checking DNS...")
    dns_servers = check_dns_leaks(quiet=quiet)

    # Load approved list and filter out approved servers
    approved_ips = load_dns_approved()
    non_approved_servers = [s for s in dns_servers if s.get("ip") not in approved_ips]

    # Check for non-Mullvad DNS among non-approved servers
    has_non_mullvad_dns = any(
        not server.get("mullvad_dns", False) for server in non_approved_servers
    )

    if has_non_mullvad_dns:
        issues.append("DNS leak detected - non-Mullvad DNS servers found")
        non_mullvad = [
            s for s in non_approved_servers if not s.get("mullvad_dns", False)
        ]
        if not quiet:
            for server in non_mullvad:
                print(
                    f"  ✗ {server.get('ip')} ({server.get('organization', 'Unknown')})"
                )
    else:
        if not quiet:
            print(f"  ✓ All {len(non_approved_servers)} DNS server(s) are Mullvad")
            if len(dns_servers) > len(non_approved_servers):
                approved_count = len(dns_servers) - len(non_approved_servers)
                print(f"  ○ {approved_count} approved DNS server(s) ignored")

    # Overall status
    is_secure = len(issues) == 0

    if not quiet:
        print("\n" + "=" * 50)
        if is_secure:
            print("✓ SECURE - All checks passed")
        else:
            print("✗ INSECURE - Issues detected:")
            for issue in issues:
                print(f"  • {issue}")
        print("=" * 50)

    status = {
        "secure": is_secure,
        "issues": issues,
        "ipv4_data": ipv4_data,
        "ipv6_data": ipv6_data,
        "dns_servers": dns_servers,
        "timestamp": timestamp,
    }

    # Only save to cache if status actually changed (excluding timestamp)
    cache = load_cache_file()
    old_status = cache.get("status") if cache else None

    # Compare status excluding timestamp
    def status_changed(old: Optional[Dict], new: Dict) -> bool:
        if not old:
            return True
        # Compare all fields except timestamp
        return (
            old.get("secure") != new.get("secure")
            or old.get("issues") != new.get("issues")
            or old.get("ipv4_data") != new.get("ipv4_data")
            or old.get("ipv6_data") != new.get("ipv6_data")
            or old.get("dns_servers") != new.get("dns_servers")
        )

    if status_changed(old_status, status):
        save_cache_file(status=status)

    return status


def format_detailed_status(
    status: Optional[Dict],
    current_time: float,
    verify_cache: Optional[Dict] = None,
    approved_dns_ips: Optional[list] = None,
) -> str:
    """Format detailed status information for display.

    Similar to what will be shown in waybar tooltip.
    """
    if verify_cache is None:
        verify_cache = {}
    if approved_dns_ips is None:
        approved_dns_ips = []

    if not status:
        return "Mullvad VPN: No data available"

    lines = []

    # Header with staleness check
    timestamp = status.get("timestamp", 0)
    age = current_time - timestamp
    stale_marker = " (STALE DATA)" if age > STALE_DATA_THRESHOLD else ""

    is_secure = status.get("secure", False)
    icon = ICON_SECURE if is_secure else ICON_LEAK
    status_text = "SECURE" if is_secure else "INSECURE"

    lines.append(f"{icon} Mullvad VPN: {status_text}{stale_marker}")
    lines.append("")

    # IPv4 info
    ipv4_data = status.get("ipv4_data")
    if ipv4_data:
        ip = ipv4_data.get("ip", "Unknown")
        server = ipv4_data.get("mullvad_exit_ip_hostname", "Unknown")
        city = ipv4_data.get("city", "")
        country = ipv4_data.get("country", "")
        protocol = ipv4_data.get("mullvad_server_type", "")
        provider = ipv4_data.get("organization", "")
        is_mullvad = ipv4_data.get("mullvad_exit_ip", False)

        check = "✓" if is_mullvad else "✗"
        lines.append(f"IPv4: {check} {ip}")
        if server != "Unknown":
            lines.append(f"  Server: {server}")
        if city and country:
            lines.append(f"  Location: {city}, {country}")
        if protocol:
            lines.append(f"  Protocol: {protocol}")
        if provider:
            lines.append(f"  Provider: {provider}")
    else:
        lines.append("IPv4: ✗ Check failed")

    lines.append("")

    # IPv6 info
    ipv6_data = status.get("ipv6_data")
    if ipv6_data:
        ip = ipv6_data.get("ip", "Unknown")
        server = ipv6_data.get("mullvad_exit_ip_hostname", "Unknown")
        city = ipv6_data.get("city", "")
        country = ipv6_data.get("country", "")
        protocol = ipv6_data.get("mullvad_server_type", "")
        provider = ipv6_data.get("organization", "")
        is_mullvad = ipv6_data.get("mullvad_exit_ip", False)

        check = "✓" if is_mullvad else "✗"
        lines.append(f"IPv6: {check} {ip}")
        if server != "Unknown":
            lines.append(f"  Server: {server}")
        if city and country:
            lines.append(f"  Location: {city}, {country}")
        if protocol:
            lines.append(f"  Protocol: {protocol}")
        if provider:
            lines.append(f"  Provider: {provider}")
    else:
        lines.append("IPv6: Not available")

    lines.append("")

    # DNS servers - organize into three sections
    dns_servers = status.get("dns_servers", [])
    if dns_servers:
        # Categorize servers
        mullvad_servers = []
        unknown_servers = []
        approved_servers = []

        for server in dns_servers:
            ip = server.get("ip", "Unknown")
            is_mullvad = server.get("mullvad_dns", False)
            hostname = server.get("mullvad_dns_hostname", "")
            org = server.get("organization", "")

            if is_mullvad:
                mullvad_servers.append((ip, hostname))
            elif ip in approved_dns_ips:
                approved_servers.append((ip, org))
            else:
                unknown_servers.append((ip, org))

        # Show sections that have servers
        sections_shown = 0

        if mullvad_servers:
            if sections_shown > 0:
                lines.append("")
            lines.append(f"Mullvad DNS ({len(mullvad_servers)}):")
            for ip, hostname in mullvad_servers:
                lines.append(f"  ✓ {ip} ({hostname})")
            sections_shown += 1

        if unknown_servers:
            if sections_shown > 0:
                lines.append("")
            lines.append(f"Unknown DNS ({len(unknown_servers)}):")
            for ip, org in unknown_servers:
                lines.append(f"  ✗ {ip} ({org})")
            sections_shown += 1

        if approved_servers:
            if sections_shown > 0:
                lines.append("")
            lines.append(f"Approved DNS ({len(approved_servers)}):")
            for ip, org in approved_servers:
                lines.append(f"  ✓ {ip} ({org})")
            sections_shown += 1

        if sections_shown == 0:
            lines.append("DNS: No servers detected")
    else:
        lines.append("DNS: No data")

    # Issues
    issues = status.get("issues", [])
    if issues:
        lines.append("")
        lines.append("Issues:")
        for issue in issues:
            lines.append(f"  • {issue}")

    return "\n".join(lines)


def format_waybar_output(
    status: Optional[Dict],
    current_time: float,
    verify_cache: Optional[Dict] = None,
    loading: bool = False,
    loading_frame_index: int = 0,
    approved_dns_ips: Optional[list] = None,
) -> Dict:
    """Format status for waybar JSON output.

    Args:
        status: Status dict from perform_mullvad_checks
        current_time: Current timestamp
        verify_cache: IP verification cache
        loading: If True, show loading spinner (for initial fetch only)
        loading_frame_index: Frame index for animated loading spinner
        approved_dns_ips: List of manually approved DNS server IPs

    Returns dict with:
    - text: Icon string
    - tooltip: Detailed status
    - class: List of CSS classes
    - alt: Alternative text identifier
    """
    if verify_cache is None:
        verify_cache = {}
    if approved_dns_ips is None:
        approved_dns_ips = []

    if not status:
        return {
            "text": ICON_LEAK,
            "tooltip": "Mullvad VPN: No data available",
            "class": ["mullvad", "error"],
            "alt": "mullvad-error",
        }

    is_secure = status.get("secure", False)
    timestamp = status.get("timestamp", 0)
    age = current_time - timestamp
    is_stale = age > STALE_DATA_THRESHOLD

    # Build CSS classes
    classes = ["mullvad"]
    if is_secure:
        classes.append("state-secure")
    else:
        classes.append("state-leak")

    if is_stale:
        classes.append("stale")

    if loading:
        classes.append("loading")

    # Generate tooltip
    tooltip = format_detailed_status(
        status, current_time, verify_cache, approved_dns_ips
    )
    if loading:
        tooltip = "Loading...\n\n" + tooltip

    # Determine icon and alt
    status_icon = ICON_SECURE if is_secure else ICON_LEAK

    if loading:
        # Show status icon + loading spinner frame
        frame = ICON_LOADING_FRAMES[loading_frame_index % len(ICON_LOADING_FRAMES)]
        icon = f"{status_icon} {frame}"
        alt = "mullvad-loading"
    else:
        icon = status_icon
        alt = "mullvad-secure" if is_secure else "mullvad-leak"

    return {
        "text": icon,
        "tooltip": tooltip,
        "class": classes,
        "alt": alt,
    }


# Usage Notes:
# - Run script to start monitoring
# - Initial check happens immediately
# - Subsequent checks every 30 seconds
# - Instant check if network topology changes
# - Ctrl+C to stop
#
# Testing scenarios:
# 1. Connected to Mullvad: Should show SECURE
# 2. Disconnected from VPN: Should show INSECURE with IP leak
# 3. Toggle VPN: Should detect network change and re-check
# 4. Kill network: Should handle errors gracefully


def single_check_mode() -> None:
    """Run a single check and exit with appropriate exit code.

    Exit codes:
    - 0: Secure (all checks passed)
    - 1: Insecure (issues detected)
    """
    status = perform_mullvad_checks()

    # Load approved DNS list from cache
    cache = load_cache_file()
    approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []

    print("\n" + "=" * 50)
    print("FINAL STATUS")
    print("=" * 50)
    detailed = format_detailed_status(status, time.time(), approved_dns_ips=approved_dns_ips)
    print(detailed)

    # Exit with appropriate code
    exit_code = 0 if status.get("secure", False) else 1
    sys.exit(exit_code)


def approve_dns_mode() -> None:
    """Load DNS servers from cache and save to approved list."""
    print("\n" + "=" * 50)
    print("DNS APPROVAL MODE")
    print("=" * 50)

    # Load cached status
    cache = load_cache_file()
    if not cache or not cache.get("status"):
        print(
            "\n✗ No cached status found. Run a check first before approving DNS servers."
        )
        print("   Hint: Run without --approve-dns to perform a check.")
        sys.exit(1)

    status = cache.get("status")
    dns_servers = status.get("dns_servers", []) if status else []

    if not dns_servers:
        print("\n✗ No DNS servers found in cached status.")
        sys.exit(1)

    print("\nDNS servers from last check:")
    for server in dns_servers:
        ip = server.get("ip", "Unknown")
        org = server.get("organization", "Unknown")
        is_mullvad = server.get("mullvad_dns", False)
        hostname = server.get("mullvad_dns_hostname", "")

        check = "✓" if is_mullvad else "✗"
        info = hostname if is_mullvad else org
        print(f"  {check} {ip} ({info})")

    # Extract IPs and save to approved list
    approved_ips = [server.get("ip") for server in dns_servers if server.get("ip")]
    save_cache_file(approved_dns_ips=approved_ips)

    print(f"\n✓ Saved {len(approved_ips)} DNS server(s) to approved list")
    print(f"  Location: {CACHE_FILE}")
    print("\nThese servers will be ignored in future checks.")
    sys.exit(0)


def approve_dns_interactive() -> None:
    """Launch rofi for interactive DNS approval management."""
    # Load cached status
    cache = load_cache_file()
    if not cache or not cache.get("status"):
        # Show error in rofi
        run_command('rofi -e "No DNS data available. Run a check first."')
        sys.exit(1)

    status = cache.get("status")
    dns_servers = status.get("dns_servers", []) if status else []

    if not dns_servers:
        run_command('rofi -e "No DNS servers found in cached status."')
        sys.exit(1)

    # Get current approved list
    approved_ips = cache.get("approved_dns_ips", [])

    # Record initial mtime for conflict detection
    if not CACHE_FILE.exists():
        sys.exit(1)
    initial_mtime = CACHE_FILE.stat().st_mtime

    # Build rofi options and index mapping
    rofi_lines = []
    index_to_server = {}  # Map rofi index -> dns_server
    mullvad_indices = []  # Track Mullvad DNS indices (non-selectable)

    for idx, server in enumerate(dns_servers):
        ip = server.get("ip", "Unknown")
        org = server.get("organization", "Unknown")
        is_mullvad = server.get("mullvad_dns", False)
        hostname = server.get("mullvad_dns_hostname", "")

        info = hostname if is_mullvad else org

        if is_mullvad:
            # Mullvad DNS: read-only, shown with --- prefix
            rofi_lines.append(f"--- {ip} ({info})")
            mullvad_indices.append(idx)
        else:
            # Non-Mullvad DNS: show checkbox based on approval status
            is_approved = ip in approved_ips
            checkbox = "[✓]" if is_approved else "[ ]"
            rofi_lines.append(f"{checkbox} {ip} ({info})")
            index_to_server[idx] = server

    # Launch rofi with multi-select, using format 'i' to get indices
    rofi_input = "\n".join(rofi_lines)
    rofi_cmd = 'rofi -multi-select -dmenu -p "DNS Servers" -format i -markup-rows'
    result = subprocess.run(
        rofi_cmd,
        shell=True,
        input=rofi_input,
        capture_output=True,
        text=True,
    )

    # User cancelled or no selection
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(0)

    # Parse selected indices
    selected_indices = []
    for line in result.stdout.strip().split("\n"):
        try:
            idx = int(line.strip())
            # Skip Mullvad DNS indices (shouldn't be selectable, but filter anyway)
            if idx not in mullvad_indices:
                selected_indices.append(idx)
        except ValueError:
            continue

    # Map indices to IPs
    selected_ips = []
    for idx in selected_indices:
        if idx in index_to_server:
            selected_ips.append(index_to_server[idx].get("ip"))

    if not selected_ips:
        sys.exit(0)

    # Check for concurrent modification
    current_mtime = CACHE_FILE.stat().st_mtime
    if current_mtime != initial_mtime:
        run_command(
            'notify-send "DNS Approval Conflict" "Cache file was modified. Please try again."'
        )
        sys.exit(1)

    # Toggle approval for selected IPs
    updated_approved = approved_ips.copy()
    for ip in selected_ips:
        if ip in updated_approved:
            # Unapprove
            updated_approved.remove(ip)
        else:
            # Approve
            updated_approved.append(ip)

    # Save updated approved list
    save_cache_file(approved_dns_ips=updated_approved)
    sys.exit(0)


def waybar_single_check() -> None:
    """Run single check and output waybar JSON once, then exit.

    This is the default behavior for --waybar without --watch.
    Used for waybar modules that poll the script at intervals.

    Loads cached status first for instant output, then performs fresh check.
    """
    verify_cache: Dict[str, bool] = {}
    current_time = time.time()

    # Try to load cached status for instant output
    cache = load_cache_file()
    approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []
    if cache and cache.get("status"):
        cached_status = cache.get("status")
        output = format_waybar_output(
            cached_status, current_time, verify_cache, approved_dns_ips=approved_dns_ips
        )
        print(json.dumps(output), flush=True)

    # Perform fresh check (which saves to cache)
    status = perform_mullvad_checks(quiet=True)
    # Reload approved_dns_ips in case it changed
    cache = load_cache_file()
    approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []
    output = format_waybar_output(
        status, current_time, verify_cache, approved_dns_ips=approved_dns_ips
    )
    print(json.dumps(output), flush=True)
    sys.exit(0)


def continuous_monitor(waybar_output: bool = False):
    """Unified continuous monitoring function.

    Args:
        waybar_output: If True, output JSON format. If False, output console format.

    This function handles both --watch (console) and --waybar --watch (JSON) modes.
    Network state is monitored for instant updates.
    Loads cached status first for instant waybar output.
    Uses threading for async API checks to allow spinner animation.
    """
    if not waybar_output:
        print("Mullvad VPN Status Checker - Continuous Monitoring Mode")
        print("Running continuous monitoring...")
        print("Press Ctrl+C to stop\n")

    last_network_hash = ""
    last_check_time = 0
    last_output_json = None
    status = None
    verify_cache: Dict[str, bool] = {}
    first_check_completed = False  # Track if first fresh check has completed
    loading_frame_index = 0  # Track current frame for loading animation
    last_cache_mtime = 0  # Track cache file modification time

    # Thread management for async checks
    check_thread = None
    check_result = [None]  # Mutable container for thread result
    check_lock = threading.Lock()

    # Load cached status for instant waybar output (with loading spinner)
    approved_dns_ips = []
    if waybar_output:
        cache = load_cache_file()
        approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []
        if cache and cache.get("status"):
            status = cache.get("status")
            current_time = time.time()
            # Show loading spinner since this is cached data, fresh check pending
            output = format_waybar_output(
                status,
                current_time,
                verify_cache,
                loading=True,
                loading_frame_index=loading_frame_index,
                approved_dns_ips=approved_dns_ips,
            )
            output_json = json.dumps(output)
            print(output_json, flush=True)
            last_output_json = output_json
            loading_frame_index += 1

    def run_check_async(quiet: bool, result_container: list, lock: threading.Lock):
        """Run check in background thread and store result."""
        try:
            result = perform_mullvad_checks(quiet=quiet)
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Error in background check: {e}", file=sys.stderr, flush=True)
            import traceback

            traceback.print_exc(file=sys.stderr)

    try:
        while True:
            current_time = time.time()
            current_hash = get_network_state_hash()

            # Check if cache file was modified externally (e.g., by rofi approval)
            if waybar_output and CACHE_FILE.exists():
                current_mtime = CACHE_FILE.stat().st_mtime
                if current_mtime != last_cache_mtime:
                    # Re-read cache and update status immediately
                    cache = load_cache_file()
                    if cache and cache.get("status"):
                        status = cache.get("status")
                    # Update approved DNS list
                    approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []
                    last_cache_mtime = current_mtime

            # Check if background thread completed
            if check_thread is not None:
                if not check_thread.is_alive():
                    # Retrieve result from thread
                    with check_lock:
                        if check_result[0] is not None:
                            status = check_result[0]
                            first_check_completed = True
                            check_result[0] = None  # Clear for next check

                            if not waybar_output:
                                # Console output mode
                                print("\n" + "=" * 50)
                                print("CURRENT STATUS")
                                print("=" * 50)
                                detailed = format_detailed_status(
                                    status, current_time, verify_cache, approved_dns_ips
                                )
                                print(detailed)

                                # Show next check time
                                next_check = int(
                                    MULLVAD_CHECK_INTERVAL
                                    - (time.time() - last_check_time)
                                )
                                print(
                                    f"\nNext check in {next_check}s (or on network change)"
                                )

                    check_thread = None  # Clear thread reference

            # Trigger check if network changed or timer elapsed or first run
            should_check = (
                current_hash != last_network_hash
                or current_time - last_check_time >= MULLVAD_CHECK_INTERVAL
                or status is None
            ) and check_thread is None  # Don't start new check if one is running

            if should_check:
                if (
                    not waybar_output
                    and current_hash != last_network_hash
                    and last_network_hash
                ):
                    print("\n⚡ Network state changed - triggering check")

                # Clear verify cache on new check
                verify_cache.clear()

                # Start check in background thread
                check_thread = threading.Thread(
                    target=run_check_async,
                    args=(waybar_output, check_result, check_lock),
                    daemon=True,
                )
                check_thread.start()
                last_check_time = current_time
                last_network_hash = current_hash

            if waybar_output:
                # JSON output mode - output only if changed
                # Show loading spinner only during first check, not on periodic refreshes
                is_loading = (
                    check_thread is not None
                    and check_thread.is_alive()
                    and not first_check_completed
                )

                output = format_waybar_output(
                    status,
                    current_time,
                    verify_cache,
                    loading=is_loading,
                    loading_frame_index=loading_frame_index,
                    approved_dns_ips=approved_dns_ips,
                )
                output_json = json.dumps(output)

                if output_json != last_output_json:
                    print(output_json, flush=True)
                    last_output_json = output_json

                # Increment frame index for animation (cycles through frames)
                if is_loading:
                    loading_frame_index += 1

            # Use shorter sleep interval when loading spinner is active for faster animation
            sleep_interval = (
                0.10 if (waybar_output and is_loading) else NETWORK_CHECK_INTERVAL
            )
            time.sleep(sleep_interval)

    except KeyboardInterrupt:
        if not waybar_output:
            print("\n\nStopped by user")
        sys.exit(0)
    except Exception as e:
        # Log errors to stderr
        print(f"Monitoring error: {e}", file=sys.stderr)
        sys.exit(1)


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Mullvad VPN Status Checker - Monitor VPN connection security",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Single check with console output
  %(prog)s --watch            # Continuous console monitoring
  %(prog)s --waybar           # Single waybar JSON output
  %(prog)s --waybar --watch   # Continuous waybar JSON monitoring
  %(prog)s --approve-dns      # Save current DNS servers to approved list
        """,
    )

    parser.add_argument(
        "-w",
        "--watch",
        action="store_true",
        help="Enable continuous monitoring (combine with --waybar for continuous JSON output)",
    )

    parser.add_argument(
        "--approve-dns",
        action="store_true",
        help="Save current DNS servers to approved list file and exit",
    )

    parser.add_argument(
        "--approve-dns-interactive",
        action="store_true",
        help="Launch rofi for interactive DNS approval management",
    )

    parser.add_argument(
        "--waybar",
        action="store_true",
        help="Output waybar JSON format (single check unless --watch is also specified)",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.approve_dns:
        # DNS approval mode (overrides all other flags)
        approve_dns_mode()
    elif args.approve_dns_interactive:
        # Interactive DNS approval via rofi
        approve_dns_interactive()
    elif args.waybar and args.watch:
        # Continuous JSON monitoring (for waybar persistent modules)
        continuous_monitor(waybar_output=True)
    elif args.waybar:
        # Single JSON output (for waybar polling modules)
        waybar_single_check()
    elif args.watch:
        # Continuous console monitoring
        continuous_monitor(waybar_output=False)
    else:
        # Single console check
        single_check_mode()
