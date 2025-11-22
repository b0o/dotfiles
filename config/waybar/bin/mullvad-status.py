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

NETWORK_CHECK_INTERVAL = 1.0
MULLVAD_CHECK_INTERVAL = 30.0
DNS_LEAK_REQUESTS = 6
REQUEST_TIMEOUT = 6

ICON_UNKNOWN = "󰝳"
ICON_SECURE = "󰌾"
ICON_LEAK = "󱙱"
ICON_LOADING_FRAMES = ["", "", "", "", "", ""]

CACHE_DIR = Path(os.getenv("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE_FILE = CACHE_DIR / "mullvad-waybar-status.json"


def check_ip(endpoint: str, log_errors: bool = True) -> dict | None:
    try:
        response = requests.get(
            f"https://{endpoint}.am.i.mullvad.net/json", timeout=REQUEST_TIMEOUT
        )
        if response.ok:
            return response.json()
    except Exception as e:
        if log_errors:
            print(f"{endpoint.upper()} check error: {e}", file=sys.stderr)
    return None


def check_dns() -> list[dict]:
    try:
        dns_servers = []
        for _ in range(DNS_LEAK_REQUESTS):
            uuid_str = str(uuid.uuid4())
            response = requests.get(
                f"https://{uuid_str}.dnsleak.am.i.mullvad.net",
                headers={"Accept": "application/json"},
                timeout=REQUEST_TIMEOUT,
            )
            if response.ok:
                servers = response.json()
                if isinstance(servers, list):
                    dns_servers.extend(servers)
        unique_servers = {}
        for server in dns_servers:
            ip = server.get("ip")
            if ip and ip not in unique_servers:
                unique_servers[ip] = server
        return list(unique_servers.values())
    except Exception as e:
        print(f"DNS leak check error: {e}", file=sys.stderr)
        return []


def get_network_state_hash() -> str:
    try:
        result = subprocess.run(
            ["ip", "route", "show"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )
        return hashlib.sha256(result.stdout.encode()).hexdigest()
    except Exception:
        return ""


def read_cache() -> dict | None:
    if not CACHE_FILE.exists():
        return None
    try:
        with open(CACHE_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading cache file: {e}", file=sys.stderr)
        return None


def write_cache(
    status: dict | None = None,
    approved_dns_ips: list[str] | None = None,
):
    existing = read_cache() or {}
    cache_data = {
        "status": status if status is not None else existing.get("status"),
        "approved_dns_ips": (
            approved_dns_ips
            if approved_dns_ips is not None
            else existing.get("approved_dns_ips", [])
        ),
    }
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with open(CACHE_FILE, "w") as f:
        json.dump(cache_data, f, indent=2)


def get_approved_dns_ips() -> list[str]:
    cache = read_cache()
    return cache.get("approved_dns_ips", []) if cache else []


def diagnose_issues(
    ipv4_status: dict | None,
    ipv6_status: dict | None,
    dns_servers: list[dict],
    approved_ips: list[str],
) -> list[str]:
    issues = []
    if ipv4_status:
        if not ipv4_status.get("mullvad_exit_ip", False):
            issues.append("IPv4 leak detected - not using Mullvad exit IP")
    else:
        issues.append("IPv4 check failed")

    if ipv6_status and not ipv6_status.get("mullvad_exit_ip", False):
        issues.append("IPv6 leak detected - not using Mullvad exit IP")

    non_approved_servers = [s for s in dns_servers if s.get("ip") not in approved_ips]
    if any(not s.get("mullvad_dns", False) for s in non_approved_servers):
        issues.append("DNS leak detected - non-Mullvad DNS servers found")

    return issues


def check_security(
    status: dict | None = None,
    approved_ips: list[str] | None = None,
) -> dict:
    if approved_ips is None:
        approved_ips = get_approved_dns_ips()

    if status is None:
        status = {
            "ipv4": check_ip("ipv4"),
            "ipv6": check_ip("ipv6", log_errors=False),
            "dns": check_dns(),
        }

    issues = diagnose_issues(
        status.get("ipv4"),
        status.get("ipv6"),
        status.get("dns", []),
        approved_ips,
    )

    status["issues"] = issues
    status["secure"] = len(issues) == 0

    cache = read_cache()
    old_status = cache.get("status") if cache else None
    if not old_status or any(
        old_status.get(k) != status.get(k)
        for k in ["secure", "issues", "ipv4", "ipv6", "dns"]
    ):
        write_cache(status=status)

    return status


def categorize_dns_servers(
    dns_servers: list[dict],
    approved_ips: list[str],
) -> tuple[list[tuple[str, str]], list[tuple[str, str]], list[tuple[str, str]]]:
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
        elif ip in approved_ips:
            approved_servers.append((ip, org))
        else:
            unknown_servers.append((ip, org))

    return mullvad_servers, unknown_servers, approved_servers


def format_ip_section(data: dict | None, label: str) -> list[str]:
    if not data:
        return (
            [f"{label}: ✗ Check failed"]
            if label == "IPv4"
            else [f"{label}: Not available"]
        )

    lines = []
    ip = data.get("ip", "Unknown")
    is_mullvad = data.get("mullvad_exit_ip", False)
    check = "✓" if is_mullvad else "✗"
    lines.append(f"{label}: {check} {ip}")

    server = data.get("mullvad_exit_ip_hostname", "")
    city = data.get("city", "")
    country = data.get("country", "")
    protocol = data.get("mullvad_server_type", "")
    provider = data.get("organization", "")

    if server and server != "Unknown":
        lines.append(f"  Server: {server}")
    if city and country:
        lines.append(f"  Location: {city}, {country}")
    if protocol:
        lines.append(f"  Protocol: {protocol}")
    if provider:
        lines.append(f"  Provider: {provider}")

    return lines


def format_tooltip(status: dict | None, approved_dns_ips: list[str]) -> str:
    if not status:
        return "Mullvad VPN: No data available"

    lines = []
    is_secure = status.get("secure", False)
    icon = ICON_SECURE if is_secure else ICON_LEAK
    status_text = "SECURE" if is_secure else "INSECURE"
    lines.append(f"{icon} Mullvad VPN: {status_text}")
    lines.append("")

    lines.extend(format_ip_section(status.get("ipv4"), "IPv4"))
    lines.append("")
    lines.extend(format_ip_section(status.get("ipv6"), "IPv6"))
    lines.append("")

    dns_servers = status.get("dns", [])
    if dns_servers:
        mullvad, unknown, approved = categorize_dns_servers(
            dns_servers, approved_dns_ips
        )

        sections_shown = 0
        for servers, title, mark in [
            (mullvad, "Mullvad DNS", "✓"),
            (unknown, "Unknown DNS", "✗"),
            (approved, "Approved DNS", "✓"),
        ]:
            if servers:
                if sections_shown > 0:
                    lines.append("")
                lines.append(f"{title} ({len(servers)}):")
                for ip, info in servers:
                    lines.append(f"  {mark} {ip} ({info})")
                sections_shown += 1

        if sections_shown == 0:
            lines.append("DNS: No servers detected")
    else:
        lines.append("DNS: No data")

    issues = status.get("issues", [])
    if issues:
        lines.append("")
        lines.append("Issues:")
        for issue in issues:
            lines.append(f"  • {issue}")

    return "\n".join(lines)


def get_loading_icon(base_icon: str, frame_index: int) -> str:
    frame = ICON_LOADING_FRAMES[frame_index % len(ICON_LOADING_FRAMES)]
    return f"{base_icon}  {frame}"


def format_waybar_output(
    status: dict | None,
    loading: bool = False,
    loading_frame_index: int = 0,
    approved_dns_ips: list[str] | None = None,
) -> dict:
    approved_dns_ips = approved_dns_ips or []

    if not status:
        if loading:
            return {
                "text": get_loading_icon(ICON_UNKNOWN, loading_frame_index),
                "tooltip": "Loading Mullvad VPN status...",
                "class": ["mullvad", "loading"],
                "alt": "mullvad-loading",
            }
        return {
            "text": ICON_LEAK,
            "tooltip": "Mullvad VPN: No data available",
            "class": ["mullvad", "error"],
            "alt": "mullvad-error",
        }

    is_secure = status.get("secure", False)

    classes = ["mullvad"]
    classes.append("state-secure" if is_secure else "state-leak")
    if loading:
        classes.append("loading")

    tooltip = format_tooltip(status, approved_dns_ips)
    if loading:
        tooltip = "Loading...\n\n" + tooltip

    status_icon = ICON_SECURE if is_secure else ICON_LEAK
    if loading:
        icon = get_loading_icon(status_icon, loading_frame_index)
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


def show_rofi_error(message: str):
    subprocess.run(["rofi", "-e", message])


def show_menu() -> None:
    cache = read_cache()
    if not cache or not cache.get("status"):
        show_rofi_error("No DNS data available. Run a check first.")
        sys.exit(1)

    status = cache.get("status", {})
    dns_servers = status.get("dns", [])
    if not dns_servers:
        show_rofi_error("No DNS servers found in cached status.")
        sys.exit(1)

    approved_ips = cache.get("approved_dns_ips", [])
    if not CACHE_FILE.exists():
        sys.exit(1)
    initial_mtime = CACHE_FILE.stat().st_mtime

    rofi_lines = []
    index_to_server = {}
    mullvad_indices = []

    for idx, server in enumerate(dns_servers):
        ip = server.get("ip", "Unknown")
        org = server.get("organization", "Unknown")
        is_mullvad = server.get("mullvad_dns", False)
        hostname = server.get("mullvad_dns_hostname", "")
        info = hostname if is_mullvad else org

        if is_mullvad:
            rofi_lines.append(f"--- {ip} ({info})")
            mullvad_indices.append(idx)
        else:
            is_approved = ip in approved_ips
            checkbox = "[✓]" if is_approved else "[ ]"
            rofi_lines.append(f"{checkbox} {ip} ({info})")
            index_to_server[idx] = server

    rofi_input = "\n".join(rofi_lines)
    result = subprocess.run(
        [
            "rofi",
            "-multi-select",
            "-dmenu",
            "-p",
            "DNS Servers",
            "-format",
            "i",
            "-markup-rows",
        ],
        input=rofi_input,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(0)

    selected_indices = []
    for line in result.stdout.strip().split("\n"):
        try:
            idx = int(line.strip())
            if idx not in mullvad_indices:
                selected_indices.append(idx)
        except ValueError:
            continue

    selected_ips = [
        index_to_server[idx].get("ip")
        for idx in selected_indices
        if idx in index_to_server
    ]

    if not selected_ips:
        sys.exit(0)

    current_mtime = CACHE_FILE.stat().st_mtime
    if current_mtime != initial_mtime:
        subprocess.run(
            [
                "notify-send",
                "-u",
                "critical",
                "DNS Approval Conflict",
                "Cache file was modified. Please try again.",
            ]
        )
        sys.exit(1)

    updated_approved = approved_ips.copy()
    for ip in selected_ips:
        if ip in updated_approved:
            updated_approved.remove(ip)
        else:
            updated_approved.append(ip)

    write_cache(approved_dns_ips=updated_approved)
    sys.exit(0)


def monitor():
    last_network_hash = ""
    last_check_time = 0
    last_output_json = None
    status = None
    first_check_completed = False
    loading_frame_index = 0
    last_cache_mtime = 0
    check_thread = None
    check_result = [None]
    check_lock = threading.Lock()
    last_secure_state = None

    cache = read_cache()
    approved_dns_ips = cache.get("approved_dns_ips", []) if cache else []
    prev_approved_dns_ips = approved_dns_ips.copy()

    current_time = time.time()
    if cache and cache.get("status"):
        status = cache.get("status", {})
        last_secure_state = status.get("secure", False)

    output = format_waybar_output(
        status,
        loading=True,
        loading_frame_index=loading_frame_index,
        approved_dns_ips=approved_dns_ips,
    )
    output_json = json.dumps(output)
    print(output_json, flush=True)
    last_output_json = output_json
    loading_frame_index += 1

    def run_check_async(result_container: list, lock: threading.Lock):
        try:
            result = check_security()
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Background check error: {e}", file=sys.stderr)

    try:
        while True:
            current_time = time.time()
            current_hash = get_network_state_hash()

            if CACHE_FILE.exists():
                current_mtime = CACHE_FILE.stat().st_mtime
                if current_mtime != last_cache_mtime:
                    cache = read_cache()
                    if cache and cache.get("status"):
                        status = cache.get("status")
                    new_approved = cache.get("approved_dns_ips", []) if cache else []
                    if set(new_approved) != set(prev_approved_dns_ips):
                        if status:
                            status = check_security(status, new_approved)
                            write_cache(status=status)
                        prev_approved_dns_ips = new_approved.copy()
                    approved_dns_ips = new_approved
                    last_cache_mtime = current_mtime

            if check_thread is not None and not check_thread.is_alive():
                with check_lock:
                    if check_result[0] is not None:
                        status = check_result[0]
                        first_check_completed = True
                        check_result[0] = None
                check_thread = None

            if (
                current_hash != last_network_hash
                or current_time - last_check_time >= MULLVAD_CHECK_INTERVAL
            ) and (check_thread is None or not check_thread.is_alive()):
                check_thread = threading.Thread(
                    target=run_check_async,
                    args=(check_result, check_lock),
                    daemon=True,
                )
                check_thread.start()
                last_check_time = current_time
                last_network_hash = current_hash

            if status:
                current_secure_state = status.get("secure", False)
                should_notify = (
                    last_secure_state is None and not current_secure_state
                ) or (
                    last_secure_state is not None
                    and last_secure_state
                    and not current_secure_state
                )
                if should_notify:
                    issues = status.get("issues", [])
                    issue_text = "\n".join(f"• {issue}" for issue in issues)
                    subprocess.run(
                        [
                            "notify-send",
                            "-u",
                            "critical",
                            "Mullvad VPN Security Alert",
                            f"VPN connection is INSECURE\n\n{issue_text}",
                        ]
                    )
                last_secure_state = current_secure_state

            is_loading = (
                check_thread is not None
                and check_thread.is_alive()
                and not first_check_completed
            )

            output = format_waybar_output(
                status,
                loading=is_loading,
                loading_frame_index=loading_frame_index,
                approved_dns_ips=approved_dns_ips,
            )
            output_json = json.dumps(output)

            if output_json != last_output_json:
                print(output_json, flush=True)
                last_output_json = output_json

            if is_loading:
                loading_frame_index += 1

            sleep_interval = 0.10 if is_loading else NETWORK_CHECK_INTERVAL
            time.sleep(sleep_interval)

    except KeyboardInterrupt:
        sys.exit(0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--show-menu", action="store_true", help="Show DNS approval menu"
    )
    args = parser.parse_args()

    if args.show_menu:
        show_menu()
    else:
        monitor()


if __name__ == "__main__":
    main()
