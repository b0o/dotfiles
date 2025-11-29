"""
Niri scratchpad module - manage scratchpad windows.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
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
    x_str, y_str = coords
    monitor_width, monitor_height = _get_monitor_dimensions(outputs, monitor_name)

    if x_str.endswith("%"):
        x_percent = float(x_str[:-1])
        x = int(monitor_width * x_percent / 100)
    else:
        x = int(x_str)

    if y_str.endswith("%"):
        y_percent = float(y_str[:-1])
        y = int(monitor_height * y_percent / 100)
    else:
        y = int(y_str)

    return x, y


def _get_monitor_dimensions(
    outputs: dict[str, Any] | None = None, monitor_name: str | None = None
) -> tuple[int, int]:
    if outputs and monitor_name and monitor_name in outputs:
        output_info = outputs[monitor_name]
        logical = output_info.get("logical", {})
        width = logical.get("width")
        height = logical.get("height")
        if width and height:
            return width, height

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


_REGEX_CACHE: dict[str, re.Pattern] = {}


def run_concurrent(commands: list[list[str]]) -> list[subprocess.CompletedProcess]:
    if not commands:
        return []

    def run_cmd(cmd: list[str]) -> subprocess.CompletedProcess:
        return subprocess.run(cmd, check=True)

    if len(commands) == 1:
        return [run_cmd(commands[0])]

    with ThreadPoolExecutor(max_workers=len(commands)) as executor:
        results = list(executor.map(run_cmd, commands))

    return results


class ScratchpadState:
    def __init__(self, name: str):
        self.name = name
        self.state_file = STATE_DIR / f"{name}.json"
        self._cached_state: dict[str, Any] | None = None
        self._cache_mtime: float | None = None
        STATE_DIR.mkdir(parents=True, exist_ok=True)

    def save_window_id(self, window_id: int, app_id: str) -> None:
        state = {"window_id": window_id, "app_id": app_id, "created_at": time.time()}
        with open(self.state_file, "w") as f:
            json.dump(state, f)
        self._cached_state = None
        self._cache_mtime = None

    def get_window_id(self) -> int | None:
        if not self.state_file.exists():
            return None

        try:
            with open(self.state_file) as f:
                state = json.load(f)

            window_id = state.get("window_id")
            if window_id:
                return window_id
            self.clear_state()
            return None
        except (json.JSONDecodeError, FileNotFoundError):
            return None

    def get_window_id_cached(self) -> int | None:
        if not self.state_file.exists():
            return None

        try:
            state = self._get_cached_state()
            if not state:
                return None

            window_id = state.get("window_id")
            if window_id:
                return window_id
            self.clear_state()
            return None
        except (json.JSONDecodeError, FileNotFoundError):
            return None

    def _get_cached_state(self) -> dict[str, Any] | None:
        if not self.state_file.exists():
            return None

        try:
            current_mtime = self.state_file.stat().st_mtime

            if (
                self._cached_state is not None
                and self._cache_mtime is not None
                and current_mtime == self._cache_mtime
            ):
                return self._cached_state

            with open(self.state_file) as f:
                self._cached_state = json.load(f)
            self._cache_mtime = current_mtime
            return self._cached_state

        except (json.JSONDecodeError, FileNotFoundError, OSError):
            return None

    def clear_state(self) -> None:
        if self.state_file.exists():
            self.state_file.unlink()
        self._cached_state = None
        self._cache_mtime = None


class UnifiedScratchpadState:
    def __init__(self):
        self.state_file = UNIFIED_STATE_FILE
        self._cached_state: dict[str, Any] | None = None
        self._cache_mtime: float | None = None

    def _load_state(self) -> dict[str, Any]:
        if not self.state_file.exists():
            return {
                "windows": {},
                "last_used": {},
                "visible": [],
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
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.state_file, "w") as f:
            json.dump(state, f, indent=2)
        self._cached_state = None
        self._cache_mtime = None

    def register_window(self, window_id: int, scratchpad_name: str) -> None:
        state = self._load_state()
        state["windows"][str(window_id)] = scratchpad_name
        state["last_used"][scratchpad_name] = time.time()
        self._save_state(state)

    def unregister_window(self, window_id: int) -> None:
        state = self._load_state()
        window_id_str = str(window_id)
        if window_id_str in state["windows"]:
            scratchpad_name = state["windows"][window_id_str]
            del state["windows"][window_id_str]
            if scratchpad_name in state["visible"]:
                state["visible"].remove(scratchpad_name)
            self._save_state(state)

    def mark_visible(self, scratchpad_name: str) -> None:
        state = self._load_state()
        if scratchpad_name not in state["visible"]:
            state["visible"].append(scratchpad_name)
        state["last_used"][scratchpad_name] = time.time()
        self._save_state(state)

    def mark_hidden(self, scratchpad_name: str) -> None:
        state = self._load_state()
        if scratchpad_name in state["visible"]:
            state["visible"].remove(scratchpad_name)
        state["last_used"][scratchpad_name] = time.time()
        self._save_state(state)

    def get_scratchpad_for_window(self, window_id: int) -> str | None:
        state = self._load_state()
        return state["windows"].get(str(window_id))

    def get_most_recent_scratchpad(self) -> str | None:
        state = self._load_state()
        if not state["last_used"]:
            return None

        sorted_scratchpads = sorted(
            state["last_used"].items(), key=lambda x: x[1], reverse=True
        )

        for name, _ in sorted_scratchpads:
            if name not in state["visible"]:
                return name

        return None

    def clean_stale_windows(self, existing_window_ids: list[int]) -> None:
        state = self._load_state()
        existing_ids_str = {str(wid) for wid in existing_window_ids}

        to_remove = []
        for window_id_str in state["windows"]:
            if window_id_str not in existing_ids_str:
                to_remove.append(window_id_str)

        if to_remove:
            for window_id_str in to_remove:
                scratchpad_name = state["windows"][window_id_str]
                del state["windows"][window_id_str]
                if scratchpad_name in state["visible"]:
                    state["visible"].remove(scratchpad_name)
            self._save_state(state)


class NiriState:
    def __init__(self):
        self.windows: list[dict[str, Any]] = []
        self.workspaces: list[dict[str, Any]] = []
        self.focused_output: dict[str, Any] = {}
        self.outputs: dict[str, Any] = {}
        self._loaded = False

    def load(self) -> None:
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

        self.position_map: dict[str | None, tuple[str, str] | None] = {}
        if position_specs:
            for spec in position_specs:
                output_name, coords = parse_position_spec(spec)
                self.position_map[output_name] = coords
        elif position:
            self.position_map[None] = parse_position(position)

        self.state = ScratchpadState(name)
        self.unified_state = UnifiedScratchpadState()

        if command is not None and not ((app_id is None) ^ (title is None)):
            raise ValueError("Must provide exactly one of app_id or title")

    def toggle_scratchpad(self) -> bool:
        niri_state = NiriState()
        niri_state.load()

        window_id = self.state.get_window_id_cached()

        if window_id is None:
            if self.command is None:
                return True
            print(f"Creating new scratchpad '{self.name}'")
            return self._create_scratchpad()

        window_info = self._get_window_info(window_id, niri_state.windows)
        if not window_info:
            self.state.clear_state()
            if self.command is None:
                return True
            return self._create_scratchpad()

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
            print(f"Hiding scratchpad '{self.name}'")
            return self._hide_scratchpad(window_id)
        elif window_workspace_id != current_workspace_id:
            print(f"Showing scratchpad '{self.name}'")
            return self._show_scratchpad(window_id) and self._focus_window(window_id)
        else:
            print(f"Focusing scratchpad '{self.name}'")
            return self._focus_window(window_id)

    def _create_scratchpad(self) -> bool:
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
        try:
            scratchpad_workspace = SCRATCHPAD_WORKSPACE

            print(f"Moving window {window_id} to workspace '{scratchpad_workspace}'")

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

            self.unified_state.mark_hidden(self.name)

            print("Successfully moved window to scratchpad workspace")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to hide scratchpad: {e}", file=sys.stderr)
            return False

    def _show_scratchpad(self, window_id: int) -> bool:
        try:
            niri_state = NiriState()
            niri_state.load()
            workspace_info = self._get_current_workspace_info(niri_state)
            if not workspace_info:
                print("Failed to get current workspace info", file=sys.stderr)
                return False

            _workspace_id, _workspace_idx, monitor_name = workspace_info

            self._configure_floating_window(window_id)

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

            self.unified_state.mark_visible(self.name)
            self.unified_state.register_window(window_id, self.name)

            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to show scratchpad: {e}", file=sys.stderr)
            return False

    def _focus_window(self, window_id: int) -> bool:
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
        try:
            subprocess.run(
                [
                    "niri",
                    "msg",
                    "action",
                    "move-window-to-floating",
                    "--id",
                    str(window_id),
                ],
                check=True,
            )

            resize_cmds: list[list[str]] = []
            if self.width is not None:
                resize_cmds.append(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-width",
                        "--id",
                        str(window_id),
                        self.width,
                    ]
                )
            if self.height is not None:
                resize_cmds.append(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-height",
                        "--id",
                        str(window_id),
                        self.height,
                    ]
                )

            if resize_cmds:
                run_concurrent(resize_cmds)

            if self.position_map:
                self._position_window(window_id)

        except subprocess.CalledProcessError as e:
            print(f"Failed to configure floating window: {e}", file=sys.stderr)

    def _position_window(self, window_id: int) -> None:
        try:
            niri_state = NiriState()
            niri_state.load()
            monitor_name = niri_state.focused_output.get("name")

            position_coords = self.position_map.get(monitor_name)

            if position_coords is None and monitor_name not in self.position_map:
                position_coords = self.position_map.get(None)

            if monitor_name in self.position_map or None in self.position_map:
                if position_coords is None:
                    subprocess.run(
                        ["niri", "msg", "action", "center-window"], check=True
                    )
                else:
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
        return next((w for w in windows if w["id"] == window_id), None)

    def _get_current_workspace_info(
        self, niri_state: NiriState
    ) -> tuple[int, int, str] | None:
        try:
            focused_monitor = niri_state.focused_output.get("name")
            if not focused_monitor:
                return None

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

        if not ((app_id is None) ^ (title is None)):
            raise ValueError("Must provide exactly one of app_id or title")

    def should_handle(self, event: dict[str, Any]) -> bool:
        return "WindowOpenedOrChanged" in event and self.waiting_for_window

    def handle(self, event: dict[str, Any]) -> None:
        window_data = event["WindowOpenedOrChanged"]["window"]

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

            save_id = self.app_id or f"title:{self.title}"
            self.state.save_window_id(window_id, save_id)

            if self.scratchpad_name:
                self.unified_state.register_window(window_id, self.scratchpad_name)
                self.unified_state.mark_visible(self.scratchpad_name)

            self._configure_new_window(window_id)

            self.waiting_for_window = False

    def _matches_window(self, window_data: dict[str, Any]) -> bool:
        if self.app_id_regex:
            window_app_id = window_data.get("app_id", "")
            return bool(self.app_id_regex.search(window_app_id))
        elif self.app_id:
            window_app_id = window_data.get("app_id", "")
            return window_app_id == self.app_id
        elif self.title_regex:
            window_title = window_data.get("title", "")
            return bool(self.title_regex.search(window_title))
        elif self.title:
            window_title = window_data.get("title", "")
            return window_title == self.title
        return False

    def launch_application(self) -> bool:
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
        try:
            subprocess.run(
                [
                    "niri",
                    "msg",
                    "action",
                    "move-window-to-floating",
                    "--id",
                    str(window_id),
                ],
                check=True,
            )

            resize_cmds: list[list[str]] = []
            if self.width is not None:
                resize_cmds.append(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-width",
                        "--id",
                        str(window_id),
                        self.width,
                    ]
                )
            if self.height is not None:
                resize_cmds.append(
                    [
                        "niri",
                        "msg",
                        "action",
                        "set-window-height",
                        "--id",
                        str(window_id),
                        self.height,
                    ]
                )

            if resize_cmds:
                run_concurrent(resize_cmds)

            if self.position_map:
                self._position_window(window_id)

            print(f"Window {window_id} configured as scratchpad")
        except subprocess.CalledProcessError as e:
            print(f"Failed to configure window: {e}", file=sys.stderr)

    def _position_window(self, window_id: int) -> None:
        try:
            niri_state = NiriState()
            niri_state.load()
            monitor_name = niri_state.focused_output.get("name")

            position_coords = self.position_map.get(monitor_name)

            if position_coords is None and monitor_name not in self.position_map:
                position_coords = self.position_map.get(None)

            if monitor_name in self.position_map or None in self.position_map:
                if position_coords is None:
                    subprocess.run(
                        ["niri", "msg", "action", "center-window"], check=True
                    )
                else:
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
    start_time = time.time()

    try:
        process = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for line in process.stdout or []:
            if time.time() - start_time > timeout:
                print("Timeout reached, stopping monitoring")
                break

            line = line.strip()
            if not line:
                continue

            try:
                event = json.loads(line)

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
    if "=" in position_spec:
        parts = position_spec.split("=", 1)
        if len(parts) == 2:
            output_name = parts[0].strip()
            position_str = parts[1].strip()
            return output_name, parse_position(position_str)

    return None, parse_position(position_spec)


def load_config() -> dict[str, Any]:
    return _load_config_recursive(CONFIG_FILE, set())


def _load_config_recursive(config_path: Path, visited: set[Path]) -> dict[str, Any]:
    try:
        config_path = config_path.resolve()
    except (OSError, RuntimeError):
        print(f"Warning: Could not resolve path {config_path}", file=sys.stderr)
        return {}

    if config_path in visited:
        print(
            f"Warning: Circular include detected for {config_path}, skipping",
            file=sys.stderr,
        )
        return {}

    if not config_path.exists():
        if config_path == CONFIG_FILE.resolve():
            return {}
        else:
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

        result: dict[str, Any] = {"scratchpads": {}}

        includes = config.get("include", [])
        if includes:
            if not isinstance(includes, list):
                includes = [includes]

            for include_path_str in includes:
                include_path = config_path.parent / include_path_str
                included_config = _load_config_recursive(include_path, visited.copy())

                if "scratchpads" in included_config:
                    result["scratchpads"].update(included_config["scratchpads"])

        if "scratchpads" in config:
            result["scratchpads"].update(config["scratchpads"])

        return result

    except (yaml.YAMLError, OSError) as e:
        print(f"Failed to load config from {config_path}: {e}", file=sys.stderr)
        return {}


def smart_toggle() -> int:
    niri_state = NiriState()
    niri_state.load()

    unified_state = UnifiedScratchpadState()

    existing_window_ids = [w["id"] for w in niri_state.windows]
    unified_state.clean_stale_windows(existing_window_ids)

    focused_window = None
    for window in niri_state.windows:
        if window.get("is_focused", False):
            focused_window = window
            break

    if focused_window:
        window_id = focused_window["id"]
        scratchpad_name = unified_state.get_scratchpad_for_window(window_id)

        if scratchpad_name:
            print(f"Hiding focused scratchpad '{scratchpad_name}'")

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

                unified_state.mark_hidden(scratchpad_name)

                return 0
            except subprocess.CalledProcessError as e:
                print(f"Failed to hide scratchpad: {e}", file=sys.stderr)
                return 1

    most_recent = unified_state.get_most_recent_scratchpad()

    if most_recent:
        print(f"Showing most recent scratchpad '{most_recent}'")

        config = load_config()
        scratchpads = config.get("scratchpads", {})

        if most_recent in scratchpads:
            scratchpad_config = scratchpads[most_recent]

            size_str = scratchpad_config.get("size")
            if size_str:
                width, height = parse_size(size_str)
            else:
                width, height = None, None

            position_config = scratchpad_config.get("position", {})
            position_specs = []
            for output, pos in position_config.items():
                if pos.lower() == "center":
                    position_specs.append(f"{output}=center")
                else:
                    position_specs.append(f"{output}={pos}")

            command = scratchpad_config.get("command")

            manager = ScratchpadManager(
                name=most_recent,
                command=command,
                app_id=scratchpad_config.get("app_id"),
                title=scratchpad_config.get("title"),
                width=width,
                height=height,
                position_specs=position_specs if position_specs else None,
            )

            return 0 if manager.toggle_scratchpad() else 1
        else:
            print(f"Scratchpad '{most_recent}' not found in config", file=sys.stderr)
            return 1
    else:
        print("No scratchpad to toggle")
        return 0


def cmd_toggle(args: argparse.Namespace) -> int:
    if args.name is None:
        return smart_toggle()

    config = load_config()
    scratchpads = config.get("scratchpads", {})

    if args.name not in scratchpads:
        if args.size:
            width, height = parse_size(args.size)
        else:
            width, height = None, None

        if args.exec is None and args.app_id is None and args.title is None:
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
        scratchpad_config = scratchpads[args.name]

        size_str = scratchpad_config.get("size")
        if size_str:
            width, height = parse_size(size_str)
        else:
            width, height = None, None

        position_config = scratchpad_config.get("position", {})
        position_specs = []
        for output, pos in position_config.items():
            if pos.lower() == "center":
                position_specs.append(f"{output}=center")
            else:
                position_specs.append(f"{output}={pos}")

        command = scratchpad_config.get("command")

        manager = ScratchpadManager(
            name=args.name,
            command=command,
            app_id=scratchpad_config.get("app_id"),
            title=scratchpad_config.get("title"),
            width=width,
            height=height,
            position_specs=position_specs if position_specs else None,
        )

    success = manager.toggle_scratchpad()

    return 0 if success else 1


def cmd_hide(_args: argparse.Namespace) -> int:
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

    if not scratchpad_window.get("is_floating", False):
        print("Focused window is not a scratchpad", file=sys.stderr)
        return 1

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

    toggle.add_argument(
        "name",
        type=str,
        nargs="?",
        default=None,
        help="Name of the scratchpad. If not provided, will hide focused scratchpad or show most recent one",
    )

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
    if args.scratchpad_command == "toggle":
        return cmd_toggle(args)
    elif args.scratchpad_command == "hide":
        return cmd_hide(args)
    elif args.scratchpad_command == "list":
        return cmd_list(args)
    else:
        print(f"Unknown command: {args.scratchpad_command}", file=sys.stderr)
        return 1
