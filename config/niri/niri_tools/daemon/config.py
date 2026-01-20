"""Configuration loading and hot-reload for scratchpads."""

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from ..common import CONFIG_DIR
from .notify import NotifyLevel


@dataclass
class DaemonSettings:
    """Global daemon settings."""

    notify_level: NotifyLevel = NotifyLevel.ALL
    watch_config: bool = True


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
        print(
            f"Invalid size format: {size_str}. Using default 80%x60%", file=sys.stderr
        )
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


@dataclass
class LoadedConfig:
    """Result of loading configuration."""

    settings: DaemonSettings
    scratchpads: dict[str, ScratchpadConfig]
    config_files: list[Path]
    warnings: list[str]


def load_config(config_file: Path | None = None) -> LoadedConfig:
    """Load daemon configuration from YAML file."""
    if config_file is None:
        config_file = CONFIG_DIR / "scratchpads.yaml"

    loaded_files: list[Path] = []
    warnings: list[str] = []
    raw_config = _load_config_recursive(config_file, set(), loaded_files, warnings)

    # Parse daemon settings
    settings = _parse_daemon_settings(raw_config.get("settings", {}))

    # Parse scratchpads
    scratchpads = _parse_scratchpads(raw_config.get("scratchpads", {}))

    return LoadedConfig(
        settings=settings,
        scratchpads=scratchpads,
        config_files=loaded_files,
        warnings=warnings,
    )


_NOTIFY_LEVEL_MAP = {level.name.lower(): level for level in NotifyLevel}


def _parse_daemon_settings(settings_cfg: dict[str, Any]) -> DaemonSettings:
    """Parse daemon settings from config."""
    notify_level = NotifyLevel.ALL
    if notify_str := settings_cfg.get("notify"):
        level = _NOTIFY_LEVEL_MAP.get(notify_str.lower())
        if level is not None:
            notify_level = level
        else:
            valid = ", ".join(_NOTIFY_LEVEL_MAP.keys())
            print(
                f"Invalid notify level: {notify_str}. Valid: {valid}", file=sys.stderr
            )

    watch_config = True
    if "watch" in settings_cfg:
        watch_config = bool(settings_cfg["watch"])

    return DaemonSettings(notify_level=notify_level, watch_config=watch_config)


def _parse_scratchpads(
    scratchpads_cfg: dict[str, Any],
) -> dict[str, ScratchpadConfig]:
    """Parse scratchpad configurations."""
    result: dict[str, ScratchpadConfig] = {}
    for name, cfg in scratchpads_cfg.items():
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


def _load_config_recursive(
    config_path: Path,
    visited: set[Path],
    loaded_files: list[Path],
    warnings: list[str],
) -> dict[str, Any]:
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
    loaded_files.append(config_path)

    try:
        with open(config_path) as f:
            config = yaml.safe_load(f)

        if not config:
            return {}

        result: dict[str, Any] = {"settings": {}, "scratchpads": {}}

        includes = config.get("include", [])
        if includes:
            if not isinstance(includes, list):
                includes = [includes]
            for include_path_str in includes:
                include_path = (config_path.parent / include_path_str).resolve()
                if not include_path.exists():
                    warnings.append(f"Include file not found: {include_path}")
                    continue
                included = _load_config_recursive(
                    include_path, visited, loaded_files, warnings
                )
                if "settings" in included:
                    result["settings"].update(included["settings"])
                if "scratchpads" in included:
                    result["scratchpads"].update(included["scratchpads"])

        # Main file settings override included settings
        if "settings" in config:
            result["settings"].update(config["settings"])
        if "scratchpads" in config:
            result["scratchpads"].update(config["scratchpads"])

        return result

    except yaml.YAMLError as e:
        # Re-raise YAML parse errors so caller can handle them
        raise ValueError(f"Failed to parse {config_path}: {e}") from e
    except OSError as e:
        raise ValueError(f"Failed to read {config_path}: {e}") from e
