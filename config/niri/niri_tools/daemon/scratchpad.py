"""Scratchpad management logic for the daemon."""

import asyncio
import sys

from ..common import SCRATCHPAD_WORKSPACE
from .config import ScratchpadConfig
from .notify import notify_error
from .state import DaemonState, WindowInfo


def convert_position_to_pixels(
    coords: tuple[str, str],
    output_width: int,
    output_height: int,
    window_width: int,
    window_height: int,
) -> tuple[int, int]:
    """Convert position coordinates to absolute pixels.

    Percentages represent where the window sits in its valid position range:
    - 0% = window at left/top edge of screen
    - 100% = window at right/bottom edge of screen
    - 50% = window centered

    This ensures any percentage 0-100% results in the window fully on-screen.
    Pixel values are used directly as the top-left corner position.
    """
    x_str, y_str = coords

    if x_str.endswith("%"):
        # Valid x range is [0, output_width - window_width]
        max_x = max(0, output_width - window_width)
        x = int(max_x * float(x_str[:-1]) / 100)
    else:
        x = int(x_str)

    if y_str.endswith("%"):
        # Valid y range is [0, output_height - window_height]
        max_y = max(0, output_height - window_height)
        y = int(max_y * float(y_str[:-1]) / 100)
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
            if window.is_floating:
                print(f"Hiding scratchpad '{name}'")
                await self._hide_scratchpad(name, window_id)
            else:
                # Tiled - just focus the previous window instead of hiding
                print(f"Unfocusing tiled scratchpad '{name}'")
                await self._focus_previous_window()
        elif window.workspace_id != focused_ws.id:
            # On different workspace
            if window.is_floating:
                # Floating - show it on current workspace
                print(f"Showing scratchpad '{name}'")
                await self._show_scratchpad(name, window_id, config)
            elif self.state.is_on_scratchpad_workspace(window):
                # Tiled on scratchpad workspace - move to current workspace
                print(f"Moving tiled scratchpad '{name}' to current workspace")
                await self._move_to_current_workspace(window_id)
                await self._focus_window(window_id)
            else:
                # Tiled on another workspace - just focus it where it is
                print(f"Focusing tiled scratchpad '{name}'")
                await self._focus_window(window_id)
        else:
            # On same workspace but not focused - focus it
            print(f"Focusing scratchpad '{name}'")
            await self._focus_window(window_id)

    async def smart_toggle(self) -> None:
        """Smart toggle: hide focused scratchpad or show most recent."""
        # Check if focused window is a scratchpad
        window_id = self.state.focused_window_id
        name = self.state.get_scratchpad_for_window(window_id) if window_id else None

        # If focus was briefly lost, check if previous window was a visible scratchpad
        if not name and self.state.previous_focused_window_id:
            prev_name = self.state.get_scratchpad_for_window(
                self.state.previous_focused_window_id
            )
            if prev_name:
                prev_state = self.state.scratchpads.get(prev_name)
                if prev_state and prev_state.visible:
                    # Previous window was a visible scratchpad - use it
                    window_id = self.state.previous_focused_window_id
                    name = prev_name

        if name and window_id:
            window = self.state.windows.get(window_id)
            if window and window.is_floating:
                print(f"Hiding focused scratchpad '{name}'")
                await self._hide_scratchpad(name, window_id)
            else:
                # Tiled - just focus the previous window instead of hiding
                print(f"Unfocusing tiled scratchpad '{name}'")
                await self._focus_previous_window()
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

    async def toggle_float(self, name: str | None) -> None:
        """Toggle a scratchpad between floating and tiled.

        Args:
            name: Scratchpad name (None = focused or most recent scratchpad)
        """
        name, window_id, window = await self._resolve_scratchpad(name)
        if name is None or window_id is None or window is None:
            return

        # Check if we need to move to current workspace (not focused)
        bring_to_current = window_id != self.state.focused_window_id

        if window.is_floating:
            await self._tile_scratchpad(name, window_id, bring_to_current)
        else:
            await self._float_scratchpad(name, window_id, bring_to_current)

    async def float_scratchpad(self, name: str | None) -> None:
        """Float a scratchpad window.

        Args:
            name: Scratchpad name (None = focused or most recent scratchpad)
        """
        name, window_id, window = await self._resolve_scratchpad(name)
        if name is None or window_id is None or window is None:
            return

        if window.is_floating:
            print(f"Scratchpad '{name}' is already floating")
            return

        # Check if we need to move to current workspace (not focused)
        bring_to_current = window_id != self.state.focused_window_id
        await self._float_scratchpad(name, window_id, bring_to_current)

    async def tile_scratchpad(self, name: str | None) -> None:
        """Tile a scratchpad window.

        Args:
            name: Scratchpad name (None = focused or most recent scratchpad)
        """
        name, window_id, window = await self._resolve_scratchpad(name)
        if name is None or window_id is None or window is None:
            return

        if not window.is_floating:
            print(f"Scratchpad '{name}' is already tiled")
            return

        # Check if we need to move to current workspace (not focused)
        bring_to_current = window_id != self.state.focused_window_id
        await self._tile_scratchpad(name, window_id, bring_to_current)

    async def _resolve_scratchpad(
        self, name: str | None
    ) -> tuple[str | None, int | None, "WindowInfo | None"]:
        """Resolve scratchpad name to name, window_id, and window.

        If name is None, uses the focused window's scratchpad, or falls back
        to the most recently used scratchpad with a window.

        Returns (None, None, None) on error.
        """
        if name is None:
            # Try focused window first
            if self.state.focused_window_id:
                name = self.state.get_scratchpad_for_window(
                    self.state.focused_window_id
                )
                if name:
                    window_id = self.state.focused_window_id
                    window = self.state.windows.get(window_id)
                    if window:
                        return name, window_id, window

            # Fall back to most recently used scratchpad with a window
            name = self._get_most_recent_scratchpad_with_window()
            if not name:
                await self._notify_error("No scratchpad with a window")
                return None, None, None

        # Look up by name
        scratchpad_state = self.state.scratchpads.get(name)
        if not scratchpad_state or scratchpad_state.window_id is None:
            await self._notify_error(f"Scratchpad '{name}' has no window")
            return None, None, None
        window_id = scratchpad_state.window_id

        window = self.state.windows.get(window_id)
        if not window:
            await self._notify_error(f"Window {window_id} not found")
            return None, None, None

        return name, window_id, window

    def _get_most_recent_scratchpad_with_window(self) -> str | None:
        """Get the most recently used scratchpad that has a window."""
        candidates = [
            (name, state)
            for name, state in self.state.scratchpads.items()
            if state.window_id is not None and state.window_id in self.state.windows
        ]
        if not candidates:
            return None
        return max(candidates, key=lambda x: x[1].last_used)[0]

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
            C-f: Float scratchpad window
            C-t: Tile scratchpad window
            C-d: Disown scratchpad window
            C-BackSpace: Close scratchpad window
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
                "&lt;Cr&gt; toggle / &lt;C-f&gt; float / &lt;C-t&gt; tile / "
                "&lt;C-d&gt; disown / &lt;C-BackSpace&gt; close"
                "</span>",
                "-kb-remove-char-forward",
                "Delete",
                "-kb-remove-word-back",
                "Control+Alt+h",
                "-kb-move-char-forward",
                "",
                "-kb-clear-line",
                "",
                "-kb-custom-1",
                "Control+d",
                "-kb-custom-2",
                "Control+BackSpace",
                "-kb-custom-3",
                "Control+f",
                "-kb-custom-4",
                "Control+t",
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
                    await self._notify_error(f"Scratchpad {name} has no window")
            elif exit_code == 12:
                # C-f - float
                if window_id is not None:
                    await self._float_scratchpad(name, window_id, bring_to_current=True)
                else:
                    await self._notify_error(f"Scratchpad {name} has no window")
            elif exit_code == 13:
                # C-t - tile
                if window_id is not None:
                    await self._tile_scratchpad(name, window_id, bring_to_current=True)
                else:
                    await self._notify_error(f"Scratchpad {name} has no window")

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
        notify_error("Scratchpad Error", message)

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

    async def _float_scratchpad(
        self, name: str, window_id: int, bring_to_current: bool = False
    ) -> None:
        """Float a scratchpad window and configure its size/position."""
        config = self.state.scratchpad_configs.get(name)
        if not config:
            return
        print(f"Floating scratchpad '{name}'")
        # Configure first (like _show_scratchpad does)
        await self._configure_window(window_id, config)
        # Then move to current workspace if needed
        if bring_to_current:
            await self._move_to_current_workspace(window_id)
        await self._focus_window(window_id)

    async def _tile_scratchpad(
        self, name: str, window_id: int, bring_to_current: bool = False
    ) -> None:
        """Tile a scratchpad window."""
        print(f"Tiling scratchpad '{name}'")
        # Move to current workspace first, then tile
        if bring_to_current:
            await self._move_to_current_workspace(window_id)
        await self._run_niri_action("move-window-to-tiling", "--id", str(window_id))
        await self._focus_window(window_id)

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
        """Position a window based on config.

        Positions are relative to the center of the window, not the top-left corner.
        This means "50%,50%" will truly center the window on the screen.
        """
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
                    # Calculate expected window size from config
                    window_width, window_height = self._get_expected_window_size(
                        config, output.width, output.height
                    )
                    x, y = convert_position_to_pixels(
                        coords,
                        output.width,
                        output.height,
                        window_width,
                        window_height,
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

    def _get_expected_window_size(
        self, config: ScratchpadConfig, output_width: int, output_height: int
    ) -> tuple[int, int]:
        """Calculate expected window size from config.

        Falls back to current window size from state if config doesn't specify.
        """
        width = 0
        height = 0

        if config.width:
            if config.width.endswith("%"):
                width = int(output_width * float(config.width[:-1]) / 100)
            else:
                width = int(config.width)

        if config.height:
            if config.height.endswith("%"):
                height = int(output_height * float(config.height[:-1]) / 100)
            else:
                height = int(config.height)

        return width, height

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

    async def _move_to_current_workspace(self, window_id: int) -> None:
        """Move a window to the current workspace."""
        target_output = self.state.focused_output
        if not target_output:
            return

        # Move to the focused monitor's active workspace
        await self._run_niri_action(
            "move-window-to-monitor",
            "--id",
            str(window_id),
            target_output,
        )

    async def _focus_window(self, window_id: int) -> None:
        """Focus a window by ID."""
        # Update state immediately to avoid race conditions with rapid toggles
        # (the niri event will arrive later and confirm this)
        old_focus = self.state.focused_window_id
        if old_focus != window_id:
            self.state.previous_focused_window_id = old_focus
            self.state.focused_window_id = window_id
            # Update scratchpad recency
            self.state.update_scratchpad_recency(window_id)

        await self._run_niri_action("focus-window", "--id", str(window_id))

    async def _focus_previous_window(self) -> None:
        """Focus the previously focused window, if it still exists."""
        prev_id = self.state.previous_focused_window_id
        if prev_id is not None and prev_id in self.state.windows:
            await self._focus_window(prev_id)
        else:
            print("No previous window to focus", file=sys.stderr)

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
