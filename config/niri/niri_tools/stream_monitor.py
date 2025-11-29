"""
Niri stream monitor module - monitor event stream for notifications and state tracking.
"""

import argparse
import json
import subprocess
import sys
import threading
import time
from typing import Any

from .common import NIRI_STATE_FILE, EventHandler, get_window_info


class WindowUrgencyHandler(EventHandler):
    """Handle window urgency changes with notifications"""

    def __init__(self):
        self.active_notifications: dict[int, str] = {}  # window_id -> notification_id
        self.notification_window_map: dict[
            str, int
        ] = {}  # notification_id -> window_id
        self.notification_processes: dict[
            str, subprocess.Popen
        ] = {}  # notification_id -> process

    def should_handle(self, event: dict[str, Any]) -> bool:
        return "WindowUrgencyChanged" in event

    def handle(self, event: dict[str, Any]) -> None:
        urgency_data = event["WindowUrgencyChanged"]
        window_id = urgency_data["id"]
        is_urgent = urgency_data["urgent"]

        if is_urgent:
            self._handle_urgency_set(window_id)
        else:
            self._handle_urgency_cleared(window_id)

    def _handle_urgency_set(self, window_id: int) -> None:
        """Handle when window becomes urgent"""
        window_info = get_window_info(window_id)
        if window_info:
            app_name = window_info.get("app_id", "Unknown App")
            window_title = window_info.get("title", f"Window {window_id}")
            notification_id = self._send_persistent_notification(
                app_name, window_title, window_id
            )
            if notification_id:
                self.active_notifications[window_id] = notification_id
                self.notification_window_map[notification_id] = window_id
            print(f"Urgency notification sent for: {app_name}")

    def _handle_urgency_cleared(self, window_id: int) -> None:
        """Handle when window urgency is cleared"""
        if window_id in self.active_notifications:
            notification_id = self.active_notifications[window_id]
            if notification_id in self.notification_processes:
                self._dismiss_notification(notification_id)
            else:
                del self.active_notifications[window_id]
                if notification_id in self.notification_window_map:
                    del self.notification_window_map[notification_id]
            print(f"Urgency cleared for window {window_id}")

    def _send_persistent_notification(
        self, app_name: str, window_title: str, window_id: int
    ) -> str:
        """Send persistent notification and return notification ID"""
        try:
            cmd = [
                "notify-send",
                "-p",
                "-u",
                "normal",
                "-t",
                "0",
                "-A",
                "default=Focus",
                app_name,
                window_title,
            ]

            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )

            if process.stdout:
                notification_id = process.stdout.readline().strip()
            else:
                notification_id = ""

            if notification_id:
                self.notification_processes[notification_id] = process
                threading.Thread(
                    target=self._listen_for_action,
                    args=(notification_id, window_id, process),
                    daemon=True,
                ).start()
                return notification_id
            else:
                process.terminate()
                return ""

        except Exception as e:
            print(
                f"Failed to send notification for: {app_name} - {window_title}: {e}",
                file=sys.stderr,
            )
            return ""

    def _listen_for_action(
        self, notification_id: str, window_id: int, process: subprocess.Popen
    ) -> None:
        """Listen for action responses from notify-send process"""
        try:
            if process.stdout:
                for line in process.stdout:
                    action_name = line.strip()
                    if action_name:
                        if action_name == "default":
                            self._focus_window(window_id)
                        self._cleanup_notification_process(notification_id)
                        break

        except Exception as e:
            print(
                f"Error listening for actions on notification {notification_id}: {e}",
                file=sys.stderr,
            )
        finally:
            self._cleanup_notification_process(notification_id)

    def _focus_window(self, window_id: int) -> None:
        """Focus a window by ID using niri"""
        try:
            subprocess.run(
                ["niri", "msg", "action", "focus-window", "--id", str(window_id)],
                capture_output=True,
                text=True,
                check=True,
            )
            print(f"Focused window {window_id}")
        except subprocess.CalledProcessError as e:
            print(f"Failed to focus window {window_id}: {e}", file=sys.stderr)

    def _cleanup_notification_process(self, notification_id: str) -> None:
        """Clean up notification process and mappings"""
        if notification_id in self.notification_processes:
            process = self.notification_processes[notification_id]
            process.terminate()
            del self.notification_processes[notification_id]

        if notification_id in self.notification_window_map:
            window_id = self.notification_window_map[notification_id]
            if window_id in self.active_notifications:
                del self.active_notifications[window_id]
            del self.notification_window_map[notification_id]

    def _dismiss_notification(self, notification_id: str) -> None:
        """Dismiss a notification by ID"""
        try:
            subprocess.run(
                ["notify-send", "-r", notification_id, "-t", "1", ""], check=True
            )
            self._cleanup_notification_process(notification_id)
        except subprocess.CalledProcessError as e:
            print(
                f"Failed to dismiss notification {notification_id}: {e}",
                file=sys.stderr,
            )


class NiriStateTracker(EventHandler):
    """Track and cache niri state for fast scratchpad access"""

    def __init__(self):
        self.state = {
            "windows": [],
            "workspaces": [],
            "focused_output": {},
            "outputs": {},
            "last_updated": time.time(),
        }
        self._load_initial_state()
        self._save_state()

    def should_handle(self, event: dict[str, Any]) -> bool:
        return any(
            key in event
            for key in [
                "WindowOpenedOrChanged",
                "WindowsChanged",
                "WindowClosed",
                "WindowFocusChanged",
                "WorkspaceActivated",
                "WorkspacesChanged",
                "OutputFocusChanged",
                "OutputsChanged",
            ]
        )

    def handle(self, event: dict[str, Any]) -> None:
        state_changed = False

        if "WindowOpenedOrChanged" in event:
            self._handle_window_opened_or_changed(event["WindowOpenedOrChanged"])
            state_changed = True
        elif "WindowsChanged" in event:
            self._handle_windows_changed(event["WindowsChanged"])
            state_changed = True
        elif "WindowClosed" in event:
            self._handle_window_closed(event["WindowClosed"])
            state_changed = True
        elif "WindowFocusChanged" in event:
            self._handle_window_focus_changed(event["WindowFocusChanged"])
            state_changed = True

        elif "WorkspaceActivated" in event:
            self._handle_workspace_activated(event["WorkspaceActivated"])
            state_changed = True
        elif "WorkspacesChanged" in event:
            self._reload_workspaces()
            state_changed = True

        elif "OutputFocusChanged" in event:
            self._handle_output_focus_changed(event["OutputFocusChanged"])
            state_changed = True
        elif "OutputsChanged" in event:
            self._handle_outputs_changed(event["OutputsChanged"])
            state_changed = True

        if state_changed:
            self.state["last_updated"] = time.time()
            self._save_state()

    def _load_initial_state(self) -> None:
        """Load initial state from niri commands"""
        try:
            result = subprocess.run(
                ["niri", "msg", "-j", "windows"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.state["windows"] = json.loads(result.stdout)

            result = subprocess.run(
                ["niri", "msg", "-j", "workspaces"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.state["workspaces"] = json.loads(result.stdout)

            result = subprocess.run(
                ["niri", "msg", "-j", "focused-output"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.state["focused_output"] = json.loads(result.stdout)

            result = subprocess.run(
                ["niri", "msg", "-j", "outputs"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.state["outputs"] = json.loads(result.stdout)

        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"Failed to load initial niri state: {e}", file=sys.stderr)

    def _handle_window_opened_or_changed(self, window_data: dict[str, Any]) -> None:
        """Update or add window in state"""
        window_id = window_data["window"]["id"]

        for i, window in enumerate(self.state["windows"]):
            if window["id"] == window_id:
                self.state["windows"][i] = window_data["window"]
                return

        self.state["windows"].append(window_data["window"])

    def _handle_windows_changed(self, windows_data: dict[str, Any]) -> None:
        """Handle bulk window changes"""
        self.state["windows"] = windows_data["windows"]

    def _handle_window_closed(self, window_data: dict[str, Any]) -> None:
        """Remove window from state"""
        window_id = window_data["id"]
        self.state["windows"] = [
            w for w in self.state["windows"] if w["id"] != window_id
        ]

    def _handle_window_focus_changed(self, focus_data: dict[str, Any]) -> None:
        """Update window focus state"""
        for window in self.state["windows"]:
            window["is_focused"] = False

        if "id" in focus_data:
            focused_id = focus_data["id"]
            for window in self.state["windows"]:
                if window["id"] == focused_id:
                    window["is_focused"] = True
                    break

    def _handle_workspace_activated(self, workspace_data: dict[str, Any]) -> None:
        """Update active workspace"""
        workspace_id = workspace_data["id"]
        is_focused = workspace_data.get("focused", False)

        for workspace in self.state["workspaces"]:
            workspace["is_active"] = False

        for workspace in self.state["workspaces"]:
            if workspace["id"] == workspace_id:
                workspace["is_active"] = True
                if is_focused and "output" in workspace:
                    self.state["focused_output"] = {"name": workspace["output"]}
                break

    def _handle_output_focus_changed(self, output_data: dict[str, Any]) -> None:
        """Update focused output"""
        self.state["focused_output"] = output_data["output"]

    def _handle_outputs_changed(self, outputs_data: dict[str, Any]) -> None:
        """Update monitor/output information"""
        self.state["outputs"] = outputs_data["outputs"]

    def _reload_workspaces(self) -> None:
        """Reload workspace list from niri"""
        try:
            result = subprocess.run(
                ["niri", "msg", "-j", "workspaces"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.state["workspaces"] = json.loads(result.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"Failed to reload workspaces: {e}", file=sys.stderr)

    def _save_state(self) -> None:
        """Save state to file atomically"""
        try:
            temp_file = NIRI_STATE_FILE.with_suffix(".tmp")
            with open(temp_file, "w") as f:
                json.dump(self.state, f, separators=(",", ":"))
            temp_file.replace(NIRI_STATE_FILE)
        except OSError as e:
            print(f"Failed to save niri state: {e}", file=sys.stderr)


def add_arguments(_parser: argparse.ArgumentParser) -> None:
    """Add stream monitor-specific arguments to the parser."""
    # No specific arguments needed for stream monitor currently
    pass


def main(_args: argparse.Namespace) -> int:
    """Monitor niri event stream with configurable handlers"""
    handlers: list[EventHandler] = [
        WindowUrgencyHandler(),
        NiriStateTracker(),
    ]

    try:
        process = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for line in process.stdout or []:
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

    except KeyboardInterrupt:
        print("\nMonitoring stopped")
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0
