#!/usr/bin/env bash
# Wrapper for opencode that tracks focus via Zellij pane state
# Polls Zellij to check if this pane is focused

set -e

INSTANCE_ID="${ZELLIJ_PANE_ID:-$$}"
FOCUS_FILE="/tmp/opencode-focus-${INSTANCE_ID}"

# Initialize
echo "1" >"$FOCUS_FILE"
export OPENCODE_FOCUS_FILE="$FOCUS_FILE"

cleanup() {
  # Kill background watcher
  [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
  rm -f "$FOCUS_FILE"
}

trap cleanup EXIT INT TERM

# Background process to poll Zellij focus state
if [[ -n "$ZELLIJ_PANE_ID" ]]; then
  (
    while true; do
      # Get current pane info from Zellij
      # zellij action dump-layout gives us pane info including focus
      PANE_INFO=$(zellij action dump-layout 2>/dev/null || echo "")

      # Check if our pane ID is the focused one
      # This is a rough heuristic - look for our pane being marked as focused
      if echo "$PANE_INFO" | grep -q "\"pane_id\":${ZELLIJ_PANE_ID}.*\"is_focused\":true"; then
        echo "1" >"$FOCUS_FILE"
      else
        # Simpler check - if we can't determine, check if any output indicates focus
        # For now, just keep the current state
        :
      fi

      sleep 0.5
    done
  ) &
  WATCHER_PID=$!
fi

# Run opencode with full TTY access
exec opencode "$@"
