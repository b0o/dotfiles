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


if __name__ == "__main__":
    print("Mullvad VPN Status Checker - Phase 1")

    print("\n--- DNS Leak Check ---")
    dns_servers = check_dns_leaks()

    if dns_servers:
        print(f"\nFound {len(dns_servers)} unique DNS server(s):")
        for server in dns_servers:
            ip = server.get("ip", "Unknown")
            is_mullvad = server.get("mullvad_dns", False)
            hostname = server.get("mullvad_dns_hostname", "")
            org = server.get("organization", "")
            country = server.get("country", "")

            status = "✓" if is_mullvad else "✗"
            info = hostname if is_mullvad else org
            print(f"  {status} {ip} - {info} ({country})")

        # Check for leaks
        has_leak = any(not s.get("mullvad_dns", False) for s in dns_servers)
        if has_leak:
            print("\n⚠ DNS LEAK DETECTED - Non-Mullvad DNS servers found")
        else:
            print("\n✓ No DNS leaks - All servers are Mullvad")
    else:
        print("✗ DNS leak check failed")
