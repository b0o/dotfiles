"""Scratchpad management logic for the daemon."""

import asyncio
import subprocess
import sys

from ..common import SCRATCHPAD_WORKSPACE
from .config import ScratchpadConfig
from .state import DaemonState, WindowInfo


def convert_coordinates_to_pixels(
    coords: tuple[str, str],
    output_width: int,
    output_height: int,
) -> tuple[int, int]:
    """Convert percentage or pixel coordinates to absolute pixels."""
    x_str, y_str = coords

    if x_str.endswith("%"):
        x = int(output_width * float(x_str[:-1]) / 100)
    else:
        x = int(x_str)

    if y_str.endswith("%"):
        y = int(output_height * float(y_str[:-1]) / 100)
    else:
        y = int(y_str)

    return x, y


class ScratchpadManager:
    """Manages scratchpad operations using in-memory state."""

    def __init__(self, state: DaemonState):
        self.state = state

    async def toggle(self, name: str) -> None:
        """Toggle a named scratchpad."""
        config = self.state.scratchpad_configs.get(name)
        if not config:
            print(f"Unknown scratchpad: {name}", file=sys.stderr)
            return

        scratchpad_state = self.state.scratchpads.get(name)
        window_id = scratchpad_state.window_id if scratchpad_state else None

        if window_id is None:
            # No window exists - spawn it
            if config.command:
                print(f"Creating new scratchpad '{name}'")
                await self._spawn_scratchpad(name, config)
            return

        window = self.state.windows.get(window_id)
        if not window:
            # Window no longer exists
            self.state.unregister_scratchpad_window(window_id)
            if config.command:
                print(f"Creating new scratchpad '{name}'")
                await self._spawn_scratchpad(name, config)
            return

        focused_ws = self.state.get_focused_workspace()
        if not focused_ws:
            print("Failed to get focused workspace", file=sys.stderr)
            return

        if window.is_focused:
            # Currently focused - hide it
            print(f"Hiding scratchpad '{name}'")
            await self._hide_scratchpad(name, window_id)
        elif window.workspace_id != focused_ws.id:
            # On different workspace - show it
            print(f"Showing scratchpad '{name}'")
            await self._show_scratchpad(name, window_id, config)
        else:
            # On same workspace but not focused - focus it
            print(f"Focusing scratchpad '{name}'")
            await self._focus_window(window_id)

    async def smart_toggle(self) -> None:
        """Smart toggle: hide focused scratchpad or show most recent."""
        # Check if focused window is a scratchpad
        if self.state.focused_window_id:
            name = self.state.get_scratchpad_for_window(self.state.focused_window_id)
            if name:
                print(f"Hiding focused scratchpad '{name}'")
                await self._hide_scratchpad(name, self.state.focused_window_id)
                return

        # Show most recent hidden scratchpad
        name = self.state.get_most_recent_hidden_scratchpad()
        if name:
            print(f"Showing most recent scratchpad '{name}'")
            await self.toggle(name)
        else:
            print("No scratchpad to toggle")

    async def hide(self) -> None:
        """Hide the focused scratchpad if any."""
        if not self.state.focused_window_id:
            print("No focused window", file=sys.stderr)
            return

        window = self.state.windows.get(self.state.focused_window_id)
        if not window or not window.is_floating:
            print("Focused window is not a floating window", file=sys.stderr)
            return

        name = self.state.get_scratchpad_for_window(self.state.focused_window_id)
        if name:
            await self._hide_scratchpad(name, self.state.focused_window_id)
        else:
            # Not a tracked scratchpad, but still floating - hide it anyway
            await self._move_to_scratchpad_workspace(self.state.focused_window_id)

    async def adopt(self, window_id: int | None, name: str | None) -> None:
        """Adopt an existing window as a scratchpad.

        Args:
            window_id: Window ID to adopt (None = focused window)
            name: Scratchpad name (None = prompt with rofi)
        """
        # Resolve window ID
        if window_id is None:
            window_id = self.state.focused_window_id
            if window_id is None:
                await self._notify_error("No focused window to adopt")
                return

        window = self.state.windows.get(window_id)
        if not window:
            await self._notify_error(f"Window {window_id} not found")
            return

        # Check if window is already a scratchpad
        existing_name = self.state.get_scratchpad_for_window(window_id)
        if existing_name:
            await self._notify_error(
                f"Window {window_id} is already scratchpad {existing_name}"
            )
            return

        # Get available scratchpads (those without existing windows)
        available = self._get_available_scratchpads()
        if not available:
            await self._notify_error("No scratchpads available")
            return

        # Resolve scratchpad name
        if name is None:
            name = await self._prompt_scratchpad_name(available)
            if name is None:
                # User cancelled
                return

        # Validate scratchpad name
        if name not in self.state.scratchpad_configs:
            await self._notify_error(f"Unknown scratchpad: {name}")
            return

        # Check if chosen scratchpad already has a window
        scratchpad_state = self.state.scratchpads.get(name)
        if scratchpad_state and scratchpad_state.window_id is not None:
            # Verify the window still exists
            if scratchpad_state.window_id in self.state.windows:
                await self._notify_error(
                    f"Scratchpad {name} already has window {scratchpad_state.window_id}"
                )
                return
            # Window no longer exists, clear it
            self.state.unregister_scratchpad_window(scratchpad_state.window_id)

        # Adopt the window
        config = self.state.scratchpad_configs[name]
        print(f"Adopting window {window_id} as scratchpad {name}")

        self.state.register_scratchpad_window(name, window_id)
        self.state.mark_scratchpad_visible(name)
        await self._configure_window(window_id, config)
        self.state.save_scratchpad_state()

        print(f"Window {window_id} adopted as scratchpad {name}")

    async def disown(self, window_id: int | None) -> None:
        """Disown a scratchpad window and tile it.

        Args:
            window_id: Window ID to disown (None = focused window)
        """
        # Resolve window ID
        if window_id is None:
            window_id = self.state.focused_window_id
            if window_id is None:
                await self._notify_error("No focused window to disown")
                return

        window = self.state.windows.get(window_id)
        if not window:
            await self._notify_error(f"Window {window_id} not found")
            return

        # Check if window is a scratchpad
        name = self.state.get_scratchpad_for_window(window_id)
        if not name:
            await self._notify_error(f"Window {window_id} is not a scratchpad")
            return

        print(f"Disowning scratchpad '{name}' (window {window_id})")

        # Unregister from scratchpad tracking
        self.state.unregister_scratchpad_window(window_id)

        # Move to tiling
        await self._run_niri_action("move-window-to-tiling", "--id", str(window_id))

        self.state.save_scratchpad_state()
        print(f"Window {window_id} disowned from scratchpad '{name}'")

    async def close(self, window_id: int | None, *, confirm: bool = True) -> None:
        """Close a scratchpad window.

        Args:
            window_id: Window ID to close (None = focused window)
            confirm: Whether to show confirmation prompt
        """
        # Resolve window ID
        if window_id is None:
            window_id = self.state.focused_window_id
            if window_id is None:
                await self._notify_error("No focused window to close")
                return

        window = self.state.windows.get(window_id)
        if not window:
            await self._notify_error(f"Window {window_id} not found")
            return

        # Check if window is a scratchpad
        name = self.state.get_scratchpad_for_window(window_id)
        if not name:
            await self._notify_error(f"Window {window_id} is not a scratchpad")
            return

        if confirm:
            confirmed = await self._confirm_close(name, window)
            if not confirmed:
                return

        print(f"Closing scratchpad '{name}' (window {window_id})")
        await self._run_niri_action("close-window", "--id", str(window_id))

    async def _confirm_close(self, name: str, window: WindowInfo) -> bool:
        """Show confirmation prompt for closing a scratchpad. Returns True if confirmed."""
        # Show the scratchpad first to give user context
        config = self.state.scratchpad_configs.get(name)
        if config:
            await self._show_scratchpad(name, window.id, config)

        try:
            title = window.title or window.app_id or name
            proc = await asyncio.create_subprocess_exec(
                "rofi",
                "-dmenu",
                "-p",
                f"Close '{name}'?",
                "-mesg",
                f"<span size='small'>{title}</span>",
                "-lines",
                "2",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            input_data = b"Close\nCancel"
            stdout, _ = await proc.communicate(input=input_data)

            if proc.returncode != 0:
                return False

            selected = stdout.decode().strip()
            return selected == "Close"

        except Exception as e:
            print(f"Failed to run rofi: {e}", file=sys.stderr)
            return False

    async def menu(self) -> None:
        """Show scratchpad menu with rofi.

        Keybindings:
            Enter: Toggle scratchpad
            C-d: Disown scratchpad window
            C-q: Close scratchpad window
        """
        items: list[tuple[str, str]] = []  # (display_text, name)
        # Sort by: 1) has window (True first), 2) MRU (most recent first), 3) alpha
        sorted_names = sorted(
            self.state.scratchpad_configs.keys(),
            key=lambda n: (
                not self._scratchpad_has_window(n),
                -self._get_scratchpad_last_used(n),
                n,
            ),
        )
        for name in sorted_names:
            has_window = self._scratchpad_has_window(name)
            icon = "" if has_window else ""
            color = "#B48EFA" if has_window else "#9587af"
            items.append((f'<span color="{color}">{icon}</span>  {name}', name))

        if not items:
            print("No scratchpads configured")
            return

        # Show rofi menu
        try:
            proc = await asyncio.create_subprocess_exec(
                "rofi",
                "-dmenu",
                "-p",
                "Scratchpad",
                "-markup-rows",
                "-format",
                "i",  # Return index
                "-mesg",
                "<span size='small' alpha='70%'>"
                "&lt;Cr&gt; toggle / &lt;C-d&gt; disown / &lt;C-BackSpace&gt; close"
                "</span>",
                "-kb-remove-char-forward",
                "Delete",
                "-kb-remove-word-back",
                "Control+Alt+h",
                "-kb-custom-1",
                "Control+d",
                "-kb-custom-2",
                "Control+BackSpace",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            input_data = "\n".join(display for display, _ in items).encode()
            stdout, _ = await proc.communicate(input=input_data)

            exit_code = proc.returncode
            if exit_code == 1:
                # User cancelled (Escape)
                return

            index_str = stdout.decode().strip()
            if not index_str:
                return

            index = int(index_str)
            if not (0 <= index < len(items)):
                return

            _, name = items[index]
            scratchpad_state = self.state.scratchpads.get(name)
            window_id = scratchpad_state.window_id if scratchpad_state else None

            if exit_code == 0:
                # Enter - toggle
                await self.toggle(name)
            elif exit_code == 10:
                # C-d - disown
                if window_id is not None:
                    await self.disown(window_id)
                else:
                    await self._notify_error(f"Scratchpad {name} not found")
            elif exit_code == 11:
                # C-BackSpace - close
                if window_id is not None:
                    await self.close(window_id, confirm=True)
                else:
                    await self._notify_error(f"Scratchpad {name} not found")

        except Exception as e:
            print(f"Failed to run rofi: {e}", file=sys.stderr)

    def _scratchpad_has_window(self, name: str) -> bool:
        """Check if a scratchpad has an existing window."""
        scratchpad_state = self.state.scratchpads.get(name)
        if scratchpad_state is None or scratchpad_state.window_id is None:
            return False
        return scratchpad_state.window_id in self.state.windows

    def _get_scratchpad_last_used(self, name: str) -> float:
        """Get the last_used timestamp for a scratchpad (0.0 if never used)."""
        scratchpad_state = self.state.scratchpads.get(name)
        return scratchpad_state.last_used if scratchpad_state else 0.0

    def _get_available_scratchpads(self) -> list[str]:
        """Get scratchpad names that don't have existing windows."""
        available = []
        for name in self.state.scratchpad_configs:
            scratchpad_state = self.state.scratchpads.get(name)
            if scratchpad_state is None or scratchpad_state.window_id is None:
                available.append(name)
            elif scratchpad_state.window_id not in self.state.windows:
                # Window no longer exists
                available.append(name)
        return sorted(available)

    async def _prompt_scratchpad_name(self, available: list[str]) -> str | None:
        """Prompt user to select a scratchpad name using rofi."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "rofi",
                "-dmenu",
                "-p",
                "Adopt as scratchpad",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            input_data = "\n".join(available).encode()
            stdout, _ = await proc.communicate(input=input_data)

            if proc.returncode != 0:
                # User cancelled or error
                return None

            selected = stdout.decode().strip()
            if selected and selected in available:
                return selected
            return None

        except Exception as e:
            print(f"Failed to run rofi: {e}", file=sys.stderr)
            return None

    async def _notify_error(self, message: str) -> None:
        """Show an error notification."""
        print(f"Error: {message}", file=sys.stderr)
        try:
            subprocess.run(
                ["notify-send", "-u", "critical", "Scratchpad Error", message],
                check=False,
            )
        except Exception:
            pass

    async def _spawn_scratchpad(self, name: str, config: ScratchpadConfig) -> None:
        """Spawn a new scratchpad window via niri.

        Uses 'niri msg action spawn' so the process is parented by niri,
        not the daemon. This way scratchpads survive daemon restarts.
        """
        if name in self.state.pending_spawns:
            print(f"Scratchpad '{name}' already spawning", file=sys.stderr)
            return

        self.state.pending_spawns.add(name)

        try:
            if config.command:
                print(f"Launching {' '.join(config.command)}...")
                # Use niri spawn so process is parented by niri, not daemon
                await self._run_niri_action("spawn", "--", *config.command)
        except Exception as e:
            print(f"Failed to spawn scratchpad: {e}", file=sys.stderr)
            self.state.pending_spawns.discard(name)

    async def handle_window_opened(self, window: WindowInfo) -> None:
        """Handle a newly opened window - check if it matches a pending spawn."""
        for name in list(self.state.pending_spawns):
            config = self.state.scratchpad_configs.get(name)
            if not config:
                self.state.pending_spawns.discard(name)
                continue

            if self._matches_config(window, config):
                print(f"Detected window for scratchpad '{name}' (ID: {window.id})")
                self.state.pending_spawns.discard(name)
                self.state.register_scratchpad_window(name, window.id)
                self.state.mark_scratchpad_visible(name)
                await self._configure_window(window.id, config)
                self.state.save_scratchpad_state()
                return

    def _matches_config(self, window: WindowInfo, config: ScratchpadConfig) -> bool:
        """Check if a window matches a scratchpad config."""
        if config.app_id_regex:
            return bool(config.app_id_regex.search(window.app_id))
        elif config.app_id:
            return window.app_id == config.app_id
        elif config.title_regex:
            return bool(config.title_regex.search(window.title))
        elif config.title:
            return window.title == config.title
        return False

    async def _hide_scratchpad(self, name: str, window_id: int) -> None:
        """Hide a scratchpad by moving to hidden workspace."""
        await self._move_to_scratchpad_workspace(window_id)
        self.state.mark_scratchpad_hidden(name)
        self.state.save_scratchpad_state()

    async def _show_scratchpad(
        self, name: str, window_id: int, config: ScratchpadConfig
    ) -> None:
        """Show a scratchpad on the current monitor."""
        if not self.state.focused_output:
            print("No focused output", file=sys.stderr)
            return

        # Configure window (floating, size)
        await self._configure_window(window_id, config)

        # Move to current monitor
        await self._run_niri_action(
            "move-window-to-monitor", "--id", str(window_id), self.state.focused_output
        )

        # Focus it
        await self._focus_window(window_id)

        self.state.mark_scratchpad_visible(name)
        self.state.register_scratchpad_window(name, window_id)
        self.state.save_scratchpad_state()

    async def _configure_window(self, window_id: int, config: ScratchpadConfig) -> None:
        """Configure a window as floating with size and position."""
        # Make floating
        await self._run_niri_action("move-window-to-floating", "--id", str(window_id))

        # Set size
        tasks = []
        if config.width:
            tasks.append(
                self._run_niri_action(
                    "set-window-width", "--id", str(window_id), config.width
                )
            )
        if config.height:
            tasks.append(
                self._run_niri_action(
                    "set-window-height", "--id", str(window_id), config.height
                )
            )

        if tasks:
            await asyncio.gather(*tasks)

        # Set position
        await self._position_window(window_id, config)

    async def _position_window(self, window_id: int, config: ScratchpadConfig) -> None:
        """Position a window based on config."""
        if not config.position_map:
            return

        output_name = self.state.focused_output
        coords = config.position_map.get(output_name)

        # Fall back to default position if output not in map
        if coords is None and output_name not in config.position_map:
            coords = config.position_map.get(None)

        if output_name in config.position_map or None in config.position_map:
            if coords is None:
                await self._run_niri_action("center-window", "--id", str(window_id))
            else:
                output = self.state.outputs.get(output_name or "")
                if output:
                    x, y = convert_coordinates_to_pixels(
                        coords, output.width, output.height
                    )
                    await self._run_niri_action(
                        "move-floating-window",
                        "--id",
                        str(window_id),
                        "--x",
                        str(x),
                        "--y",
                        str(y),
                    )

    async def _move_to_scratchpad_workspace(self, window_id: int) -> None:
        """Move a window to the hidden scratchpad workspace."""
        await self._run_niri_action(
            "move-window-to-workspace",
            "--window-id",
            str(window_id),
            "--focus",
            "false",
            SCRATCHPAD_WORKSPACE,
        )

    async def _focus_window(self, window_id: int) -> None:
        """Focus a window by ID."""
        await self._run_niri_action("focus-window", "--id", str(window_id))

    async def _run_niri_action(self, action: str, *args: str) -> None:
        """Run a niri msg action command."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "niri",
                "msg",
                "action",
                action,
                *args,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode != 0:
                print(
                    f"niri action {action} failed: {stderr.decode()}", file=sys.stderr
                )
        except Exception as e:
            print(f"Failed to run niri action {action}: {e}", file=sys.stderr)
