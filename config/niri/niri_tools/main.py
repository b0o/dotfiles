"""
Niri window manager tools - unified CLI entry point.
"""

import argparse
import asyncio
import sys

from . import client
from .daemon import server


def create_parser() -> argparse.ArgumentParser:
    """Create the main argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        prog="niri-tools",
        description="Niri window manager tools - unified CLI for scratchpad and daemon",
    )

    subparsers = parser.add_subparsers(
        dest="command",
        help="Available commands",
        required=True,
    )

    # Daemon command
    daemon_parser = subparsers.add_parser(
        "daemon",
        help="Run the niri-tools daemon",
        description="Run the daemon that handles scratchpads and urgency notifications",
    )
    daemon_sub = daemon_parser.add_subparsers(dest="daemon_command")
    daemon_sub.add_parser("start", help="Start the daemon")
    daemon_sub.add_parser("stop", help="Stop the daemon")
    daemon_sub.add_parser("restart", help="Restart the daemon")
    daemon_sub.add_parser("status", help="Show daemon status")

    # Scratchpad command (routes to client)
    scratchpad_parser = subparsers.add_parser(
        "scratchpad",
        help="Manage scratchpad windows",
        description="Toggle show/hide scratchpad windows (requires daemon)",
    )
    client.add_arguments(scratchpad_parser)

    return parser


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "daemon":
            if args.daemon_command == "start":
                return client.start_daemon()
            if args.daemon_command == "stop":
                return client.stop_daemon()
            if args.daemon_command == "restart":
                return client.restart_daemon()
            if args.daemon_command == "status":
                return client.daemon_status()
            return asyncio.run(server.run_daemon())
        elif args.command == "scratchpad":
            return client.main(args)
        else:
            print(f"Unknown command: {args.command}", file=sys.stderr)
            parser.print_help()
            return 1
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
