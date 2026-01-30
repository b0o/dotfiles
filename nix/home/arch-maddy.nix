{
  config,
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
  sops = {
    defaultSopsFile = ../../secrets.yaml;
    # NOTE: You must manually create/place the age key file before bootstrapping
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    # TODO: can we organize this better so that all gost config
    # is in one location rather than spread across different attrsets?
    # [{"addr": string, "chain"?: string, "prefer"?: "ipv4" | "ipv6", "clientIp"?: string, "ttl"?: duration, "timeout"?: duration}]
    # https://gost.run/en/reference/configuration/file/#nameserver
    secrets."gost/nameservers" = {};

    templates."gost-config.json".content = ''
      {
        "services": [
          {
            "name": "socks-proxy",
            "addr": ":1080",
            "handler": {"type": "socks5"},
            "listener": {"type": "tcp"},
            "resolver": "socks-proxy"
          }
        ],
        "resolvers": [
          {
            "name": "socks-proxy",
            "nameservers": ${config.sops.placeholder."gost/nameservers"}
          }
        ]
      }
    '';
  };

  systemd.user.services.gost = {
    Unit = {
      Description = "SOCKS5 proxy with unfiltered DNS";
      After = ["sops-nix.service"];
      Requires = ["sops-nix.service"];
    };
    Service = {
      ExecStart = "${pkgs.gost}/bin/gost -C ${config.sops.templates."gost-config.json".path}";
      Restart = "on-failure";
    };
    Install = {WantedBy = ["default.target"];};
  };
}
