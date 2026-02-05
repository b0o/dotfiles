# Stow activation for managing dotfiles
# Runs stow on home-manager activation to symlink config/ directory
{ lib, pkgs, ... }:
{
  home.activation.stow = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.stow}/bin/stow --target="$XDG_CONFIG_HOME" --dir="$XDG_CONFIG_HOME/dotfiles" --restow config
  '';
}
