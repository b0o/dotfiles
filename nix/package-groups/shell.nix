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

  # Terminal multiplexer
  zellij # terminal workspace manager

  # Task automation
  just # command runner

  # Dotfiles management
  stow # manage symlinks of dotfiles

  # Environment management
  direnv # load/unload env vars depending on current directory
  nix-direnv # faster implementation of direnv's use_nix and use_flake

  # Shell enhancements
  starship # customizable shell prompt
  atuin # shell history manager with sync
  carapace # multi-shell completion generator
  vivid # themeable LS_COLORS generator

  # Modern CLI utilities
  bat # cat clone with syntax highlighting and Git integration
  eza # modern replacement for 'ls'
  fzf # command-line fuzzy finder
  fd # simple, fast alternative to 'find'
  ripgrep # faster grep alternative

  # Git tools
  hub # GitHub CLI wrapper for git
  gh # official GitHub CLI
]
