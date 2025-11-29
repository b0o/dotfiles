#!/usr/bin/env python3
"""
Common utilities and classes for Niri window manager scripts.
"""

import json
import os
import subprocess
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
NIRI_STATE_FILE = Path(runtime_dir) / "niri-state.json"
SOCKET_PATH = Path(runtime_dir) / "niri-tools.sock"
SCRATCHPAD_WORKSPACE = "󰪷"
CONFIG_DIR = Path.home() / ".config" / "niri"
CONFIG_FILE = CONFIG_DIR / "scratchpads.yaml"


class EventHandler(ABC):
    """Base class for niri event handlers"""

    @abstractmethod
    def should_handle(self, event: dict[str, Any]) -> bool:
        """Return True if this handler should process the event"""
        pass

    @abstractmethod
    def handle(self, event: dict[str, Any]) -> None:
        """Process the event"""
        pass


def get_window_info(window_id: int) -> dict[str, Any] | None:
    """Get window information from niri"""
    try:
        result = subprocess.run(
            ["niri", "msg", "-j", "windows"], capture_output=True, text=True, check=True
        )
        windows = json.loads(result.stdout)
        for window in windows:
            if window["id"] == window_id:
                return window
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        pass
    return None
