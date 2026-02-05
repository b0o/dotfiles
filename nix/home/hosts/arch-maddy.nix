# Home-manager configuration for Arch Linux (non-NixOS)
{
  config,
  inputs,
  pkgs,
  ...
}:
let
  packageGroups = import ../../package-groups { inherit inputs pkgs; };
in
{
  imports = [
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../modules/gost.nix
  ];

  home = {
    username = "maddy";
    homeDirectory = "/home/${config.home.username}";
    stateVersion = "26.05";

    packages =
      packageGroups.base
      ++ packageGroups.debugging
      ++ packageGroups.javascript
      ++ packageGroups.neovim
      ++ packageGroups.security
      ++ packageGroups.shell
      ++ packageGroups.niri.other
      ++ (map config.lib.nixGL.wrap packageGroups.niri.graphical);
  };

  # Arch-specific: nixGL for GPU acceleration
  targets.genericLinux = {
    enable = true;
    nixGL = {
      packages = pkgs.nixgl;
      defaultWrapper = "nvidia";
      installScripts = [
        "nvidia"
        "mesa"
      ];
    };
  };

  # Override ghostty package with nixGL wrapper
  programs.ghostty.package = config.lib.nixGL.wrap pkgs.ghostty;

  # Sops configuration
  sops = {
    defaultSopsFile = ../../../secrets.yaml;
    # NOTE: You must manually create/place the age key file before bootstrapping
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  };
}
