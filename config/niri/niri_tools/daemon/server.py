"""Socket server and niri event stream handling."""

import asyncio
import json
import os
import sys
from typing import Any

from ..common import CONFIG_FILE, SOCKET_PATH
from .config import load_config
from .notify import notify_error, notify_info, set_notify_level
from .scratchpad import ScratchpadManager
from .state import DaemonState, OutputInfo, WindowInfo, WorkspaceInfo
from .urgency import UrgencyHandler


class DaemonServer:
    """Main daemon server - handles socket, events, and config watching."""

    def __init__(self) -> None:
        self.state = DaemonState()
        self.scratchpad_manager = ScratchpadManager(self.state)
        self.urgency_handler = UrgencyHandler(self.state)
        self.server: asyncio.Server | None = None
        self.running = False
        self._needs_reconciliation = (
            False  # True if we loaded state and need to reconcile
        )
        self._tasks: list[asyncio.Task[None]] = []

    async def start(self) -> None:
        """Start the daemon."""
        print("Starting niri-tools daemon...")

        # Load initial state from niri
        self.state.load_initial_state()

        # Try to restore scratchpad state from disk
        if self.state.load_scratchpad_state():
            self._needs_reconciliation = True

        # Load config
        self._reload_config()

        # Remove stale socket
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()

        # Start socket server
        self.server = await asyncio.start_unix_server(
            self._handle_client, path=str(SOCKET_PATH)
        )
        os.chmod(SOCKET_PATH, 0o600)

        self.running = True
        print(f"Listening on {SOCKET_PATH}")

        # Run main loops
        self._tasks = [
            asyncio.create_task(self._event_stream_loop()),
            asyncio.create_task(self._config_watch_loop()),
            asyncio.create_task(self._serve_forever()),
        ]
        await asyncio.gather(*self._tasks, return_exceptions=True)

    async def stop(self) -> None:
        """Stop the daemon."""
        print("Stopping daemon...")
        self.running = False
        if self.server:
            self.server.close()
        await self.urgency_handler.cleanup_all()
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()
        # Cancel all tasks - this will cause the gather() in start() to return
        for task in self._tasks:
            task.cancel()
        print("Daemon stopped")

    async def _restart(self) -> None:
        """Restart the daemon by spawning a new instance and stopping."""
        print("Restarting daemon...")
        # Spawn new daemon via niri (so it's parented by niri, not us)
        daemon_cmd = self._get_daemon_command()
        try:
            proc = await asyncio.create_subprocess_exec(
                "niri",
                "msg",
                "action",
                "spawn",
                "--",
                *daemon_cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode != 0:
                print(f"Failed to spawn new daemon: {stderr.decode()}", file=sys.stderr)
                return
        except Exception as e:
            print(f"Failed to spawn new daemon: {e}", file=sys.stderr)
            return

        # Stop this instance
        await self.stop()

    def _get_daemon_command(self) -> list[str]:
        """Get the command to start the daemon."""
        argv0 = sys.argv[0]
        if argv0.endswith("__main__.py") or argv0.endswith("niri_tools"):
            return [sys.executable, "-m", "niri_tools", "daemon"]
        return [argv0, "daemon"]

    def _get_status(self) -> dict[str, int | str]:
        """Get daemon status information."""
        pid = os.getpid()
        ppid = os.getppid()

        def get_proc_cmdline(p: int) -> str:
            try:
                with open(f"/proc/{p}/cmdline") as f:
                    return f.read().replace("\x00", " ").strip()
            except OSError:
                return ""

        return {
            "pid": pid,
            "cmdline": get_proc_cmdline(pid),
            "ppid": ppid,
            "parent_cmdline": get_proc_cmdline(ppid),
            "socket": str(SOCKET_PATH),
        }

    async def _serve_forever(self) -> None:
        """Keep the server running."""
        if self.server:
            async with self.server:
                await self.server.serve_forever()

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        """Handle a client connection."""
        try:
            data = await reader.readline()
            if not data:
                return

            try:
                command = json.loads(data.decode())
            except json.JSONDecodeError:
                return

            response = await self._dispatch_command(command)
            if response is not None:
                writer.write((json.dumps(response) + "\n").encode())
                await writer.drain()

        except Exception as e:
            print(f"Error handling client: {e}", file=sys.stderr)
        finally:
            writer.close()
            await writer.wait_closed()

    async def _dispatch_command(self, command: dict[str, Any]) -> dict[str, Any] | None:
        """Dispatch a command to the appropriate handler."""
        cmd = command.get("cmd")

        if cmd == "toggle":
            name = command.get("name")
            if name:
                await self.scratchpad_manager.toggle(name)
            else:
                await self.scratchpad_manager.smart_toggle()

        elif cmd == "hide":
            await self.scratchpad_manager.hide()

        elif cmd == "adopt":
            window_id = command.get("window_id")
            name = command.get("name")
            await self.scratchpad_manager.adopt(window_id, name)

        elif cmd == "disown":
            window_id = command.get("window_id")
            await self.scratchpad_manager.disown(window_id)

        elif cmd == "menu":
            await self.scratchpad_manager.menu()

        elif cmd == "close":
            window_id = command.get("window_id")
            confirm = command.get("confirm", True)
            await self.scratchpad_manager.close(window_id, confirm=confirm)

        elif cmd == "restart":
            await self._restart()

        elif cmd == "stop":
            await self.stop()

        elif cmd == "status":
            return self._get_status()

        else:
            print(f"Unknown command: {cmd}", file=sys.stderr)

        return None

    async def _event_stream_loop(self) -> None:
        """Listen to niri event stream and update state."""
        while self.running:
            try:
                proc = await asyncio.create_subprocess_exec(
                    "niri",
                    "msg",
                    "-j",
                    "event-stream",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )

                if proc.stdout:
                    async for line in proc.stdout:
                        if not self.running:
                            break

                        line_str = line.decode().strip()
                        if not line_str:
                            continue

                        try:
                            event = json.loads(line_str)
                            await self._handle_event(event)
                        except json.JSONDecodeError:
                            continue

                if proc.returncode is None:
                    proc.terminate()
                    await proc.wait()

            except Exception as e:
                print(f"Event stream error: {e}", file=sys.stderr)
                if self.running:
                    await asyncio.sleep(1)  # Retry after delay

    async def _handle_event(self, event: dict[str, Any]) -> None:
        """Handle a single niri event."""
        if "WindowOpenedOrChanged" in event:
            window_data = event["WindowOpenedOrChanged"]["window"]
            window = WindowInfo.from_niri(window_data)
            is_new = window.id not in self.state.windows
            self.state.windows[window.id] = window

            if is_new:
                await self.scratchpad_manager.handle_window_opened(window)

        elif "WindowsChanged" in event:
            # Full window list - used for reconciliation on startup
            windows_data = event["WindowsChanged"]["windows"]
            window_ids = set()
            for w_data in windows_data:
                window = WindowInfo.from_niri(w_data)
                self.state.windows[window.id] = window
                window_ids.add(window.id)
                if window.is_focused:
                    self.state.focused_window_id = window.id

            # If we loaded state from disk, reconcile with actual windows
            if self._needs_reconciliation:
                self._needs_reconciliation = False
                self.state.reconcile_with_windows(window_ids)

        elif "WindowClosed" in event:
            window_id = event["WindowClosed"]["id"]
            self.state.windows.pop(window_id, None)
            was_scratchpad = window_id in self.state.window_to_scratchpad
            self.state.unregister_scratchpad_window(window_id)
            if was_scratchpad:
                self.state.save_scratchpad_state()

        elif "WindowFocusChanged" in event:
            focus_data = event["WindowFocusChanged"]
            # Clear old focus
            for w in self.state.windows.values():
                w.is_focused = False
            # Set new focus
            if "id" in focus_data:
                self.state.focused_window_id = focus_data["id"]
                if window := self.state.windows.get(focus_data["id"]):
                    window.is_focused = True
            else:
                self.state.focused_window_id = None

        elif "WorkspaceActivated" in event:
            ws_data = event["WorkspaceActivated"]
            ws_id = ws_data["id"]
            is_focused = ws_data.get("focused", False)

            # Update workspace active state - clear active on same output, set for activated
            activated_ws = self.state.workspaces.get(ws_id)
            if activated_ws:
                for ws in self.state.workspaces.values():
                    if ws.output == activated_ws.output:
                        ws.is_active = ws.id == ws_id

                if is_focused:
                    self.state.focused_output = activated_ws.output

        elif "WorkspacesChanged" in event:
            # Reload workspace list
            await self._reload_workspaces()

        elif "OutputFocusChanged" in event:
            output_data = event["OutputFocusChanged"]["output"]
            self.state.focused_output = output_data.get("name")

        elif "OutputsChanged" in event:
            outputs_data = event["OutputsChanged"]["outputs"]
            self.state.outputs.clear()
            for name, data in outputs_data.items():
                self.state.outputs[name] = OutputInfo.from_niri(name, data)

        elif "WindowUrgencyChanged" in event:
            urgency_data = event["WindowUrgencyChanged"]
            await self.urgency_handler.handle_urgency_changed(
                urgency_data["id"], urgency_data["urgent"]
            )

    async def _reload_workspaces(self) -> None:
        """Reload workspace list from niri."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "niri",
                "msg",
                "-j",
                "workspaces",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            workspaces = json.loads(stdout.decode())

            self.state.workspaces.clear()
            for ws_data in workspaces:
                ws = WorkspaceInfo.from_niri(ws_data)
                self.state.workspaces[ws.id] = ws

        except Exception as e:
            print(f"Failed to reload workspaces: {e}", file=sys.stderr)

    async def _config_watch_loop(self) -> None:
        """Watch for config file changes."""
        while self.running:
            await asyncio.sleep(1.0)

            try:
                if CONFIG_FILE.exists():
                    mtime = CONFIG_FILE.stat().st_mtime
                    if mtime > self.state.config_mtime:
                        self._reload_config(is_reload=True)
            except OSError:
                pass

    def _reload_config(self, *, is_reload: bool = False) -> None:
        """Reload configuration from file. Keeps previous config on failure."""
        try:
            config = load_config()
            # Update notify level first so it applies to subsequent notifications
            set_notify_level(config.settings.notify_level)
            # Update scratchpad configs
            self.state.scratchpad_configs = config.scratchpads
            if CONFIG_FILE.exists():
                self.state.config_mtime = CONFIG_FILE.stat().st_mtime
            print(f"Loaded {len(config.scratchpads)} scratchpad configs")
            if is_reload:
                notify_info(
                    "Scratchpad config reloaded",
                    f"Loaded {len(config.scratchpads)} scratchpads",
                )

        except Exception as e:
            # Keep previous config, just update mtime to avoid retry loop
            if CONFIG_FILE.exists():
                self.state.config_mtime = CONFIG_FILE.stat().st_mtime
            error_msg = f"Failed to load config: {e}"
            print(error_msg, file=sys.stderr)
            notify_error("Config error", error_msg)


async def run_daemon() -> int:
    """Run the daemon until interrupted."""
    server = DaemonServer()

    try:
        await server.start()
    except KeyboardInterrupt:
        pass
    finally:
        await server.stop()

    return 0
