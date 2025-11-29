"""
Niri window manager tools - unified CLI entry point.
"""

import argparse
import sys

from . import scratchpad, stream_monitor


def create_parser() -> argparse.ArgumentParser:
    """Create the main argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        prog="niri-tools",
        description="Niri window manager tools - unified CLI for scratchpad and stream monitoring",
    )

    subparsers = parser.add_subparsers(
        dest="command",
        help="Available commands",
        required=True,
    )

    scratchpad_parser = subparsers.add_parser(
        "scratchpad",
        help="Manage scratchpad windows",
        description="Toggle show/hide scratchpad windows",
    )
    scratchpad.add_arguments(scratchpad_parser)

    monitor_parser = subparsers.add_parser(
        "monitor",
        help="Monitor niri event stream",
        description="Monitor niri event stream for urgency notifications and state tracking",
    )
    stream_monitor.add_arguments(monitor_parser)

    return parser


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "scratchpad":
            return scratchpad.main(args)
        elif args.command == "monitor":
            return stream_monitor.main(args)
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
