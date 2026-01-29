"""Main monitoring loop for Claude usage monitor."""

import atexit
import json
import signal
import sys
import threading
import time
from datetime import datetime
from typing import Any, Dict, Optional

from .api import fetch_usage_data
from .constants import CHECK_INTERVAL, OUTPUT_INTERVAL
from .formatting import format_waybar_output
from .history import (
    check_existing_instance,
    clear_pid,
    load_current_snapshots,
    load_history,
    save_pid,
    set_config,
    signal_running_instance,
    update_history,
)


def monitor(prefer_source_override: Optional[str] = None) -> None:
    """Main monitoring loop."""
    # Check if another instance is already running
    existing_pid = check_existing_instance()
    if existing_pid:
        print(
            f"Another instance is already running (PID {existing_pid})", file=sys.stderr
        )
        sys.exit(1)

    last_check_time: Optional[datetime] = None
    last_output_json: Optional[str] = None
    usage_data: Optional[Dict[str, Any]] = None
    profile_data: Optional[Dict[str, Any]] = None
    current_token: Optional[str] = None
    cred_source: Optional[str] = None
    cred_is_fallback: bool = False
    has_token: bool = True
    check_thread: Optional[threading.Thread] = None
    check_result: list = [(None, None, None, None, False, True)]
    check_lock = threading.Lock()
    expired_5h_triggered: bool = False
    expired_7d_triggered: bool = False
    last_check_start: float = 0.0
    signal_received: list = [False]  # Use list for mutability in signal handler
    # Track usage snapshots for timeline chart - load from history if available
    loaded_snapshots, loaded_reset = load_current_snapshots()
    usage_snapshots: list[tuple[float, float]] = loaded_snapshots
    last_5h_reset: int = loaded_reset

    def get_prefer_source() -> Optional[str]:
        """Get prefer_source from override or config."""
        if prefer_source_override:
            return prefer_source_override
        history = load_history()
        return history.get("config", {}).get("prefer_source")

    def get_display_mode() -> str:
        """Get display_mode from config."""
        history = load_history()
        return history.get("config", {}).get("display_mode", "normal")

    def handle_refresh_signal(_signum: int, _frame: Any) -> None:
        """Handle SIGUSR1 to trigger refresh."""
        signal_received[0] = True

    def handle_exit_signal(_signum: int, _frame: Any) -> None:
        """Handle SIGTERM/SIGINT to clean up and exit."""
        clear_pid()
        sys.exit(0)

    signal.signal(signal.SIGUSR1, handle_refresh_signal)
    signal.signal(signal.SIGTERM, handle_exit_signal)
    signal.signal(signal.SIGINT, handle_exit_signal)

    def run_check_async(
        result_container: list, lock: threading.Lock, prev_token: Optional[str]
    ) -> None:
        try:
            result = fetch_usage_data(prev_token, get_prefer_source())
            with lock:
                result_container[0] = result
        except Exception as e:
            print(f"Background check error: {e}", file=sys.stderr)

    def start_check() -> None:
        nonlocal check_thread, last_check_start
        check_thread = threading.Thread(
            target=run_check_async,
            args=(check_result, check_lock, current_token),
            daemon=True,
        )
        check_thread.start()
        last_check_start = time.time()

    # Save PID and register cleanup
    save_pid()
    atexit.register(clear_pid)

    # Start initial check immediately
    start_check()

    try:
        while True:
            current_time = time.time()

            # Check if signal received (triggers immediate refresh)
            if signal_received[0]:
                signal_received[0] = False
                if check_thread is None or not check_thread.is_alive():
                    start_check()

            # Check if background thread completed
            if check_thread is not None and not check_thread.is_alive():
                with check_lock:
                    if check_result[0] is not None:
                        data, profile, token, source, is_fallback, token_valid = (
                            check_result[0]
                        )
                        has_token = token_valid
                        if data is not None:
                            # Check if 5h session reset (new session started)
                            if data["5h_reset"] != last_5h_reset:
                                usage_snapshots.clear()
                                last_5h_reset = data["5h_reset"]
                            # Record snapshot for timeline chart
                            usage_snapshots.append(
                                (current_time, data["5h_utilization"])
                            )
                            usage_data = data
                            current_token = token
                            cred_source = source
                            cred_is_fallback = is_fallback
                            # Only update profile if we got new one (token changed)
                            if profile is not None:
                                profile_data = profile
                            # Reset expiry triggers when we get new data
                            expired_5h_triggered = False
                            expired_7d_triggered = False
                            # Update history with profile info and snapshots
                            update_history(
                                data,
                                profile if profile else profile_data,
                                usage_snapshots,
                            )
                        last_check_time = datetime.now()
                        check_result[0] = None
                check_thread = None

            # Check if either timer has expired and trigger a check
            should_check = False
            if usage_data:
                if (
                    usage_data["5h_reset"] > 0
                    and current_time >= usage_data["5h_reset"]
                ):
                    if not expired_5h_triggered:
                        expired_5h_triggered = True
                        should_check = True
                if (
                    usage_data["7d_reset"] > 0
                    and current_time >= usage_data["7d_reset"]
                ):
                    if not expired_7d_triggered:
                        expired_7d_triggered = True
                        should_check = True

            # Start new check if interval elapsed or timer expired
            if (should_check or current_time - last_check_start >= CHECK_INTERVAL) and (
                check_thread is None or not check_thread.is_alive()
            ):
                start_check()

            # Determine alternation cycle: 15s primary, 15s alternate
            cycle_position = int(current_time) % 30
            show_alternate = cycle_position >= 15

            # Format and output
            prefer_source = get_prefer_source()
            display_mode = get_display_mode()
            output = format_waybar_output(
                usage_data,
                last_check_time,
                show_alternate,
                has_token,
                profile_data,
                cred_source,
                cred_is_fallback,
                prefer_source,
                display_mode,
                usage_snapshots,
            )
            if output:
                output_json = json.dumps(output)
                if output_json != last_output_json:
                    print(output_json, flush=True)
                    last_output_json = output_json

            time.sleep(OUTPUT_INTERVAL)

    except KeyboardInterrupt:
        clear_pid()
        sys.exit(0)


def main() -> None:
    """Main entry point with CLI argument parsing."""
    import argparse

    parser = argparse.ArgumentParser(description="Claude usage monitor for Waybar")

    # Runtime preference override (for the monitor)
    runtime_group = parser.add_mutually_exclusive_group()
    runtime_group.add_argument(
        "--prefer-cc",
        action="store_true",
        help="Prefer Claude Code credentials (falls back to OpenCode)",
    )
    runtime_group.add_argument(
        "--prefer-oc",
        action="store_true",
        help="Prefer OpenCode credentials (falls back to Claude Code)",
    )

    # One-shot commands to configure and signal running instance
    action_group = parser.add_mutually_exclusive_group()
    action_group.add_argument(
        "--set-prefer-cc",
        action="store_true",
        help="Set preference to Claude Code and signal refresh",
    )
    action_group.add_argument(
        "--set-prefer-oc",
        action="store_true",
        help="Set preference to OpenCode and signal refresh",
    )
    action_group.add_argument(
        "--set-prefer-auto",
        action="store_true",
        help="Set preference to auto (try Claude Code first) and signal refresh",
    )
    action_group.add_argument(
        "--refresh",
        action="store_true",
        help="Signal running instance to refresh",
    )
    action_group.add_argument(
        "--set-mode-compact",
        action="store_true",
        help="Set display mode to compact",
    )
    action_group.add_argument(
        "--set-mode-normal",
        action="store_true",
        help="Set display mode to normal",
    )
    action_group.add_argument(
        "--set-mode-expanded",
        action="store_true",
        help="Set display mode to expanded",
    )
    action_group.add_argument(
        "--cycle-mode-up",
        action="store_true",
        help="Cycle display mode: compact -> normal -> expanded -> compact",
    )
    action_group.add_argument(
        "--cycle-mode-down",
        action="store_true",
        help="Cycle display mode: compact <- normal <- expanded <- compact",
    )

    args = parser.parse_args()

    # Handle one-shot config commands
    if args.set_prefer_cc:
        set_config("prefer_source", "cc")
        print("Set preference to Claude Code")
        return
    elif args.set_prefer_oc:
        set_config("prefer_source", "oc")
        print("Set preference to OpenCode")
        return
    elif args.set_prefer_auto:
        set_config("prefer_source", None)
        print("Set preference to auto")
        return
    elif args.refresh:
        if signal_running_instance():
            print("Signaled running instance to refresh")
        else:
            print("No running instance found")
        return
    elif args.set_mode_compact:
        set_config("display_mode", "compact")
        print("Set display mode to compact")
        return
    elif args.set_mode_normal:
        set_config("display_mode", "normal")
        print("Set display mode to normal")
        return
    elif args.set_mode_expanded:
        set_config("display_mode", "expanded")
        print("Set display mode to expanded")
        return
    elif args.cycle_mode_up:
        history = load_history()
        current = history.get("config", {}).get("display_mode", "normal")
        modes = ["compact", "normal", "expanded"]
        next_mode = modes[(modes.index(current) + 1) % len(modes)]
        set_config("display_mode", next_mode)
        print(f"Display mode: {next_mode}")
        return
    elif args.cycle_mode_down:
        history = load_history()
        current = history.get("config", {}).get("display_mode", "normal")
        modes = ["compact", "normal", "expanded"]
        next_mode = modes[(modes.index(current) - 1) % len(modes)]
        set_config("display_mode", next_mode)
        print(f"Display mode: {next_mode}")
        return

    # Start monitor with optional runtime override
    prefer_source = None
    if args.prefer_cc:
        prefer_source = "cc"
    elif args.prefer_oc:
        prefer_source = "oc"

    monitor(prefer_source)
