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
]
