# dotfiles

Maddison's configuration files, managed with [Nix](https://nixos.org/)

![Screenshot](https://github.com/user-attachments/assets/a7873a70-4b90-4e92-a11c-f262d9653f29)

## Overview

- Compositor: [Niri](https://github.com/YaLTeR/niri)
- Terminal: [Ghostty](https://ghostty.org/)
- Multiplexer: [Zellij](https://zellij.dev/)
- Shell: [Nushell](https://www.nushell.sh/)
- Editor: [Neovim](https://neovim.io/)
- Colorscheme: [Lavi](https://github.com/b0o/lavi.nvim)
- Font: [Pragmasevka Nerd Font](https://github.com/shytikov/pragmasevka)
- Stats:
  - 19,000+ lines of code across 175 files
  - 10,000+ lines of Neovim config (Lua)
  - 4,000+ lines of Nushell config
  - In development since 2015, 1,250+ commits since 2018

## Structure

- [`config/`](config) - Application configurations
  - Shell
    - [`nushell/`](config/nushell) - structured data shell
    - [`starship.toml`](config/starship.toml) - shell prompt
    - [`atuin/`](config/atuin) - shell history sync and search
    - [`carapace/`](config/carapace) - shell completions
    - [`zellij/`](config/zellij) - multiplexer
    - [`zsh/`](config/zsh) - fallback shell
  - Editor
    - [`nvim/`](config/nvim) - Neovim configuration
      - Fully custom, written from scratch
      - 100+ plugins managed with lazy.nvim
      - LSP with 30+ language servers
      - 500+ custom keymaps
      - blink.cmp completion
      - Telescope fuzzy finder
      - Treesitter with textobjects
      - Incline.nvim, lualine.nvim status lines
      - Neogit, Gitsigns, Diffview
      - Nvim-dap debugging, Neotest
      - Supermaven AI completion
  - Terminal
    - [`ghostty/`](config/ghostty) - terminal emulator
  - Desktop
    - [`niri/`](config/niri) - wayland compositor
    - [`mako/`](config/mako) - notification daemon
    - [`waybar/`](config/waybar) - status bar
    - [`wlr-which-key/`](config/wlr-which-key) - keybinding hints
    - [`rofi/`](config/rofi) - application launcher
  - Dev Tools
    - [`git/`](config/git) - global git configuration
    - [`opencode/`](config/opencode) - AI coding assistant
  - Utilities
    - [`bat/`](config/bat) - cat with syntax highlighting
    - [`feh/`](config/feh) - image viewer
    - [`htop/`](config/htop) - process monitor
    - [`satty/`](config/satty) - screenshot annotation
    - [`vivid/`](config/vivid) - LS_COLORS generator
    - [`zathura/`](config/zathura) - document viewer
- [`nix/`](nix) - [NixOS](https://nixos.org/) and [Home Manager](https://github.com/nix-community/home-manager) configurations
  - [`home/`](nix/home) - Home Manager configurations
  - [`hosts/`](nix/hosts) - NixOS host configurations
  - [`modules/`](nix/modules) - Reusable NixOS modules
  - [`profiles/`](nix/profiles) - Package profiles
  - [`overlays/`](nix/overlays) - Nixpkgs overlays
  - [`pkgs/`](nix/pkgs) - Custom packages
- [`flake.nix`](flake.nix) - Nix flake entry point
- [`justfile`](justfile) - Task runner commands

## Installation

### [Home Manager](https://github.com/nix-community/home-manager)

```sh
# using my nushell helper
hm switch

# or standard home-manager command
home-manager switch --flake .#<config>
```

**Configs**:

- [`arch-maddy`](nix/home/arch-maddy.nix) - Arch Linux user environment

### [NixOS](https://nixos.org/)

```sh
nixos-rebuild switch --flake .#<host>
```

**Hosts**:

- [`boonix`](nix/hosts/boonix) - desktop workstation with ZFS

### [flakey-profile](https://github.com/lf-/flakey-profile)

```sh
# using my nushell helper
fp switch

# or standard command
nix run .#<profile>.switch
```

**Profiles**:

- [`dev`](nix/profiles/dev.nix) - full development environment
- [`minimal`](nix/profiles/minimal.nix) - base packages only

### Standalone

Symlink configs manually with [GNU Stow](https://www.gnu.org/software/stow/):

```sh
just stow
```

## License

MIT
