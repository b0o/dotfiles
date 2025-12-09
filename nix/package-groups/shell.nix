{
  pkgs,
  inputs,
  ...
}:
with pkgs; [
  # Shells
  bash # bourne-again shell
  fish # friendly interactive shell
  zsh # z-shell
  nushell # modern shell

  # Nushell plugins
  nushellPlugins.skim

  # Terminal multiplexer
  zellij # terminal workspace manager

  # Task automation
  just # command runner

  # Dotfiles management
  stow # manage symlinks of dotfiles

  # Environment management
  direnv # load/unload env vars depending on current directory
  nix-direnv # faster implementation of direnv's use_nix and use_flake
  # bash-env-nushell # load bash environment variables in nushell

  # Shell enhancements
  starship # customizable shell prompt
  atuin # shell history manager with sync
  carapace # multi-shell completion generator
  vivid # themeable LS_COLORS generator
  usage # completions for mise

  # Modern CLI utilities
  bat # cat clone with syntax highlighting and Git integration
  eza # modern replacement for 'ls'
  fzf # command-line fuzzy finder
  skim # fuzzy finder written in Rust
  fd # simple, fast alternative to 'find'
  ripgrep # faster grep alternative

  # Git tools
  hub # GitHub CLI wrapper for git
  gh # official GitHub CLI

  # AI
  pkgs.opencode-b0o
]
