"""Configuration loading and hot-reload for scratchpads."""

import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from ..common import CONFIG_DIR


@dataclass
class ScratchpadConfig:
    """Configuration for a single scratchpad."""

    name: str
    command: list[str] | None
    app_id: str | None = None
    title: str | None = None
    width: str | None = None
    height: str | None = None
    position_map: dict[str | None, tuple[str, str] | None] = field(default_factory=dict)

    # Compiled regex patterns (not serialized)
    app_id_regex: re.Pattern[str] | None = field(default=None, repr=False)
    title_regex: re.Pattern[str] | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        if self.app_id and self.app_id.startswith("/"):
            self.app_id_regex = re.compile(self.app_id[1:])
        if self.title and self.title.startswith("/"):
            self.title_regex = re.compile(self.title[1:])


def parse_size(size_str: str) -> tuple[str, str]:
    """Parse size string like '80%x60%' into (width, height)."""
    parts = size_str.split("x")
    if len(parts) != 2:
        print(f"Invalid size format: {size_str}. Using default 80%x60%", file=sys.stderr)
        return "80%", "60%"
    return parts[0].strip(), parts[1].strip()


def parse_position(position_str: str) -> tuple[str, str] | None:
    """Parse position string into (x, y) or None for center."""
    if position_str.lower() == "center":
        return None
    parts = position_str.split(",")
    if len(parts) != 2:
        print(f"Invalid position format: {position_str}. Using center", file=sys.stderr)
        return None
    return parts[0].strip(), parts[1].strip()


def load_scratchpad_configs(config_file: Path | None = None) -> dict[str, ScratchpadConfig]:
    """Load scratchpad configurations from YAML file."""
    if config_file is None:
        config_file = CONFIG_DIR / "scratchpads.yaml"

    raw_config = _load_config_recursive(config_file, set())
    scratchpads = raw_config.get("scratchpads", {})

    result: dict[str, ScratchpadConfig] = {}
    for name, cfg in scratchpads.items():
        width, height = None, None
        if size_str := cfg.get("size"):
            width, height = parse_size(size_str)

        position_map: dict[str | None, tuple[str, str] | None] = {}
        if position_cfg := cfg.get("position"):
            for output, pos in position_cfg.items():
                position_map[output] = parse_position(pos)

        command = cfg.get("command")
        if isinstance(command, str):
            command = [command]

        result[name] = ScratchpadConfig(
            name=name,
            command=command,
            app_id=cfg.get("app_id"),
            title=cfg.get("title"),
            width=width,
            height=height,
            position_map=position_map,
        )

    return result


def _load_config_recursive(config_path: Path, visited: set[Path]) -> dict[str, Any]:
    """Recursively load config with include support."""
    try:
        config_path = config_path.resolve()
    except (OSError, RuntimeError):
        return {}

    if config_path in visited:
        return {}

    if not config_path.exists():
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
                included = _load_config_recursive(include_path, visited)
                if "scratchpads" in included:
                    result["scratchpads"].update(included["scratchpads"])

        if "scratchpads" in config:
            result["scratchpads"].update(config["scratchpads"])

        return result

    except yaml.YAMLError as e:
        # Re-raise YAML parse errors so caller can handle them
        raise ValueError(f"Failed to parse {config_path}: {e}") from e
    except OSError as e:
        print(f"Failed to read config from {config_path}: {e}", file=sys.stderr)
        return {}


def notify_config_error(error: str) -> None:
    """Send critical notification about config error."""
    try:
        subprocess.run(
            ["notify-send", "-u", "critical", "niri-tools config error", error],
            check=False,
        )
    except Exception:
        pass
