{
  inputs,
  lib,
  pkgs,
  ...
}: let
  packageGroups = import ../package-groups {
    inherit inputs pkgs;
  };
in {
  home = {
    username = "maddy";
    homeDirectory = "/home/maddy";
    stateVersion = "26.05";

    packages =
      packageGroups.base
      ++ packageGroups.debugging
      ++ packageGroups.javascript
      ++ packageGroups.neovim
      ++ packageGroups.niri
      ++ packageGroups.shell;

    activation.stow = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${pkgs.stow}/bin/stow --verbose --target="$XDG_CONFIG_HOME" --dir="$XDG_CONFIG_HOME/dotfiles" --restow config
    '';

    shell.enableShellIntegration = true;

    sessionVariables = {
      GIO_EXTRA_MODULES = "${pkgs.dconf.lib}/lib/gio/modules";
    };
  };

  dconf.enable = true;
  targets.genericLinux.enable = true;
  programs.home-manager.enable = true;
}
