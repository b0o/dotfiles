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
    print("\nTesting network state hashing:")

    # Get initial hash
    hash1 = get_network_state_hash()
    print(f"Network state hash: {hash1[:16]}...")
    assert len(hash1) == 64, "Hash should be 64 chars (SHA256)"

    # Get hash again (should be same)
    hash2 = get_network_state_hash()
    assert hash1 == hash2, "Hash should be consistent"

    print(f"Hash is consistent: {hash1 == hash2}")
    print("\n✓ Network state hashing working")
