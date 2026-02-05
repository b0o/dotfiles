{
  description = "Maddison's Dotfiles";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Nix/NixOS
    flakey-profile.url = "github:lf-/flakey-profile";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixGL = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty
    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Lavi colorscheme
    lavi = {
      url = "github:b0o/lavi.nvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim
    # TODO: Switch back to nix-community once PR #1166 is merged
    # See: https://github.com/nix-community/neovim-nightly-overlay/issues/1164
    neovim-nightly-overlay.url = "github:Prince213/neovim-nightly-overlay/push-nttnuzwkprtq";
    blink-cmp = {
      url = "github:saghen/blink.cmp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Language Support
    topiary-nushell = {
      url = "github:blindFS/topiary-nushell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wlr-which-key-b0o = {
      url = "github:b0o/wlr-which-key/b0o";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets Management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust (for zellij build)
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Misc
    opencode = {
      url = "github:anomalyco/opencode/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        # "x86_64-darwin"
      ];
    in
    rec {
      overlays = {
        default = import ./nix/overlays { inherit inputs; };
        ghostty = inputs.ghostty.overlays.releasefast;
        inherit (inputs.niri.overlays) niri;
      };

      devShells = forAllSystems (system: {
        default = legacyPackages.${system}.callPackage ./shell.nix { };
      });

      legacyPackages = forAllSystems (
        system:
        import inputs.nixpkgs {
          inherit system;
          overlays = builtins.attrValues overlays;

          # NOTE: Using `nixpkgs.config` in NixOS config won't work
          # Instead, set nixpkgs configs here
          # (https://nixos.org/manual/nixpkgs/stable/#idm140737322551056)
          config.allowUnfree = true;
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = legacyPackages."${system}";
        in
        {
          profile.dev = pkgs.callPackage ./nix/profiles/dev.nix { inherit pkgs inputs; };
          profile.minimal = pkgs.callPackage ./nix/profiles/minimal.nix { inherit pkgs inputs; };
        }
      );

      nixosConfigurations = {
        boonix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./nix/nixos/hosts/boonix
          ];
        };
      };

      homeConfigurations = {
        arch-maddy = home-manager.lib.homeManagerConfiguration {
          pkgs = legacyPackages."x86_64-linux";
          extraSpecialArgs = { inherit inputs; };
          modules = [
            ./nix/home/hosts/arch-maddy.nix
            inputs.sops-nix.homeManagerModules.sops
            inputs.lavi.homeManagerModules.lavi
          ];
        };
      };
    };
}
