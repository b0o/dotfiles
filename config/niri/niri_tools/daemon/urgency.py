"""Window urgency notification handling."""

import asyncio
import sys

from .state import DaemonState


class UrgencyHandler:
    """Handle window urgency changes with notifications."""

    def __init__(self, state: DaemonState):
        self.state = state
        self.active_notifications: dict[int, str] = {}  # window_id -> notification_id
        self.notification_tasks: dict[str, asyncio.Task[None]] = {}
        self.notification_processes: dict[str, asyncio.subprocess.Process] = {}

    async def handle_urgency_changed(self, window_id: int, is_urgent: bool) -> None:
        """Handle WindowUrgencyChanged event."""
        if is_urgent:
            await self._handle_urgency_set(window_id)
        else:
            await self._handle_urgency_cleared(window_id)

    async def _handle_urgency_set(self, window_id: int) -> None:
        """Handle when window becomes urgent."""
        # Dismiss existing notification for this window first
        if window_id in self.active_notifications:
            await self._dismiss_notification(self.active_notifications[window_id])

        window = self.state.windows.get(window_id)
        if not window:
            return

        app_name = window.app_id or "Unknown App"
        window_title = window.title or f"Window {window_id}"

        notification_id = await self._send_persistent_notification(
            app_name, window_title, window_id
        )
        if notification_id:
            self.active_notifications[window_id] = notification_id
            print(f"Urgency notification sent for: {app_name}")

    async def _handle_urgency_cleared(self, window_id: int) -> None:
        """Handle when window urgency is cleared."""
        if window_id in self.active_notifications:
            notification_id = self.active_notifications.pop(window_id)
            await self._dismiss_notification(notification_id)
            print(f"Urgency cleared for window {window_id}")

    async def _send_persistent_notification(
        self, app_name: str, window_title: str, window_id: int
    ) -> str | None:
        """Send persistent notification and return notification ID.

        notify-send -p -A outputs the notification ID first, then keeps running
        and outputs the action name when clicked. We keep the process running
        and read lines asynchronously.
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                "notify-send",
                "-p",
                "-u", "normal",
                "-t", "0",
                "-A", "default=Focus",
                app_name,
                window_title,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            if not proc.stdout:
                return None

            # Read the notification ID (first line)
            line = await proc.stdout.readline()
            notification_id = line.decode().strip()

            if not notification_id:
                proc.terminate()
                return None

            # Store process for later cleanup
            self.notification_processes[notification_id] = proc

            # Start listening for action in background (process stays running)
            task = asyncio.create_task(
                self._listen_for_action(notification_id, window_id, proc)
            )
            self.notification_tasks[notification_id] = task
            return notification_id

        except Exception as e:
            print(f"Failed to send notification: {e}", file=sys.stderr)

        return None

    async def _listen_for_action(
        self, notification_id: str, window_id: int, proc: asyncio.subprocess.Process
    ) -> None:
        """Listen for action responses from notification process.

        The notify-send process stays running after outputting the notification ID.
        When the user clicks an action, it outputs the action name and exits.
        """
        try:
            if not proc.stdout:
                return

            # Read action name (second line, output when user clicks)
            async for line in proc.stdout:
                action_name = line.decode().strip()
                if action_name == "default":
                    await self._focus_window(window_id)
                break  # Only handle first action

        except asyncio.CancelledError:
            pass
        except Exception as e:
            print(f"Error listening for notification action: {e}", file=sys.stderr)
        finally:
            self._cleanup_notification(notification_id, window_id)

    async def _focus_window(self, window_id: int) -> None:
        """Focus a window by ID."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "niri", "msg", "action", "focus-window", "--id", str(window_id),
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode == 0:
                print(f"Focused window {window_id}")
            else:
                print(f"Failed to focus window {window_id}: {stderr.decode()}", file=sys.stderr)
        except Exception as e:
            print(f"Failed to focus window {window_id}: {e}", file=sys.stderr)

    async def _dismiss_notification(self, notification_id: str) -> None:
        """Dismiss a notification by ID."""
        # Cancel the listener task if running
        if notification_id in self.notification_tasks:
            self.notification_tasks[notification_id].cancel()
            try:
                await self.notification_tasks[notification_id]
            except asyncio.CancelledError:
                pass

        # Terminate the process if still running
        if notification_id in self.notification_processes:
            proc = self.notification_processes.pop(notification_id)
            proc.terminate()

        # Replace with short-lived notification to dismiss visually
        try:
            proc = await asyncio.create_subprocess_exec(
                "notify-send",
                "-r", notification_id,
                "-t", "1",
                "",  # Empty body
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.communicate()
        except Exception:
            pass

    def _cleanup_notification(self, notification_id: str, window_id: int) -> None:
        """Clean up notification tracking."""
        self.notification_tasks.pop(notification_id, None)
        self.notification_processes.pop(notification_id, None)
        if window_id in self.active_notifications:
            if self.active_notifications[window_id] == notification_id:
                del self.active_notifications[window_id]

    async def cleanup_all(self) -> None:
        """Clean up all active notifications on shutdown."""
        for task in self.notification_tasks.values():
            task.cancel()
        # Wait for tasks to complete
        if self.notification_tasks:
            await asyncio.gather(*self.notification_tasks.values(), return_exceptions=True)
        for notification_id in list(self.active_notifications.values()):
            await self._dismiss_notification(notification_id)
