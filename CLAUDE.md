# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS dotfiles repository with configurations for Nushell, Neovim, Git, and other development tools. The repository uses Nix flakes for package management and deployment, with a modular structure for organizing configurations.

## Architecture

### Core Components

**Nix Infrastructure**
- `flake.nix` - Main flake defining packages, profiles, and NixOS configurations
- `nix/` - Directory containing Nix configurations
  - `profiles/` - Flakey-profile definitions (`dev.nix`, `minimal.nix`)
  - `package-groups/` - Categorized package lists (`base.nix`, `shell.nix`, `neovim.nix`)
  - `overlays/` - Custom package overlays and modifications
  - `pkgs/` - Custom package definitions
  - `hosts/` - NixOS host configurations (e.g., `boonix`)

**Shell Configuration (`config/nushell/`)**
- `config.nu` - Main Nushell configuration with environment setup
- `hooks.nu` - Dynamic hook initialization system for shell integrations (atuin, starship, carapace)
- `autoload/` - Modular function library automatically loaded by Nushell:
  - `comark.nu` - Bookmark management system with symlink-based storage
  - `nix.nu` - Flakey-profile wrapper commands (`fp`)
  - `git.nu`, `git/` - Git utilities and worktree management
  - `platform/` - OS-specific utilities
  - `xtras/` - Additional utilities which can be executed using `xtras <command>`

**Neovim Configuration (`config/nvim/`)**
- `init.lua` - Entry point using lazy.nvim plugin manager
- `lua/user/` - Custom configuration modules
- Uses neovim-nightly-overlay from flake inputs
- Configured with tree-sitter, LSPs (nil, alejandra, statix for Nix; just-lsp)

**Git Configuration (`config/git/`)**
- Modular config structure with includes:
  - `config` - Main configuration
  - `alias.config` - Git aliases
  - `delta.config` - Delta (diff) configuration
  - `local.config` - Machine-specific settings (gitignored)
- Uses delta as pager, histogram diff algorithm, zdiff3 merge conflict style

### Nix Flake Commands

**Build a profile:**
```bash
nix build .#profile.dev
nix build .#profile.minimal
```

**Switch to a profile:**
```bash
nix run .#profile.dev.switch
```

**Update flake inputs:**
```bash
nix flake update
```

**Enter development shell:**
```bash
nix develop
```

### Flakey-Profile Management (Nushell)

The `fp` command provides a wrapper around flakey-profile operations:

```nushell
fp build         # or `fp b` - Build profile
fp switch        # or `fp sw` - Activate profile
fp rollback      # or `fp rb` - Rollback to previous
fp update        # or `fp up` - Update flake.lock and switch
fp develop       # or `fp dev` - Enter dev shell
```

Options:
- `--profile (-p)` - Specify profile name (default: `$env.NIX_PROFILE` or "dev")
- `--dir (-d)` - Specify base directory (default: `$env.DOTFILES_HOME`)

### Hooks System

Nushell uses a custom hooks system (`hooks.nu`) for shell integrations:

```nushell
hooks use {
  <name>: {
    enabled: bool      # Enable/disable hook
    cmd: list<string>  # Command to initialize
    depends?: string   # Optional dependency check
    env?: record       # Environment variables
  }
}
```

Hooks are cached in `$nu.data-dir/vendor/autoload/` and auto-regenerated on config changes.

**Manage hooks:**
- `hooks clean <name>` - Clean specific hook
- `hooks clean-all` - Clean all hooks

### Stow Deployment

Deploy configurations using GNU Stow:

```bash
just stow
# or manually:
stow --verbose --target="$XDG_CONFIG_HOME" --restow config
```

This creates symlinks from `~/.config/` to `config/` subdirectories.

## Development Workflow

### NixOS Configuration Changes

1. Modify relevant files in `nix/` or `config/`
2. Test profile build: `nix build .#profile.dev`
3. Switch if successful: `nix run .#profile.dev.switch`
4. For flake updates: `fp update` (updates lock and switches)

### Nushell Function Development

1. Add/modify functions in `config/nushell/autoload/*.nu`
2. Use `export def` for exported functions
3. Follow naming conventions:
   - `def --env` for functions that modify environment (cd, etc.)
   - Use comma suffix for bookmark commands (`m,`, `cd,`, `f,`)
4. Functions are auto-loaded; restart shell or `use` file to test

### Neovim Configuration Changes

1. Edit files in `config/nvim/lua/user/`
2. Lazy.nvim auto-loads on nvim startup
3. LSPs and tools are managed in `nix/package-groups/neovim.nix`

## Git Workflow

- Default branch: `main`
- Commits are GPG-signed by default
- Uses histogram diff algorithm
- Delta provides enhanced diff viewing
- Rebase autosquash enabled
- Pull is set to fast-forward only

## Key Tools

**Shell:** Nushell (primary), with bash/zsh/fish available
**Terminal:** Zellij (workspace manager)
**Fuzzy finder:** FZF with bat/eza previews
**File navigation:** eza (ls), fd (find), ripgrep (grep)
**Version control:** git with hub and gh
**History:** atuin (synced shell history)
**Completions:** carapace (multi-shell completions with bridge support)
**Prompt:** starship

## Environment Variables

Key environment variables (set in `config/nushell/config.nu`):
- `$env.DOTFILES_HOME` - Dotfiles directory (`~/.config/dotfiles`)
- `$env.GIT_PROJECTS_DIR` - Git projects location (`~/git`)
- `$env.NIX_PROFILE` - Active Nix profile name
