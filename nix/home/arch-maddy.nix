{
  inputs,
  lib,
  pkgs,
  ...
}: let
  packageGroups = import ../package-groups {
    inherit inputs pkgs;
  };
  home = {
    username = "maddy";
    homeDirectory = "/home/maddy";
  };
in {
  home =
    home
    // {
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

  programs = {
    home-manager.enable = true;
    nix-search-tv.enable = true;

    ghostty = {
      enable = true;
      enableBashIntegration = false;
      enableZshIntegration = false;
      enableFishIntegration = false;
      systemd.enable = true;
    };
  };

  xdg.configFile."ghostty/config".enable = false; # prevent home-manager from touching this
  };
}
