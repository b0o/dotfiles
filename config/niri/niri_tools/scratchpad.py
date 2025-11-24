"""
Niri scratchpad module - manage scratchpad windows.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import yaml

from .common import EventHandler, runtime_dir

STATE_DIR = Path(runtime_dir) / "niri-scratchpads"
SCRATCHPAD_WORKSPACE = "󰪷"
CONFIG_DIR = Path.home() / ".config" / "niri"
CONFIG_FILE = CONFIG_DIR / "scratchpads.yaml"
UNIFIED_STATE_FILE = Path(runtime_dir) / "scratchpad-state.json"


def convert_coordinates_to_pixels(
    coords: tuple[str, str],
    outputs: dict[str, Any] | None = None,
    monitor_name: str | None = None,
) -> tuple[int, int]:
    """Convert coordinate strings (which may include percentages) to absolute pixel values"""
    x_str, y_str = coords

    # Get monitor dimensions from cached output data if available
    monitor_width, monitor_height = _get_monitor_dimensions(outputs, monitor_name)

    # Convert X coordinate
    if x_str.endswith("%"):
        x_percent = float(x_str[:-1])
        x = int(monitor_width * x_percent / 100)
    else:
        x = int(x_str)

    # Convert Y coordinate
    if y_str.endswith("%"):
        y_percent = float(y_str[:-1])
        y = int(monitor_height * y_percent / 100)
    else:
        y = int(y_str)

    return x, y


def _get_monitor_dimensions(
    outputs: dict[str, Any] | None = None, monitor_name: str | None = None
) -> tuple[int, int]:
    """Get monitor dimensions from cached outputs, with fallback to default 4K"""
    if outputs and monitor_name and monitor_name in outputs:
        output_info = outputs[monitor_name]
        logical = output_info.get("logical", {})
        width = logical.get("width")
        height = logical.get("height")
        if width and height:
            return width, height

    # Fallback: try to get focused monitor dimensions
    if outputs:
        for output_name, output_info in outputs.items():
            logical = output_info.get("logical", {})
            width = logical.get("width")
            if not width:
                raise ValueError(f"Invalid output {output_name} width: {width}")
            height = logical.get("height")
            if not height:
                raise ValueError(f"Invalid output {output_name} height: {height}")
            return width, height

    raise ValueError("No monitor dimensions found")


# Shared regex cache for compiled patterns
_REGEX_CACHE: dict[str, re.Pattern] = {}


class ScratchpadState:
    """Manage scratchpad state persistence"""

    def __init__(self, name: str):
        self.name = name
        self.state_file = STATE_DIR / f"{name}.json"
        self._cached_state: dict[str, Any] | None = None
        self._cache_mtime: float | None = None
        STATE_DIR.mkdir(parents=True, exist_ok=True)

    def save_window_id(self, window_id: int, app_id: str) -> None:
        """Save scratchpad window information"""
        state = {"window_id": window_id, "app_id": app_id, "created_at": time.time()}
        with open(self.state_file, "w") as f:
            json.dump(state, f)
        # Invalidate cache after writing
        self._cached_state = None
        self._cache_mtime = None

    def get_window_id(self) -> int | None:
        """Get stored window ID if it exists and is valid"""
        if not self.state_file.exists():
            return None

        try:
            with open(self.state_file) as f:
                state = json.load(f)

            window_id = state.get("window_id")
            if window_id:
                return window_id
            # Clean up invalid state
            self.clear_state()
            return None
        except (json.JSONDecodeError, FileNotFoundError):
            return None

    def get_window_id_cached(self) -> int | None:
        """Get stored window ID if it exists and is valid using cached window data"""
        if not self.state_file.exists():
            return None

        try:
            state = self._get_cached_state()
            if not state:
                return None

            window_id = state.get("window_id")
            if window_id:
                return window_id
            # Clean up invalid state
            self.clear_state()
            return None
        except (json.JSONDecodeError, FileNotFoundError):
            return None

    def _get_cached_state(self) -> dict[str, Any] | None:
        """Get state with file system caching"""
        if not self.state_file.exists():
            return None

        try:
            current_mtime = self.state_file.stat().st_mtime

            # Use cached state if file hasn't changed
            if (
                self._cached_state is not None
                and self._cache_mtime is not None
                and current_mtime == self._cache_mtime
            ):
                return self._cached_state

            # Read and cache state
            with open(self.state_file) as f:
                self._cached_state = json.load(f)
            self._cache_mtime = current_mtime
            return self._cached_state

        except (json.JSONDecodeError, FileNotFoundError, OSError):
            return None

    def clear_state(self) -> None:
        """Remove state file"""
        if self.state_file.exists():
            self.state_file.unlink()
        # Clear cache
        self._cached_state = None
        self._cache_mtime = None


class UnifiedScratchpadState:
    """Manage unified state for all scratchpads"""

    def __init__(self):
        self.state_file = UNIFIED_STATE_FILE
        self._cached_state: dict[str, Any] | None = None
        self._cache_mtime: float | None = None

    def _load_state(self) -> dict[str, Any]:
        """Load or create unified state"""
        if not self.state_file.exists():
            return {
                "windows": {},  # window_id -> scratchpad_name mapping
                "last_used": {},  # scratchpad_name -> timestamp
                "visible": [],  # list of currently visible scratchpad names
            }

        try:
            with open(self.state_file) as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            return {
                "windows": {},
                "last_used": {},
                "visible": [],
            }

    def _save_state(self, state: dict[str, Any]) -> None:
        """Save unified state to disk"""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.state_file, "w") as f:
            json.dump(state, f, indent=2)
        # Invalidate cache
        self._cached_state = None
        self._cache_mtime = None

    def register_window(self, window_id: int, scratchpad_name: str) -> None:
        """Register a window as belonging to a scratchpad"""
        state = self._load_state()
        state["windows"][str(window_id)] = scratchpad_name
        state["last_used"][scratchpad_name] = time.time()
        self._save_state(state)

    def unregister_window(self, window_id: int) -> None:
        """Remove a window from the registry"""
        state = self._load_state()
        window_id_str = str(window_id)
        if window_id_str in state["windows"]:
            scratchpad_name = state["windows"][window_id_str]
            del state["windows"][window_id_str]
            # Remove from visible list if present
            if scratchpad_name in state["visible"]:
                state["visible"].remove(scratchpad_name)
            self._save_state(state)

    def mark_visible(self, scratchpad_name: str) -> None:
        """Mark a scratchpad as currently visible"""
        state = self._load_state()
        if scratchpad_name not in state["visible"]:
            state["visible"].append(scratchpad_name)
        state["last_used"][scratchpad_name] = time.time()
        self._save_state(state)

    def mark_hidden(self, scratchpad_name: str) -> None:
        """Mark a scratchpad as hidden"""
        state = self._load_state()
        if scratchpad_name in state["visible"]:
            state["visible"].remove(scratchpad_name)
        self._save_state(state)

    def get_scratchpad_for_window(self, window_id: int) -> str | None:
        """Get the scratchpad name for a given window ID"""
        state = self._load_state()
        return state["windows"].get(str(window_id))

    def get_most_recent_scratchpad(self) -> str | None:
        """Get the name of the most recently used scratchpad that isn't currently visible"""
        state = self._load_state()
        if not state["last_used"]:
            return None

        # Sort by timestamp, most recent first
        sorted_scratchpads = sorted(
            state["last_used"].items(), key=lambda x: x[1], reverse=True
        )

        # Find first one that's not currently visible
        for name, _ in sorted_scratchpads:
            if name not in state["visible"]:
                return name

        return None

    def clean_stale_windows(self, existing_window_ids: list[int]) -> None:
        """Remove entries for windows that no longer exist"""
        state = self._load_state()
        existing_ids_str = {str(wid) for wid in existing_window_ids}

        # Find windows to remove
        to_remove = []
        for window_id_str in state["windows"]:
            if window_id_str not in existing_ids_str:
                to_remove.append(window_id_str)

        # Remove stale entries
        if to_remove:
            for window_id_str in to_remove:
                scratchpad_name = state["windows"][window_id_str]
                del state["windows"][window_id_str]
                # Also remove from visible list if present
                if scratchpad_name in state["visible"]:
                    state["visible"].remove(scratchpad_name)
            self._save_state(state)


class NiriState:
    """Load Niri state from cached file written by niri-tools monitor"""

    def __init__(self):
        self.windows: list[dict[str, Any]] = []
        self.workspaces: list[dict[str, Any]] = []
        self.focused_output: dict[str, Any] = {}
        self.outputs: dict[str, Any] = {}
        self._loaded = False

    def load(self) -> None:
        """Load niri state from cached file"""
        if self._loaded:
            return

        niri_state_file = Path(runtime_dir) / "niri-state.json"

        try:
            if not niri_state_file.exists():
                print(
                    "Warning: niri-state.json not found. Is niri-tools monitor running?",
                    file=sys.stderr,
                )
                return

            with open(niri_state_file) as f:
                state = json.load(f)

            self.windows = state.get("windows", [])
            self.workspaces = state.get("workspaces", [])
            self.focused_output = state.get("focused_output", {})
            self.outputs = state.get("outputs", {})
            self._loaded = True

        except (json.JSONDecodeError, OSError) as e:
            print(f"Failed to load niri state cache: {e}", file=sys.stderr)


class ScratchpadManager:
    """Manage scratchpad creation, showing, and hiding"""

    def __init__(
        self,
        name: str,
        command: list[str] | None,
        app_id: str | None = None,
        title: str | None = None,
        width: str | None = None,
        height: str | None = None,
        position: str | None = None,
        position_specs: list[str] | None = None,
    ):
        self.name = name
        self.command = command
        self.app_id = app_id
        self.title = title

        # Check if app_id is a regex pattern (starts with /)
        self.app_id_regex: re.Pattern | None = None
        if app_id and app_id.startswith("/"):
            pattern = app_id[1:]  # Remove leading /
            if pattern not in _REGEX_CACHE:
                _REGEX_CACHE[pattern] = re.compile(pattern)
            self.app_id_regex = _REGEX_CACHE[pattern]

        # Check if title is a regex pattern (starts with /)
        self.title_regex: re.Pattern | None = None
        if title and title.startswith("/"):
            pattern = title[1:]  # Remove leading /
            if pattern not in _REGEX_CACHE:
                _REGEX_CACHE[pattern] = re.compile(pattern)
            self.title_regex = _REGEX_CACHE[pattern]

        self.width = width
        self.height = height

        # Parse position specifications into a dictionary
        self.position_map: dict[str | None, tuple[str, str] | None] = {}
        if position_specs:
            for spec in position_specs:
                output_name, coords = parse_position_spec(spec)
                self.position_map[output_name] = coords
        elif position:
            # Legacy single position support
            self.position_map[None] = parse_position(position)

        self.state = ScratchpadState(name)
        self.unified_state = UnifiedScratchpadState()

        # Validate that exactly one matching method is provided (only if command is provided)
        if command is not None and not ((app_id is None) ^ (title is None)):
            raise ValueError("Must provide exactly one of app_id or title")

    def toggle_scratchpad(self) -> bool:
        """Main toggle function - show/hide/create scratchpad"""
        # Load all niri state from cached file (extremely fast)
        niri_state = NiriState()
        niri_state.load()

        window_id = self.state.get_window_id_cached()

        if window_id is None:
            # Scratchpad doesn't exist
            if self.command is None:
                # No command provided, just exit quietly
                return True
            # Command provided, create it
            print(f"Creating new scratchpad '{self.name}'")
            return self._create_scratchpad()

        # Scratchpad exists, check its current state
        window_info = self._get_window_info(window_id, niri_state.windows)
        if not window_info:
            # Window no longer exists in state, clean up
            self.state.clear_state()
            if self.command is None:
                # No command provided, just exit quietly
                return True
            # Command provided, create new
            return self._create_scratchpad()

        # Get current workspace info using cached data
        current_workspace_info = self._get_current_workspace_info(niri_state)
        if not current_workspace_info:
            print("Failed to get current workspace info", file=sys.stderr)
            return False

        current_workspace_id, _current_workspace_idx, _current_monitor = (
            current_workspace_info
        )
        window_workspace_id = window_info.get("workspace_id")
        is_focused = window_info.get("is_focused", False)

        if is_focused:
            # Window is focused, hide it
            print(f"Hiding scratchpad '{self.name}'")
            return self._hide_scratchpad(window_id)
        elif window_workspace_id != current_workspace_id:
            # Window is on different workspace (possibly different monitor), show it
            print(f"Showing scratchpad '{self.name}'")
            return self._show_scratchpad(window_id)
        else:
            # Window is on current workspace but not focused, focus it
            print(f"Focusing scratchpad '{self.name}'")
            return self._focus_window(window_id)

    def _create_scratchpad(self) -> bool:
        """Create new scratchpad"""
        handler = ScratchpadHandler(
            self.command,
            self.state,
            self.width,
            self.height,
            position_specs=None,  # Not needed since we pass position_map directly
            position_map=self.position_map,
            app_id=self.app_id,
            title=self.title,
            scratchpad_name=self.name,
        )

        if not handler.launch_application():
            return False

        print("Monitoring for window creation...")
        monitor_events([handler], timeout=10.0)

        if handler.waiting_for_window:
            print("Window was not detected within timeout period")
            return False

        print("Scratchpad created successfully!")
        return True

    def _hide_scratchpad(self, window_id: int) -> bool:
        """Move scratchpad to hidden workspace"""
        try:
            # Use scratchpad workspace name (niri creates it automatically)
            scratchpad_workspace = SCRATCHPAD_WORKSPACE

            print(f"Moving window {window_id} to workspace '{scratchpad_workspace}'")

            # Move to scratchpad workspace with no focus follow
            subprocess.run(
                [
                    "niri",
                    "msg",
                    "action",
                    "move-window-to-workspace",
                    "--window-id",
                    str(window_id),
                    "--focus",
                    "false",
                    scratchpad_workspace,
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            # Update unified state
            self.unified_state.mark_hidden(self.name)

            print("Successfully moved window to scratchpad workspace")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to hide scratchpad: {e}", file=sys.stderr)
            return False

    def _show_scratchpad(self, window_id: int) -> bool:
        """Move scratchpad to current workspace and configure it"""
        try:
            # Get current workspace info from cached state
            niri_state = NiriState()
            niri_state.load()
            workspace_info = self._get_current_workspace_info(niri_state)
            if not workspace_info:
                print("Failed to get current workspace info", file=sys.stderr)
                return False

            _workspace_id, workspace_idx, monitor_name = workspace_info

            # Step 1: Move window to the target monitor
            subprocess.run(
                [
                    "niri",
                    "msg",
                    "action",
                    "move-window-to-monitor",
                    "--id",
                    str(window_id),
                    monitor_name,
                ],
                check=True,
            )

            # Step 2: Ensure window is on the active workspace of that monitor
            # Use workspace index for this command as it's more reliable
            subprocess.run(
                [
                    "niri",
                    "msg",
                    "action",
                    "move-window-to-workspace",
                    "--window-id",
                    str(window_id),
                    "--focus",
                    "false",
                    str(workspace_idx),
                ],
                check=True,
            )

            # Configure as floating and centered
            self._configure_floating_window(window_id)

            # Update unified state
            self.unified_state.mark_visible(self.name)
            self.unified_state.register_window(window_id, self.name)

            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to show scratchpad: {e}", file=sys.stderr)
            return False

    def _focus_window(self, window_id: int) -> bool:
        """Focus the scratchpad window"""
        try:
            subprocess.run(
                ["niri", "msg", "action", "focus-window", "--id", str(window_id)],
                check=True,
            )
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to focus window: {e}", file=sys.stderr)
            return False

    def _configure_floating_window(self, window_id: int) -> None:
        """Configure window as floating, optionally resized and positioned"""
        try:
            # Focus the window
            subprocess.run(
                ["niri", "msg", "action", "focus-window", "--id", str(window_id)],
                check=True,
            )

            # Move window to floating layout (this is idempotent - won't break if already floating)
            subprocess.run(
                ["niri", "msg", "action", "move-window-to-floating"], check=True
            )

            # Only resize if width/height are specified
            if self.width is not None:
                subprocess.run(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-width",
                        "--id",
                        str(window_id),
                        self.width,
                    ],
                    check=True,
                )
            if self.height is not None:
                subprocess.run(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-height",
                        "--id",
                        str(window_id),
                        self.height,
                    ],
                    check=True,
                )

            # Only position if positions are specified
            if self.position_map:
                self._position_window(window_id)

        except subprocess.CalledProcessError as e:
            print(f"Failed to configure floating window: {e}", file=sys.stderr)

    def _position_window(self, window_id: int) -> None:
        """Position window based on user preference"""
        try:
            # Get monitor info
            niri_state = NiriState()
            niri_state.load()
            monitor_name = niri_state.focused_output.get("name")

            # Look for output-specific position first
            position_coords = self.position_map.get(monitor_name)

            # If no output-specific position, use fallback (None key)
            if position_coords is None and monitor_name not in self.position_map:
                position_coords = self.position_map.get(None)

            # If we have a position to apply (checking against explicit None)
            if monitor_name in self.position_map or None in self.position_map:
                if position_coords is None:
                    # Center position
                    subprocess.run(
                        ["niri", "msg", "action", "center-window"], check=True
                    )
                else:
                    # Convert coordinates to absolute pixels if needed
                    x, y = convert_coordinates_to_pixels(
                        position_coords, niri_state.outputs, monitor_name
                    )
                    subprocess.run(
                        [
                            "niri",
                            "msg",
                            "action",
                            "move-floating-window",
                            "--id",
                            str(window_id),
                            "--x",
                            str(x),
                            "--y",
                            str(y),
                        ],
                        check=True,
                    )
        except subprocess.CalledProcessError as e:
            print(f"Failed to position window: {e}", file=sys.stderr)

    def _get_window_info(
        self, window_id: int, windows: list[dict[str, Any]]
    ) -> dict[str, Any] | None:
        """Get window information using cached window data"""
        # Use next() with default for early termination
        return next((w for w in windows if w["id"] == window_id), None)

    def _get_current_workspace_info(
        self, niri_state: NiriState
    ) -> tuple[int, int, str] | None:
        """Get current active workspace info using cached data: (id, index, monitor_name) on the focused monitor"""
        try:
            focused_monitor = niri_state.focused_output.get("name")
            if not focused_monitor:
                return None

            # Find the active workspace on the focused monitor with early termination
            workspace = next(
                (
                    w
                    for w in niri_state.workspaces
                    if w.get("output") == focused_monitor and w.get("is_active", False)
                ),
                None,
            )

            if workspace:
                return (workspace["id"], workspace["idx"], focused_monitor)

        except (KeyError, TypeError):
            pass
        return None


class ScratchpadHandler(EventHandler):
    """Handle scratchpad application launching and window management"""

    def __init__(
        self,
        command: list[str] | None,
        state: ScratchpadState,
        width: str | None = None,
        height: str | None = None,
        position: str | None = None,
        position_specs: list[str] | None = None,
        position_map: dict[str | None, tuple[str, str] | None] | None = None,
        app_id: str | None = None,
        title: str | None = None,
        scratchpad_name: str | None = None,
    ):
        self.app_id = app_id
        self.title = title
        self.scratchpad_name = scratchpad_name

        # Check if app_id is a regex pattern (starts with /)
        self.app_id_regex: re.Pattern | None = None
        if app_id and app_id.startswith("/"):
            pattern = app_id[1:]  # Remove leading /
            if pattern not in _REGEX_CACHE:
                _REGEX_CACHE[pattern] = re.compile(pattern)
            self.app_id_regex = _REGEX_CACHE[pattern]

        # Check if title is a regex pattern (starts with /)
        self.title_regex: re.Pattern | None = None
        if title and title.startswith("/"):
            pattern = title[1:]  # Remove leading /
            if pattern not in _REGEX_CACHE:
                _REGEX_CACHE[pattern] = re.compile(pattern)
            self.title_regex = _REGEX_CACHE[pattern]

        self.command = command
        self.state = state
        self.width = width
        self.height = height
        self.position_map = position_map or {}
        self.waiting_for_window = False
        self.launch_time = 0.0
        self.unified_state = UnifiedScratchpadState()

        # Validate that exactly one matching method is provided
        if not ((app_id is None) ^ (title is None)):
            raise ValueError("Must provide exactly one of app_id or title")

    def should_handle(self, event: dict[str, Any]) -> bool:
        return "WindowOpenedOrChanged" in event and self.waiting_for_window

    def handle(self, event: dict[str, Any]) -> None:
        window_data = event["WindowOpenedOrChanged"]["window"]

        # Check if this is the window we're waiting for
        if self.waiting_for_window and self._matches_window(window_data):
            window_id = window_data["id"]

            if self.app_id_regex:
                match_info = f"app_id pattern '{self.app_id}'"
            elif self.app_id:
                match_info = f"app_id '{self.app_id}'"
            elif self.title_regex:
                match_info = f"title pattern '{self.title}'"
            else:
                match_info = f"title '{self.title}'"

            print(f"Detected window matching {match_info} (ID: {window_id})")

            # Save the window state (use app_id if available, otherwise use title)
            save_id = self.app_id or f"title:{self.title}"
            self.state.save_window_id(window_id, save_id)

            # Register with unified state if we have a scratchpad name
            if self.scratchpad_name:
                self.unified_state.register_window(window_id, self.scratchpad_name)
                self.unified_state.mark_visible(self.scratchpad_name)

            # Configure the window
            self._configure_new_window(window_id)

            # Reset waiting state
            self.waiting_for_window = False

    def _matches_window(self, window_data: dict[str, Any]) -> bool:
        """Check if window matches our criteria (app_id or title)"""
        if self.app_id_regex:
            # Match by app_id regex
            window_app_id = window_data.get("app_id", "")
            return bool(self.app_id_regex.search(window_app_id))
        elif self.app_id:
            # Match by exact app_id
            window_app_id = window_data.get("app_id", "")
            return window_app_id == self.app_id
        elif self.title_regex:
            # Match by title regex
            window_title = window_data.get("title", "")
            return bool(self.title_regex.search(window_title))
        elif self.title:
            # Match by exact title
            window_title = window_data.get("title", "")
            return window_title == self.title
        return False

    def launch_application(self) -> bool:
        """Launch the application and start monitoring for its window"""
        if not self.command:
            return True
        try:
            print(f"Launching {' '.join(self.command)}...")
            subprocess.Popen(self.command)
            self.waiting_for_window = True
            self.launch_time = time.time()
            return True
        except Exception as e:
            print(f"Failed to launch application: {e}", file=sys.stderr)
            return False

    def _configure_new_window(self, window_id: int) -> None:
        """Configure newly created scratchpad window"""
        try:
            # Focus the window
            subprocess.run(
                ["niri", "msg", "action", "focus-window", "--id", str(window_id)],
                check=True,
            )

            # Move to floating layout
            subprocess.run(
                ["niri", "msg", "action", "move-window-to-floating"], check=True
            )

            # Only resize if width/height are specified
            if self.width is not None:
                subprocess.run(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-width",
                        "--id",
                        str(window_id),
                        self.width,
                    ],
                    check=True,
                )
            if self.height is not None:
                subprocess.run(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-height",
                        "--id",
                        str(window_id),
                        self.height,
                    ],
                    check=True,
                )

            # Only position if positions are specified
            if self.position_map:
                self._position_window(window_id)

            print(f"Window {window_id} configured as scratchpad")
        except subprocess.CalledProcessError as e:
            print(f"Failed to configure window: {e}", file=sys.stderr)

    def _position_window(self, window_id: int) -> None:
        """Position window based on user preference"""
        try:
            # Get monitor info
            niri_state = NiriState()
            niri_state.load()
            monitor_name = niri_state.focused_output.get("name")

            # Look for output-specific position first
            position_coords = self.position_map.get(monitor_name)

            # If no output-specific position, use fallback (None key)
            if position_coords is None and monitor_name not in self.position_map:
                position_coords = self.position_map.get(None)

            # If we have a position to apply (checking against explicit None)
            if monitor_name in self.position_map or None in self.position_map:
                if position_coords is None:
                    # Center position
                    subprocess.run(
                        ["niri", "msg", "action", "center-window"], check=True
                    )
                else:
                    # Convert coordinates to absolute pixels if needed
                    x, y = convert_coordinates_to_pixels(
                        position_coords, niri_state.outputs, monitor_name
                    )
                    subprocess.run(
                        [
                            "niri",
                            "msg",
                            "action",
                            "move-floating-window",
                            "--id",
                            str(window_id),
                            "--x",
                            str(x),
                            "--y",
                            str(y),
                        ],
                        check=True,
                    )
        except subprocess.CalledProcessError as e:
            print(f"Failed to position window: {e}", file=sys.stderr)


def monitor_events(handlers: list[EventHandler], timeout: float = 10.0) -> None:
    """Monitor niri event stream for a limited time"""
    start_time = time.time()

    try:
        process = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for line in process.stdout or []:
            # Check timeout
            if time.time() - start_time > timeout:
                print("Timeout reached, stopping monitoring")
                break

            line = line.strip()
            if not line:
                continue

            try:
                event = json.loads(line)

                # Run all handlers that match the event
                for handler in handlers:
                    if handler.should_handle(event):
                        handler.handle(event)

            except json.JSONDecodeError:
                print(f"Failed to parse event: {line}", file=sys.stderr)
                continue

        process.terminate()

    except KeyboardInterrupt:
        print("\nMonitoring stopped")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)


def parse_size(size_str: str) -> tuple[str, str]:
    """Parse size string like '80%x60%' into (width, height)"""
    try:
        parts = size_str.split("x")
        if len(parts) != 2:
            raise ValueError(f"Size must be in format 'widthxheight', got: {size_str}")
        return parts[0].strip(), parts[1].strip()
    except Exception:
        print(
            f"Invalid size format: {size_str}. Using default 80%x60%", file=sys.stderr
        )
        return "80%", "60%"


def parse_position(position_str: str) -> tuple[str, str] | None:
    """Parse position string like '100,50' or '10%,20%' into (x, y). Returns None for 'center'."""
    if position_str.lower() == "center":
        return None

    try:
        parts = position_str.split(",")
        if len(parts) != 2:
            raise ValueError(
                f"Position must be 'center' or 'x,y' format, got: {position_str}"
            )
        return parts[0].strip(), parts[1].strip()
    except Exception:
        print(f"Invalid position format: {position_str}. Using center", file=sys.stderr)
        return None


def parse_position_spec(
    position_spec: str,
) -> tuple[str | None, tuple[str, str] | None]:
    """Parse position specification like 'DP-1=40%,60%' or '30%,30%'.

    Returns (output_name, position_coords) where:
    - output_name is None for fallback positions
    - position_coords is None for 'center', otherwise (x, y)
    """
    # Check if this is an output-specific position
    if "=" in position_spec:
        parts = position_spec.split("=", 1)
        if len(parts) == 2:
            output_name = parts[0].strip()
            position_str = parts[1].strip()
            return output_name, parse_position(position_str)

    # No output specified, this is a fallback position
    return None, parse_position(position_spec)


def load_config() -> dict[str, Any]:
    """Load scratchpad configuration from YAML file with support for includes"""
    return _load_config_recursive(CONFIG_FILE, set())


def _load_config_recursive(config_path: Path, visited: set[Path]) -> dict[str, Any]:
    """Recursively load config files, following include directives

    Included files are processed first, then merged with the current file's config.
    Scratchpads defined in the current file override those from included files.
    """
    # Resolve to absolute path to handle circular includes
    try:
        config_path = config_path.resolve()
    except (OSError, RuntimeError):
        print(f"Warning: Could not resolve path {config_path}", file=sys.stderr)
        return {}

    # Check for circular includes
    if config_path in visited:
        print(
            f"Warning: Circular include detected for {config_path}, skipping",
            file=sys.stderr,
        )
        return {}

    if not config_path.exists():
        if config_path == CONFIG_FILE.resolve():
            # Main config file doesn't exist, return empty config
            return {}
        else:
            # Included file doesn't exist, warn and skip
            print(
                f"Warning: Included config file not found: {config_path}",
                file=sys.stderr,
            )
            return {}

    visited.add(config_path)

    try:
        with open(config_path) as f:
            config = yaml.safe_load(f)

        if not config:
            return {}

        # Initialize result with empty scratchpads dict
        result: dict[str, Any] = {"scratchpads": {}}

        # Process includes if present
        includes = config.get("include", [])
        if includes:
            # Ensure includes is a list
            if not isinstance(includes, list):
                includes = [includes]

            # Load each included file and merge in order
            for include_path_str in includes:
                # Resolve relative paths relative to the current config file's directory
                include_path = config_path.parent / include_path_str
                included_config = _load_config_recursive(include_path, visited.copy())

                # Merge scratchpads from included file
                if "scratchpads" in included_config:
                    result["scratchpads"].update(included_config["scratchpads"])

        # Now merge scratchpads from current file (these override included ones)
        if "scratchpads" in config:
            result["scratchpads"].update(config["scratchpads"])

        return result

    except (yaml.YAMLError, OSError) as e:
        print(f"Failed to load config from {config_path}: {e}", file=sys.stderr)
        return {}


def smart_toggle() -> int:
    """Smart toggle: hide focused scratchpad or show most recent one"""

    # Load niri state
    niri_state = NiriState()
    niri_state.load()

    # Load unified scratchpad state
    unified_state = UnifiedScratchpadState()

    # Clean up stale windows first
    existing_window_ids = [w["id"] for w in niri_state.windows]
    unified_state.clean_stale_windows(existing_window_ids)

    # Check if focused window is a scratchpad
    focused_window = None
    for window in niri_state.windows:
        if window.get("is_focused", False):
            focused_window = window
            break

    if focused_window:
        window_id = focused_window["id"]
        scratchpad_name = unified_state.get_scratchpad_for_window(window_id)

        if scratchpad_name:
            # Focused window is a scratchpad, hide it
            print(f"Hiding focused scratchpad '{scratchpad_name}'")

            # Move to scratchpad workspace
            try:
                subprocess.run(
                    [
                        "niri",
                        "msg",
                        "action",
                        "move-window-to-workspace",
                        "--window-id",
                        str(window_id),
                        "--focus",
                        "false",
                        SCRATCHPAD_WORKSPACE,
                    ],
                    check=True,
                )

                # Update unified state
                unified_state.mark_hidden(scratchpad_name)

                return 0
            except subprocess.CalledProcessError as e:
                print(f"Failed to hide scratchpad: {e}", file=sys.stderr)
                return 1

    # No scratchpad is focused, show the most recent one
    most_recent = unified_state.get_most_recent_scratchpad()

    if most_recent:
        print(f"Showing most recent scratchpad '{most_recent}'")

        # Load config to get scratchpad settings
        config = load_config()
        scratchpads = config.get("scratchpads", {})

        if most_recent in scratchpads:
            # Use the regular toggle mechanism with the scratchpad name
            scratchpad_config = scratchpads[most_recent]

            # Parse size from config
            size_str = scratchpad_config.get("size")
            if size_str:
                width, height = parse_size(size_str)
            else:
                width, height = None, None

            # Parse position from config
            position_config = scratchpad_config.get("position", {})
            position_specs = []
            for output, pos in position_config.items():
                if pos.lower() == "center":
                    position_specs.append(f"{output}=center")
                else:
                    position_specs.append(f"{output}={pos}")

            # Get command from config
            command = scratchpad_config.get("command")

            # Create manager with config values
            manager = ScratchpadManager(
                name=most_recent,
                command=command,
                app_id=scratchpad_config.get("app_id"),
                title=scratchpad_config.get("title"),
                width=width,
                height=height,
                position_specs=position_specs if position_specs else None,
            )

            # Toggle the scratchpad (which will show it)
            return 0 if manager.toggle_scratchpad() else 1
        else:
            print(f"Scratchpad '{most_recent}' not found in config", file=sys.stderr)
            return 1
    else:
        print("No scratchpad to toggle")
        return 0


def cmd_toggle(args: argparse.Namespace) -> int:
    """Toggle a scratchpad"""

    # If no name provided, handle smart toggle
    if args.name is None:
        return smart_toggle()

    # Load configuration
    config = load_config()
    scratchpads = config.get("scratchpads", {})

    # Check if scratchpad exists in config
    if args.name not in scratchpads:
        # Fall back to command-line arguments if not in config
        # Parse size into width and height if provided
        if args.size:
            width, height = parse_size(args.size)
        else:
            width, height = None, None

        # When no command is provided, we also don't require app_id or title
        if args.exec is None and args.app_id is None and args.title is None:
            # Just toggle by name
            manager = ScratchpadManager(
                name=args.name,
                command=None,
                app_id=None,
                title=None,
                width=width,
                height=height,
                position_specs=args.position,
            )
        else:
            # Normal behavior with command
            manager = ScratchpadManager(
                name=args.name,
                command=args.exec,
                app_id=args.app_id,
                title=args.title,
                width=width,
                height=height,
                position_specs=args.position,
            )
    else:
        # Use config values
        scratchpad_config = scratchpads[args.name]

        # Parse size from config
        size_str = scratchpad_config.get("size")
        if size_str:
            width, height = parse_size(size_str)
        else:
            width, height = None, None

        # Parse position from config
        position_config = scratchpad_config.get("position", {})
        position_specs = []
        for output, pos in position_config.items():
            if pos.lower() == "center":
                position_specs.append(f"{output}=center")
            else:
                position_specs.append(f"{output}={pos}")

        # Get command from config
        command = scratchpad_config.get("command")

        # Create manager with config values
        manager = ScratchpadManager(
            name=args.name,
            command=command,
            app_id=scratchpad_config.get("app_id"),
            title=scratchpad_config.get("title"),
            width=width,
            height=height,
            position_specs=position_specs if position_specs else None,
        )

    # Toggle the scratchpad
    success = manager.toggle_scratchpad()

    return 0 if success else 1


def cmd_hide(_args: argparse.Namespace) -> int:
    """Hide the focused scratchpad"""
    # Determine if the focused window is a scratchpad
    niri_state = NiriState()
    niri_state.load()

    scratchpad_window = None
    for window in niri_state.windows:
        if window["is_focused"]:
            scratchpad_window = window
            break

    if not scratchpad_window:
        print("No focused window found", file=sys.stderr)
        return 1

    # TODO: check scratchpad state to ensure it's actually a scratchpad,
    # rather than just a floating window
    # neet to unify scratchpad state into a single file to do this efficiently
    if not scratchpad_window.get("is_floating", False):
        print("Focused window is not a scratchpad", file=sys.stderr)
        return 1

    # Hide the scratchpad
    subprocess.run(
        [
            "niri",
            "msg",
            "action",
            "move-window-to-workspace",
            "--window-id",
            str(scratchpad_window["id"]),
            "--focus",
            "false",
            SCRATCHPAD_WORKSPACE,
        ],
        check=True,
    )

    return 0


def cmd_list(_args: argparse.Namespace) -> int:
    """List all configured scratchpads"""
    config = load_config()
    scratchpads = config.get("scratchpads", {})

    if not scratchpads:
        print("No scratchpads configured in", CONFIG_FILE)
        return 0

    print(f"Configured scratchpads from {CONFIG_FILE}:")
    print()

    for name, scratchpad_config in scratchpads.items():
        print(f"  {name}:")
        if "app_id" in scratchpad_config:
            print(f"    App ID: {scratchpad_config['app_id']}")
        if "title" in scratchpad_config:
            print(f"    Title: {scratchpad_config['title']}")
        if "size" in scratchpad_config:
            print(f"    Size: {scratchpad_config['size']}")
        if "position" in scratchpad_config:
            positions = scratchpad_config["position"]
            if positions:
                print("    Positions:")
                for output, pos in positions.items():
                    print(f"      {output}: {pos}")
        if "command" in scratchpad_config:
            cmd = scratchpad_config["command"]
            if isinstance(cmd, list):
                cmd_str = " ".join(cmd)
            else:
                cmd_str = cmd
            print(f"    Command: {cmd_str}")
        print()

    return 0


def add_arguments(parser: argparse.ArgumentParser) -> None:
    sub = parser.add_subparsers(dest="scratchpad_command")

    toggle = sub.add_parser("toggle", help="Toggle a scratchpad")

    """Add scratchpad-specific arguments to the parser."""
    toggle.add_argument(
        "name",
        type=str,
        nargs="?",  # Make name optional
        default=None,
        help="Name of the scratchpad. If not provided, will hide focused scratchpad or show most recent one",
    )

    # Optional arguments for overriding config or defining scratchpads not in config
    match_group = toggle.add_mutually_exclusive_group(required=False)
    match_group.add_argument(
        "--app-id",
        "-a",
        type=str,
        help="Application ID to match windows (e.g., 'com.mitchellh.ghostty', 'firefox'). Prefix with '/' for regex matching (e.g., '/org\\.gnome\\..*')",
    )
    match_group.add_argument(
        "--title",
        "-t",
        type=str,
        help="Window title to match (e.g., 'Terminal', 'Firefox'). Prefix with '/' for regex matching (e.g., '/.*Firefox.*')",
    )

    toggle.add_argument(
        "--exec",
        "-x",
        nargs="+",
        required=False,
        help="Command to launch the application (e.g., 'ghostty' or 'firefox --new-window')",
    )
    toggle.add_argument(
        "--size",
        "-s",
        type=str,
        default=None,
        help="Window size as 'widthxheight' (e.g., '80%%x60%%', '1200x800', '50%%x40%%'). If not specified, window manager decides size.",
    )
    toggle.add_argument(
        "--position",
        "-p",
        type=str,
        action="append",
        default=None,
        help="Window position: 'center', 'x,y' coordinates (e.g., '100,50', '10%%,10%%'), or output-specific positions (e.g., 'DP-1=40%%,60%%'). Can be specified multiple times for different outputs. If not specified, window manager decides position.",
    )

    sub.add_parser("hide", help="Hide the focused scratchpad")
    sub.add_parser("list", help="List all configured scratchpads")


def main(args: argparse.Namespace) -> int:
    """Main scratchpad toggle function"""

    if args.scratchpad_command == "toggle":
        return cmd_toggle(args)
    elif args.scratchpad_command == "hide":
        return cmd_hide(args)
    elif args.scratchpad_command == "list":
        return cmd_list(args)
    else:
        print(f"Unknown command: {args.scratchpad_command}", file=sys.stderr)
        return 1
