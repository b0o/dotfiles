#!/usr/bin/env python3
"""
Common utilities and constants for Niri window manager scripts.
"""

import os
from pathlib import Path

runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")

# Socket and file paths
SOCKET_PATH = Path(runtime_dir) / "niri-tools.sock"

# Scratchpad constants
SCRATCHPAD_WORKSPACE = "󰪷"
CONFIG_DIR = Path.home() / ".config" / "niri"
CONFIG_FILE = CONFIG_DIR / "scratchpads.yaml"
