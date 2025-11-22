#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
# ]
# ///

"""
Mullvad VPN Status Checker - Phase 1

Monitors Mullvad VPN connection via Tailscale exit nodes and detects leaks.

Features:
- IPv4/IPv6 connection verification
- DNS leak detection (6 unique subdomain requests)
- Network topology change detection
- Automatic re-checking on network changes
- 30-second periodic checks

Phase 1: Console output for manual testing
Phase 2: Waybar JSON integration (future)

Usage:
    ./mullvad-status.py                # Single check and exit
    ./mullvad-status.py --watch        # Continuous monitoring mode
    ./mullvad-status.py --approve-dns  # Save current DNS servers to approved list
    ./mullvad-status.py --waybar       # Waybar JSON output mode

The script will run a single check by default.
Use --watch for continuous monitoring. Press Ctrl+C to stop.
"""

import argparse
import hashlib
import json
import requests
import subprocess
import sys
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

ICON_SECURE = ""  # Lock icon when secure
ICON_LEAK = "󱙱"  # Lock failed icon when leaking

# Approved DNS file location
APPROVED_FILE = Path.home() / ".config" / "mullvad-status-dns-approved.json"


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


def check_ipv6() -> Optional[str]:
    """Check IPv6 connection via Mullvad API.

    Returns IPv6 address if available, None otherwise.
    IPv6 may not be available on all networks.
    """
    try:
        response = requests.get(
            "https://ipv6.am.i.mullvad.net/json", timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            data = response.json()
            return data.get("ip")
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


def load_dns_approved() -> List[str]:
    """Load DNS approved list from file.

    Returns list of approved DNS server IPs.
    """
    if not APPROVED_FILE.exists():
        return []

    try:
        with open(APPROVED_FILE, "r") as f:
            data = json.load(f)
            return data.get("approved_ips", [])
    except Exception as e:
        print(f"Error loading DNS approved list: {e}", file=sys.stderr)
        return []


def save_dns_approved(dns_servers: List[Dict]) -> None:
    """Save DNS server IPs to approved list file.

    Args:
        dns_servers: List of DNS server dictionaries from Mullvad API
    """
    approved_ips = [server.get("ip") for server in dns_servers if server.get("ip")]

    # Create parent directory if needed
    APPROVED_FILE.parent.mkdir(parents=True, exist_ok=True)

    data = {
        "approved_ips": approved_ips,
        "created_at": time.time(),
        "servers": dns_servers,  # Store full server info for reference
    }

    with open(APPROVED_FILE, "w") as f:
        json.dump(data, f, indent=2)


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
    ipv6 = check_ipv6()
    if ipv6:
        ipv6_verified = verify_ip(ipv6)
        if not ipv6_verified:
            issues.append("IPv6 leak detected - not using Mullvad exit IP")
            if not quiet:
                print(f"  ✗ IPv6: {ipv6} (NOT MULLVAD)")
        else:
            if not quiet:
                print(f"  ✓ IPv6: {ipv6}")
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

    return {
        "secure": is_secure,
        "issues": issues,
        "ipv4_data": ipv4_data,
        "ipv6": ipv6,
        "dns_servers": dns_servers,
        "timestamp": timestamp,
    }


def format_detailed_status(
    status: Optional[Dict], current_time: float, verify_cache: Optional[Dict] = None
) -> str:
    """Format detailed status information for display.

    Similar to what will be shown in waybar tooltip.
    """
    if verify_cache is None:
        verify_cache = {}

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
    ipv6 = status.get("ipv6")
    if ipv6:
        is_verified = safe_verify_ip(ipv6, verify_cache)
        check = "✓" if is_verified else "✗"
        lines.append(f"IPv6: {check} {ipv6}")
    else:
        lines.append("IPv6: Not available")

    lines.append("")

    # DNS servers
    dns_servers = status.get("dns_servers", [])
    if dns_servers:
        lines.append(f"DNS Servers ({len(dns_servers)}):")
        for server in dns_servers:
            ip = server.get("ip", "Unknown")
            is_mullvad = server.get("mullvad_dns", False)
            hostname = server.get("mullvad_dns_hostname", "")
            org = server.get("organization", "")

            check = "✓" if is_mullvad else "✗"
            info = hostname if is_mullvad else org
            lines.append(f"  {check} {ip} ({info})")
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
    status: Optional[Dict], current_time: float, verify_cache: Optional[Dict] = None
) -> Dict:
    """Format status for waybar JSON output.

    Returns dict with:
    - text: Icon string
    - tooltip: Detailed status
    - class: List of CSS classes
    - alt: Alternative text identifier
    """
    if verify_cache is None:
        verify_cache = {}

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

    # Generate tooltip using existing function
    tooltip = format_detailed_status(status, current_time, verify_cache)

    # Determine icon and alt
    icon = ICON_SECURE if is_secure else ICON_LEAK
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

    print("\n" + "=" * 50)
    print("FINAL STATUS")
    print("=" * 50)
    detailed = format_detailed_status(status, time.time())
    print(detailed)

    # Exit with appropriate code
    exit_code = 0 if status.get("secure", False) else 1
    sys.exit(exit_code)


def approve_dns_mode() -> None:
    """Run DNS check, save servers to approved list, and exit."""
    print("\n" + "=" * 50)
    print("DNS APPROVAL MODE")
    print("=" * 50)

    print("\nRunning DNS checks to capture current servers...")
    dns_servers = check_dns_leaks()

    if not dns_servers:
        print("\n✗ No DNS servers detected. Cannot create approved list.")
        sys.exit(1)

    print(f"\nDetected {len(dns_servers)} DNS server(s):")
    for server in dns_servers:
        ip = server.get("ip", "Unknown")
        org = server.get("organization", "Unknown")
        is_mullvad = server.get("mullvad_dns", False)
        hostname = server.get("mullvad_dns_hostname", "")

        check = "✓" if is_mullvad else "✗"
        info = hostname if is_mullvad else org
        print(f"  {check} {ip} ({info})")

    # Save to approved list
    save_dns_approved(dns_servers)

    print(f"\n✓ Saved {len(dns_servers)} DNS server(s) to approved list")
    print(f"  Location: {APPROVED_FILE}")
    print("\nThese servers will be ignored in future checks.")
    sys.exit(0)


def main_test_loop():
    """Test loop for Phase 1 - runs checks periodically.

    In Phase 2, this will be replaced with waybar JSON output.
    """
    print("Mullvad VPN Status Checker - Continuous Monitoring Mode")
    print("Running continuous monitoring...")
    print("Press Ctrl+C to stop\n")

    last_network_hash = ""
    last_check_time = 0
    status = None

    try:
        while True:
            current_time = time.time()
            current_hash = get_network_state_hash()

            # Trigger check if network changed or timer elapsed
            should_check = (
                current_hash != last_network_hash
                or current_time - last_check_time >= MULLVAD_CHECK_INTERVAL
                or status is None  # First run
            )

            if should_check:
                if current_hash != last_network_hash and last_network_hash:
                    print("\n⚡ Network state changed - triggering check")

                status = perform_mullvad_checks()
                last_check_time = current_time
                last_network_hash = current_hash

                print("\n" + "=" * 50)
                print("CURRENT STATUS")
                print("=" * 50)
                detailed = format_detailed_status(status, current_time)
                print(detailed)

                # Show next check time
                next_check = int(
                    MULLVAD_CHECK_INTERVAL - (time.time() - last_check_time)
                )
                print(f"\nNext check in {next_check}s (or on network change)")

            time.sleep(NETWORK_CHECK_INTERVAL)

    except KeyboardInterrupt:
        print("\n\nStopped by user")


def waybar_mode():
    """Waybar continuous monitoring mode - JSON output only.

    Runs continuously, outputting JSON to stdout only when status changes.
    Errors go to stderr. Network state is monitored for instant updates.
    """
    last_network_hash = ""
    last_check_time = 0
    last_output_json = None
    status = None
    verify_cache: Dict[str, bool] = {}

    try:
        while True:
            current_time = time.time()
            current_hash = get_network_state_hash()

            # Trigger check if network changed or timer elapsed or first run
            should_check = (
                current_hash != last_network_hash
                or current_time - last_check_time >= MULLVAD_CHECK_INTERVAL
                or status is None
            )

            if should_check:
                # Clear verify cache on new check
                verify_cache.clear()
                status = perform_mullvad_checks(quiet=True)
                last_check_time = current_time
                last_network_hash = current_hash

            # Format and output if changed
            output = format_waybar_output(status, current_time, verify_cache)
            output_json = json.dumps(output)

            if output_json != last_output_json:
                print(output_json, flush=True)
                last_output_json = output_json

            time.sleep(NETWORK_CHECK_INTERVAL)

    except KeyboardInterrupt:
        # Silent exit on Ctrl+C
        sys.exit(0)
    except Exception as e:
        # Log errors to stderr
        print(f"Waybar mode error: {e}", file=sys.stderr)
        sys.exit(1)


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Mullvad VPN Status Checker - Monitor VPN connection security",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Run single check and exit
  %(prog)s --watch            # Continuous monitoring mode
  %(prog)s --approve-dns      # Save current DNS servers to approved list
  %(prog)s --waybar           # Waybar JSON output mode
        """,
    )

    parser.add_argument(
        "-w",
        "--watch",
        action="store_true",
        help="Enable continuous monitoring mode (default: single check and exit)",
    )

    parser.add_argument(
        "--approve-dns",
        action="store_true",
        help="Save current DNS servers to approved list file and exit",
    )

    parser.add_argument(
        "--waybar",
        action="store_true",
        help="Enable waybar JSON output mode (continuous monitoring)",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.approve_dns:
        approve_dns_mode()
    elif args.waybar:
        waybar_mode()
    elif args.watch:
        main_test_loop()
    else:
        single_check_mode()
