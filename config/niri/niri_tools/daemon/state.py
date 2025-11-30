"""Daemon state management - holds all niri and scratchpad state in memory."""

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Any

from ..common import STATE_FILE
from .config import ScratchpadConfig


def get_niri_session_id() -> str | None:
    """Get the current niri session identifier from NIRI_SOCKET env var."""
    niri_socket = os.environ.get("NIRI_SOCKET")
    if niri_socket:
        # NIRI_SOCKET looks like /run/user/1000/niri.1234.0.sock
        # We use the whole path as the session ID since it includes the PID
        return niri_socket
    return None


@dataclass
class WindowInfo:
    """Information about a window."""

    id: int
    app_id: str
    title: str
    workspace_id: int | None
    is_focused: bool
    is_floating: bool

    @classmethod
    def from_niri(cls, data: dict[str, Any]) -> "WindowInfo":
        return cls(
            id=data["id"],
            app_id=data.get("app_id", ""),
            title=data.get("title", ""),
            workspace_id=data.get("workspace_id"),
            is_focused=data.get("is_focused", False),
            is_floating=data.get("is_floating", False),
        )


@dataclass
class WorkspaceInfo:
    """Information about a workspace."""

    id: int
    idx: int
    output: str
    is_active: bool

    @classmethod
    def from_niri(cls, data: dict[str, Any]) -> "WorkspaceInfo":
        return cls(
            id=data["id"],
            idx=data["idx"],
            output=data.get("output", ""),
            is_active=data.get("is_active", False),
        )


@dataclass
class OutputInfo:
    """Information about an output/monitor."""

    name: str
    width: int
    height: int

    @classmethod
    def from_niri(cls, name: str, data: dict[str, Any]) -> "OutputInfo":
        logical = data.get("logical", {})
        return cls(
            name=name,
            width=logical.get("width", 0),
            height=logical.get("height", 0),
        )


@dataclass
class ScratchpadState:
    """Runtime state for a scratchpad."""

    window_id: int | None = None
    visible: bool = False
    last_used: float = 0.0


@dataclass
class DaemonState:
    """Central state for the daemon - all niri and scratchpad state in memory."""

    # Niri state
    windows: dict[int, WindowInfo] = field(default_factory=dict)
    workspaces: dict[int, WorkspaceInfo] = field(default_factory=dict)
    outputs: dict[str, OutputInfo] = field(default_factory=dict)
    focused_output: str | None = None
    focused_window_id: int | None = None

    # Scratchpad state
    scratchpads: dict[str, ScratchpadState] = field(default_factory=dict)
    pending_spawns: set[str] = field(default_factory=set)
    window_to_scratchpad: dict[int, str] = field(default_factory=dict)

    # Config
    scratchpad_configs: dict[str, ScratchpadConfig] = field(default_factory=dict)
    config_mtime: float = 0.0

    def load_initial_state(self) -> None:
        """Load initial state from niri commands."""
        try:
            # Load windows
            result = subprocess.run(
                ["niri", "msg", "-j", "windows"],
                capture_output=True,
                text=True,
                check=True,
            )
            for w in json.loads(result.stdout):
                window = WindowInfo.from_niri(w)
                self.windows[window.id] = window
                if window.is_focused:
                    self.focused_window_id = window.id

            # Load workspaces
            result = subprocess.run(
                ["niri", "msg", "-j", "workspaces"],
                capture_output=True,
                text=True,
                check=True,
            )
            for ws in json.loads(result.stdout):
                workspace = WorkspaceInfo.from_niri(ws)
                self.workspaces[workspace.id] = workspace

            # Load outputs
            result = subprocess.run(
                ["niri", "msg", "-j", "outputs"],
                capture_output=True,
                text=True,
                check=True,
            )
            outputs_data = json.loads(result.stdout)
            for name, data in outputs_data.items():
                self.outputs[name] = OutputInfo.from_niri(name, data)

            # Load focused output
            result = subprocess.run(
                ["niri", "msg", "-j", "focused-output"],
                capture_output=True,
                text=True,
                check=True,
            )
            focused = json.loads(result.stdout)
            self.focused_output = focused.get("name")

        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"Failed to load initial niri state: {e}", file=sys.stderr)

    def get_active_workspace_for_output(self, output: str) -> WorkspaceInfo | None:
        """Get the active workspace for a given output."""
        for ws in self.workspaces.values():
            if ws.output == output and ws.is_active:
                return ws
        return None

    def get_focused_workspace(self) -> WorkspaceInfo | None:
        """Get the workspace on the focused output."""
        if not self.focused_output:
            return None
        return self.get_active_workspace_for_output(self.focused_output)

    def get_scratchpad_for_window(self, window_id: int) -> str | None:
        """Get scratchpad name for a window ID, if any."""
        return self.window_to_scratchpad.get(window_id)

    def register_scratchpad_window(self, name: str, window_id: int) -> None:
        """Register a window as belonging to a scratchpad."""
        self.window_to_scratchpad[window_id] = name
        if name not in self.scratchpads:
            self.scratchpads[name] = ScratchpadState()
        self.scratchpads[name].window_id = window_id
        self.scratchpads[name].last_used = time.time()

    def unregister_scratchpad_window(self, window_id: int) -> None:
        """Unregister a window from scratchpad tracking."""
        if name := self.window_to_scratchpad.pop(window_id, None):
            if name in self.scratchpads:
                self.scratchpads[name].window_id = None
                self.scratchpads[name].visible = False

    def mark_scratchpad_visible(self, name: str) -> None:
        """Mark a scratchpad as visible."""
        if name not in self.scratchpads:
            self.scratchpads[name] = ScratchpadState()
        self.scratchpads[name].visible = True
        self.scratchpads[name].last_used = time.time()

    def mark_scratchpad_hidden(self, name: str) -> None:
        """Mark a scratchpad as hidden."""
        if name in self.scratchpads:
            self.scratchpads[name].visible = False
            self.scratchpads[name].last_used = time.time()

    def get_most_recent_hidden_scratchpad(self) -> str | None:
        """Get the most recently used scratchpad that is currently hidden."""
        candidates = [
            (name, state)
            for name, state in self.scratchpads.items()
            if state.window_id is not None and not state.visible
        ]
        if not candidates:
            return None
        return max(candidates, key=lambda x: x[1].last_used)[0]

    def save_scratchpad_state(self) -> None:
        """Save scratchpad state to disk for persistence across restarts."""
        session_id = get_niri_session_id()
        if not session_id:
            return

        # Build state to persist
        state_data = {
            "niri_session": session_id,
            "scratchpads": {},
            "window_to_scratchpad": {},
        }

        for name, sp_state in self.scratchpads.items():
            if sp_state.window_id is not None:
                state_data["scratchpads"][name] = {
                    "window_id": sp_state.window_id,
                    "visible": sp_state.visible,
                    "last_used": sp_state.last_used,
                }

        # Convert int keys to strings for JSON
        for window_id, name in self.window_to_scratchpad.items():
            state_data["window_to_scratchpad"][str(window_id)] = name

        try:
            temp_file = STATE_FILE.with_suffix(".tmp")
            with open(temp_file, "w") as f:
                json.dump(state_data, f, separators=(",", ":"))
            temp_file.replace(STATE_FILE)
        except OSError as e:
            print(f"Failed to save scratchpad state: {e}", file=sys.stderr)

    def load_scratchpad_state(self) -> bool:
        """Load scratchpad state from disk. Returns True if state was loaded."""
        if not STATE_FILE.exists():
            return False

        session_id = get_niri_session_id()
        if not session_id:
            return False

        try:
            with open(STATE_FILE) as f:
                state_data = json.load(f)

            # Verify this state is for the current niri session
            if state_data.get("niri_session") != session_id:
                print("State file is from a different niri session, ignoring")
                STATE_FILE.unlink()
                return False

            # Load scratchpad states
            for name, sp_data in state_data.get("scratchpads", {}).items():
                self.scratchpads[name] = ScratchpadState(
                    window_id=sp_data.get("window_id"),
                    visible=sp_data.get("visible", False),
                    last_used=sp_data.get("last_used", 0.0),
                )

            # Load window mappings (convert string keys back to int)
            for window_id_str, name in state_data.get("window_to_scratchpad", {}).items():
                self.window_to_scratchpad[int(window_id_str)] = name

            print(f"Restored {len(self.scratchpads)} scratchpad states from disk")
            return True

        except (json.JSONDecodeError, OSError, KeyError, ValueError) as e:
            print(f"Failed to load scratchpad state: {e}", file=sys.stderr)
            return False

    def reconcile_with_windows(self, window_ids: set[int]) -> None:
        """Reconcile loaded scratchpad state with actual windows.

        Removes any scratchpad mappings for windows that no longer exist.
        Should be called after loading state and receiving WindowsChanged event.
        """
        # Find orphaned window IDs
        orphaned = [
            wid for wid in self.window_to_scratchpad
            if wid not in window_ids
        ]

        for window_id in orphaned:
            name = self.window_to_scratchpad.pop(window_id, None)
            if name and name in self.scratchpads:
                print(f"Scratchpad '{name}' window {window_id} no longer exists, clearing")
                self.scratchpads[name].window_id = None
                self.scratchpads[name].visible = False

        if orphaned:
            # Save updated state
            self.save_scratchpad_state()
