# dotfiles

Personal configuration files managed with [Nix](https://nixos.org/)

![Screenshot](https://github.com/user-attachments/assets/a7873a70-4b90-4e92-a11c-f262d9653f29)

## Components

- [`config/`](config) - Application configurations (symlinked via Stow)
- [`nix/`](nix) - [NixOS](https://nixos.org/) and [Home Manager](https://github.com/nix-community/home-manager) configurations
- [`flake.nix`](flake.nix) - Nix flake entry point
- [`justfile`](justfile) - Task runner commands

### Application Configs

- Colorscheme
  - [lavi](https://github.com/b0o/lavi.nvim) - my custom colorscheme
- [`config/`](config)
  - Shell
    - [`nushell/`](config/nushell) - structured data shell
    - [`starship.toml`](config/starship.toml) - shell prompt
    - [`atuin/`](config/atuin) - shell history sync and search
    - [`carapace/`](config/carapace) - shell completions
    - [`zsh/`](config/zsh) - fallback shell
  - Editor
    - [`nvim/`](config/nvim) - neovim
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

### Nix Structure

- `nix/home/` - Home Manager configurations
- `nix/hosts/` - NixOS host configurations
- `nix/modules/` - Reusable NixOS modules
- `nix/profiles/` - Package profiles
- `nix/overlays/` - Nixpkgs overlays
- `nix/pkgs/` - Custom packages

## Setup

### [Home Manager](https://github.com/nix-community/home-manager)

```sh
# using my nushell helper
hm switch

# or standard home-manager command
home-manager switch --flake .#<config>
```

**Configs**:

- `arch-maddy` - Arch Linux user environment

### [NixOS](https://nixos.org/)

```sh
nixos-rebuild switch --flake .#<host>
```

**Hosts**:

- `boonix` - desktop workstation with ZFS

### [flakey-profile](https://github.com/lf-/flakey-profile)

```sh
# using my nushell helper
fp switch

# or standard command
nix run .#<profile>.switch
```

**Profiles**:

- `dev` - full development environment
- `minimal` - base packages only

### Standalone

Symlink configs manually with [GNU Stow](https://www.gnu.org/software/stow/):

```sh
just stow
```

## License

MIT
