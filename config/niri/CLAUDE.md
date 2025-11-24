# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a personal Niri window manager configuration directory. Niri is a scrollable-tiling Wayland compositor. The configuration includes:

- Main configuration file (`config.kdl`) written in KDL format
- Custom Python scripts for automation and monitoring
- Dual monitor setup with specific display configurations

## Development Commands

### Python Scripts
- **Run Python scripts**: Use `uv run python <script_name>` (dependencies managed via pyproject.toml)
- **Test configuration**: `niri validate` (validates KDL configuration syntax)
- **Configuration reloading**: Niri automatically reloads config.kdl on file changes
- **Check python code with ruff and basedpyright**: Lint and type-check Python scripts using these tools

### Niri Commands
- **Check running instance**: `niri msg version`
- **List windows**: `niri msg -j windows` (JSON output for scripting)
- **Monitor events**: `niri msg -j event-stream` (used by stream_monitor.py)
- **Get workspaces**: `niri msg -j workspaces`
- **Validate config**: `niri validate`

## Architecture

### Configuration Structure
- `config.kdl`: Main Niri configuration file with window management, keybindings, and layout settings
- `scratchpads.yaml`: Centralized configuration for all scratchpad windows
- `niri_tools/stream_monitor.py`: Event monitoring daemon that handles window urgency notifications
- `niri_tools/scratchpad.py`: Scratchpad management system for floating windows

### Key Components

#### Configuration (`config.kdl`)
- Dual monitor setup (DP-1 and DP-2, both 4K@60Hz)
- Custom keybindings using Mod (Super) key combinations
- Window rules for specific applications (Firefox PiP, password managers)
- Layout configuration with focus rings, borders, and shadows
- Integration with external tools (waybar, swaybg, brightness control)

#### Event Monitoring (`stream_monitor.py`)
- Extensible event handling system using abstract base classes
- WindowUrgencyHandler: Manages persistent notifications for urgent windows
- Uses `niri msg event-stream` for real-time compositor events
- Notification management via notify-send with proper cleanup

#### Scratchpad System (`scratchpad.py` and `scratchpads.yaml`)
- YAML-based configuration for all scratchpad windows
- Each scratchpad defines: app_id/title_pattern, command, size, and per-monitor positions
- Commands: `toggle <name>` (show/hide scratchpad), `hide` (hide focused), `list` (show all configured)
- Automatic window detection and floating window management
- State persistence across restarts

### Script Dependencies
Python scripts require:
- Python 3.13+
- uv package manager for environment management
- Dependencies installed via `uv pip install -e .` (see pyproject.toml)
- Access to `niri msg` command
- notify-send for notifications (stream_monitor.py)
- PyYAML for configuration parsing (scratchpad.py)

## Configuration Notes

- KDL format is used for configuration (not TOML or JSON)
- Scripts are automatically started via `spawn-at-startup` in config.kdl
- Window management uses column-based tiling with scrolling workspaces
- Custom color themes with purple/blue gradients
- Integration with system audio controls and brightness utilities

## Documentation Resources

- Refer to the niri wiki for documentation: https://github.com/YaLTeR/niri/tree/main/wiki