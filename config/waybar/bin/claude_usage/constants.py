"""Constants for Claude usage monitor."""

import os

# Timing
CHECK_INTERVAL = 60.0
OUTPUT_INTERVAL = 5.0

# Display
BAR_WIDTH = 46
CHART_HEIGHT = 5  # Number of rows for usage charts (8 levels per row)

# File paths
HISTORY_FILE = os.path.expanduser("~/.local/share/claude-usage.json")
CLAUDE_CREDS_PATH = os.path.expanduser("~/.claude/.credentials.json")
OPENCODE_CREDS_PATH = os.path.expanduser("~/.local/share/opencode/auth.json")

# OAuth
OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
OAUTH_PROFILE_URL = "https://api.anthropic.com/api/oauth/profile"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_REFRESH_MARGIN = 300  # Refresh if token expires within 5 minutes

# Colors
COLOR_SUBDUED = "#c3bae6"  # header details, footer, percentages <=85%, icons
COLOR_DIM = "#61557d"  # bar bg
COLOR_SHADOW = "#322b46"  # shadows for charts

# Progress bar characters
PROGRESS_CHARS = {
    "empty_left": "",
    "empty_mid": "",
    "empty_right": "",
    "full_left": "",
    "full_mid": "",
    "full_right": "",
}

# Hourglass animation frames
HOURGLASS_FRAMES = [
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
]

# Icons
ICONS = {
    "star": "󰛄",
    "bullet": "·",
    "zap": "",
    "allowed_warning": "",
    "rejected": "",
    "delta": "𝚫",
    "epsilon": "𝚺",
}
