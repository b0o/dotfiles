#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
# ]
# ///

"""
Mullvad VPN Status Checker

Monitors Mullvad VPN connection and detects IP/DNS leaks.
Phase 1: Console output for testing.
"""

import hashlib
import json
import requests
import subprocess
import time
import uuid
from pathlib import Path
from typing import Dict, List, Optional


def run_command(cmd: str, timeout: int = 5) -> Optional[str]:
    """Run a shell command and return its output."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, subprocess.SubprocessError):
        pass
    return None


# Constants
NETWORK_CHECK_INTERVAL = 1.0    # Check local network state every second
MULLVAD_CHECK_INTERVAL = 30.0   # Full API check every 30 seconds
STALE_DATA_THRESHOLD = 300      # 5 minutes before marking data as stale
DNS_LEAK_REQUESTS = 6           # Number of DNS leak check requests
REQUEST_TIMEOUT = 6             # HTTP request timeout in seconds

ICON_SECURE = ""     # Lock icon when secure
ICON_LEAK = "󱙱"       # Lock failed icon when leaking


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
            "https://ipv4.am.i.mullvad.net/json",
            timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            return response.json()
    except Exception as e:
        print(f"IPv4 check error: {e}")
    return None


def check_ipv6() -> Optional[str]:
    """Check IPv6 connection via Mullvad API.

    Returns IPv6 address if available, None otherwise.
    IPv6 may not be available on all networks.
    """
    try:
        response = requests.get(
            "https://ipv6.am.i.mullvad.net/json",
            timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            data = response.json()
            return data.get("ip")
    except Exception as e:
        # IPv6 not available is normal, don't print error
        pass
    return None


def verify_ip(ip: str) -> bool:
    """Verify if an IP address is a Mullvad exit IP.

    Uses the check-ip endpoint to double-check IP addresses.
    """
    try:
        response = requests.get(
            f"https://am.i.mullvad.net/check-ip/{ip}",
            timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            data = response.json()
            return data.get("mullvad_exit_ip", False)
    except Exception as e:
        print(f"IP verification error for {ip}: {e}")
    return False


def check_dns_leaks() -> List[Dict]:
    """Check for DNS leaks using UUID-based subdomains.

    Makes multiple requests to unique subdomains. Each DNS server
    that resolves the request will be reported by the API.

    Returns list of unique DNS servers (deduplicated by IP).
    """
    dns_servers = []

    print(f"Running {DNS_LEAK_REQUESTS} DNS leak checks...", end="", flush=True)

    for i in range(DNS_LEAK_REQUESTS):
        try:
            uuid_str = str(uuid.uuid4())
            response = requests.get(
                f"https://{uuid_str}.dnsleak.am.i.mullvad.net",
                headers={"Accept": "application/json"},
                timeout=REQUEST_TIMEOUT
            )
            if response.ok:
                # API returns list of DNS servers
                servers = response.json()
                if isinstance(servers, list):
                    dns_servers.extend(servers)
            print(".", end="", flush=True)
        except Exception as e:
            print("x", end="", flush=True)
            continue

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
        print(f"Error getting network state: {e}")
        return ""


def perform_mullvad_checks() -> Dict:
    """Run all Mullvad API checks and return combined status.

    Returns dict with:
    - secure: bool (overall security status)
    - issues: list of problem descriptions
    - ipv4_data: IPv4 connection data
    - ipv6: IPv6 address or None
    - dns_servers: List of DNS servers
    - timestamp: When check was performed
    """
    print("\n" + "="*50)
    print("PERFORMING MULLVAD SECURITY CHECKS")
    print("="*50)

    timestamp = time.time()
    issues = []

    # IPv4 check
    print("\n[1/3] Checking IPv4...")
    ipv4_data = check_ipv4()
    if not ipv4_data:
        issues.append("IPv4 check failed")
    elif not ipv4_data.get("mullvad_exit_ip"):
        issues.append("IPv4 leak detected - not using Mullvad exit IP")
        print(f"  ✗ IP: {ipv4_data.get('ip')} (NOT MULLVAD)")
    else:
        print(f"  ✓ IP: {ipv4_data.get('ip')} via {ipv4_data.get('mullvad_exit_ip_hostname')}")

    # IPv6 check
    print("\n[2/3] Checking IPv6...")
    ipv6 = check_ipv6()
    if ipv6:
        ipv6_verified = verify_ip(ipv6)
        if not ipv6_verified:
            issues.append("IPv6 leak detected - not using Mullvad exit IP")
            print(f"  ✗ IPv6: {ipv6} (NOT MULLVAD)")
        else:
            print(f"  ✓ IPv6: {ipv6}")
    else:
        print("  ○ IPv6 not available (OK)")

    # DNS leak check
    print("\n[3/3] Checking DNS...")
    dns_servers = check_dns_leaks()
    has_non_mullvad_dns = any(
        not server.get("mullvad_dns", False)
        for server in dns_servers
    )
    if has_non_mullvad_dns:
        issues.append("DNS leak detected - non-Mullvad DNS servers found")
        non_mullvad = [s for s in dns_servers if not s.get("mullvad_dns", False)]
        for server in non_mullvad:
            print(f"  ✗ {server.get('ip')} ({server.get('organization', 'Unknown')})")
    else:
        print(f"  ✓ All {len(dns_servers)} DNS server(s) are Mullvad")

    # Overall status
    is_secure = len(issues) == 0

    print("\n" + "="*50)
    if is_secure:
        print("✓ SECURE - All checks passed")
    else:
        print("✗ INSECURE - Issues detected:")
        for issue in issues:
            print(f"  • {issue}")
    print("="*50)

    return {
        "secure": is_secure,
        "issues": issues,
        "ipv4_data": ipv4_data,
        "ipv6": ipv6,
        "dns_servers": dns_servers,
        "timestamp": timestamp,
    }


def format_detailed_status(status: Optional[Dict], current_time: float) -> str:
    """Format detailed status information for display.

    Similar to what will be shown in waybar tooltip.
    """
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
        is_verified = verify_ip(ipv6)
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


if __name__ == "__main__":
    print("Mullvad VPN Status Checker - Phase 1")

    status = perform_mullvad_checks()

    print("\n" + "="*50)
    print("FORMATTED OUTPUT (for waybar tooltip)")
    print("="*50)
    detailed = format_detailed_status(status, time.time())
    print(detailed)
