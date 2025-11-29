"""Thin client for niri-tools daemon - fire and forget."""

import argparse
import json
import socket
import sys

from .common import SOCKET_PATH


def send_command(command: dict) -> int:
    """Send a command to the daemon. Returns 0 on success, 1 on failure."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(str(SOCKET_PATH))
            sock.sendall((json.dumps(command) + "\n").encode())
        return 0
    except FileNotFoundError:
        print("Daemon not running (socket not found)", file=sys.stderr)
        return 1
    except ConnectionRefusedError:
        print("Daemon not running (connection refused)", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Failed to send command: {e}", file=sys.stderr)
        return 1


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


def main(args: argparse.Namespace) -> int:
    """Handle scratchpad commands by sending to daemon."""
    if args.scratchpad_command == "toggle":
        command = {"cmd": "toggle"}
        if args.name:
            command["name"] = args.name
        return send_command(command)

    elif args.scratchpad_command == "hide":
        return send_command({"cmd": "hide"})

    else:
        print(f"Unknown command: {args.scratchpad_command}", file=sys.stderr)
        return 1
