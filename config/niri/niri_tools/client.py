"""Thin client for niri-tools daemon - fire and forget."""

import argparse
import json
import socket
import subprocess
import sys
import time

from .common import SOCKET_PATH

# Daemon auto-start settings
MAX_CONNECT_ATTEMPTS = 10
CONNECT_RETRY_DELAY = 0.1  # seconds


def _get_daemon_command() -> list[str]:
    """Get the command to start the daemon.

    Handles different invocation methods:
    - Entry point (niri-tools): sys.argv[0] is the script path
    - Module (python -m niri_tools): sys.argv[0] is __main__.py path
    """
    argv0 = sys.argv[0]

    # Check if invoked as a module (python -m niri_tools)
    if argv0.endswith("__main__.py") or argv0.endswith("niri_tools"):
        return [sys.executable, "-m", "niri_tools", "daemon"]

    # Entry point script (e.g., ~/.local/bin/niri-tools)
    return [argv0, "daemon"]


def _spawn_daemon() -> bool:
    """Spawn the daemon via niri so it survives this process.

    Returns True if spawn command succeeded.
    """
    daemon_cmd = _get_daemon_command()
    try:
        subprocess.run(
            ["niri", "msg", "action", "spawn", "--", *daemon_cmd],
            check=True,
            capture_output=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to spawn daemon: {e.stderr.decode()}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print("niri command not found", file=sys.stderr)
        return False


def _try_connect() -> socket.socket | None:
    """Try to connect to daemon socket. Returns socket on success, None on failure."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(str(SOCKET_PATH))
        return sock
    except (FileNotFoundError, ConnectionRefusedError):
        sock.close()
        return None


def send_command(command: dict) -> int:
    """Send a command to the daemon. Returns 0 on success, 1 on failure.

    If daemon is not running, attempts to start it and retry connection.
    """
    # First attempt
    sock = _try_connect()

    if sock is None:
        # Daemon not running - try to start it
        print("Daemon not running, starting...", file=sys.stderr)
        if not _spawn_daemon():
            return 1

        # Poll for socket to become available
        for _attempt in range(MAX_CONNECT_ATTEMPTS):
            time.sleep(CONNECT_RETRY_DELAY)
            sock = _try_connect()
            if sock is not None:
                break
        else:
            print(
                f"Daemon failed to start after {MAX_CONNECT_ATTEMPTS * CONNECT_RETRY_DELAY:.1f}s",
                file=sys.stderr,
            )
            return 1

    # Send command
    try:
        sock.sendall((json.dumps(command) + "\n").encode())
        return 0
    except Exception as e:
        print(f"Failed to send command: {e}", file=sys.stderr)
        return 1
    finally:
        sock.close()


def restart_daemon() -> int:
    """Send restart command to the daemon, or start it if not running."""
    sock = _try_connect()
    if sock is None:
        print("Daemon not running, starting...", file=sys.stderr)
        if _spawn_daemon():
            return 0
        return 1

    try:
        sock.sendall((json.dumps({"cmd": "restart"}) + "\n").encode())
        return 0
    except Exception as e:
        print(f"Failed to send restart command: {e}", file=sys.stderr)
        return 1
    finally:
        sock.close()


def daemon_status() -> int:
    """Check and print the daemon status."""
    sock = _try_connect()
    if sock is None:
        print("Daemon is not running")
        return 1

    try:
        sock.sendall((json.dumps({"cmd": "status"}) + "\n").encode())
        # Read response
        response_data = sock.recv(4096)
        if response_data:
            response = json.loads(response_data.decode())
            print("Daemon is running")
            print(f"  PID:    {response.get('pid')} ({response.get('cmdline')})")
            print(
                f"  Parent: {response.get('ppid')} ({response.get('parent_cmdline')})"
            )
            print(f"  Socket: {response.get('socket')}")
        else:
            print("Daemon is running")
        return 0
    except Exception as e:
        print(f"Daemon is running (failed to get details: {e})")
        return 0
    finally:
        sock.close()


def start_daemon() -> int:
    """Start the daemon if not already running."""
    sock = _try_connect()
    if sock is not None:
        sock.close()
        print("Daemon is already running")
        return 0

    print("Starting daemon...")
    if _spawn_daemon():
        return 0
    return 1


def stop_daemon() -> int:
    """Stop the daemon if running."""
    sock = _try_connect()
    if sock is None:
        print("Daemon is not running")
        return 0

    try:
        sock.sendall((json.dumps({"cmd": "stop"}) + "\n").encode())
        print("Daemon stopped")
        return 0
    except Exception as e:
        print(f"Failed to send stop command: {e}", file=sys.stderr)
        return 1
    finally:
        sock.close()


def add_arguments(parser: argparse.ArgumentParser) -> None:
    """Add scratchpad subcommand arguments."""
    sub = parser.add_subparsers(dest="scratchpad_command")

    toggle = sub.add_parser("toggle", help="Toggle a scratchpad")
    toggle.add_argument(
        "name",
        type=str,
        nargs="?",
        default=None,
        help="Name of the scratchpad. If not provided, smart toggle (hide focused or show recent)",
    )

    sub.add_parser("hide", help="Hide the focused scratchpad")

    adopt = sub.add_parser("adopt", help="Adopt an existing window as a scratchpad")
    adopt.add_argument(
        "-w",
        "--window-id",
        type=int,
        default=None,
        help="Window ID to adopt (default: focused window)",
    )
    adopt.add_argument(
        "-n",
        "--name",
        type=str,
        default=None,
        help="Scratchpad name to adopt as (default: prompt with rofi)",
    )

    disown = sub.add_parser("disown", help="Disown a scratchpad window and tile it")
    disown.add_argument(
        "-w",
        "--window-id",
        type=int,
        default=None,
        help="Window ID to disown (default: focused window)",
    )

    sub.add_parser("menu", help="Show scratchpad menu with rofi")

    close = sub.add_parser("close", help="Close a scratchpad window")
    close.add_argument(
        "-w",
        "--window-id",
        type=int,
        default=None,
        help="Window ID to close (default: focused window)",
    )
    close.add_argument(
        "--no-confirm",
        action="store_true",
        help="Skip confirmation prompt",
    )


def main(args: argparse.Namespace) -> int:
    """Handle scratchpad commands by sending to daemon."""
    if args.scratchpad_command == "toggle":
        command: dict[str, str | int | None] = {"cmd": "toggle"}
        if args.name:
            command["name"] = args.name
        return send_command(command)

    elif args.scratchpad_command == "hide":
        return send_command({"cmd": "hide"})

    elif args.scratchpad_command == "adopt":
        command = {"cmd": "adopt"}
        if args.window_id is not None:
            command["window_id"] = args.window_id
        if args.name is not None:
            command["name"] = args.name
        return send_command(command)

    elif args.scratchpad_command == "disown":
        command = {"cmd": "disown"}
        if args.window_id is not None:
            command["window_id"] = args.window_id
        return send_command(command)

    elif args.scratchpad_command == "menu":
        return send_command({"cmd": "menu"})

    elif args.scratchpad_command == "close":
        command = {"cmd": "close", "confirm": not args.no_confirm}
        if args.window_id is not None:
            command["window_id"] = args.window_id
        return send_command(command)

    else:
        print(f"Unknown command: {args.scratchpad_command}", file=sys.stderr)
        return 1
