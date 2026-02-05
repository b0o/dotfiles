# Base profile: common settings for all home-manager hosts
{ pkgs, ... }:
{
  imports = [
    ../modules/stow.nix
  ];

  home.shell.enableShellIntegration = true;

  dconf.enable = true;

  programs = {
    home-manager.enable = true;
    nix-search-tv.enable = true;
  };
}
