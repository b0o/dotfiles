#!/usr/bin/env -S uv run --script
# pyright: basic
# /// script
# requires-python = ">=3.8"
# dependencies = []
# ///
"""Claude usage monitor for Waybar.

This is the entry point script. The implementation is in the claude_usage package.
"""

from claude_usage.monitor import main

if __name__ == "__main__":
    main()
