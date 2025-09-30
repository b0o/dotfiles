{
  pkgs,
  inputs,
  ...
}:
with pkgs; [
  just # command runner

  stow # manage symlinks of dotfiles

  direnv # load and unload environment variables depending on the current directory
  nix-direnv # A faster, persistent implementation of direnv's use_nix and use_flake, to replace the built-in one.

  nushell # modern shell
  carapace # shell autocompletion
  starship # shell prompt
  atuin # shell history manager
  bat # cat clone with syntax highlighting and Git integration
  fzf # command-line fuzzy finder
  fd # simple, fast and user-friendly alternative to 'find'
  ripgrep # better grep
  hub # GitHub command-line wrapper for git
  gh # GitHub command-line wrapper for git
  eza # enhanced modern 'ls'

  zellij # terminal multiplexer
]
