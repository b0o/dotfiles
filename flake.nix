{
  description = "Maddison's Dotfiles";

  inputs = {
    # Nix/NixOS
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flakey-profile.url = "github:lf-/flakey-profile";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty
    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nushell
    nushell-nightly = {
      url = "github:JoaquinTrinanes/nushell-nightly-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bash-env-nushell = {
      url = "github:tesujimath/bash-env-nushell";
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

    # Misc
    opencode = {
      url = "github:b0o/opencode/b0o";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opentui-src = {
      url = "github:b0o/opentui/b0o";
      flake = false;
    };
    opentui-spinner-src = {
      url = "github:msmps/opentui-spinner";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flakey-profile,
    home-manager,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;
    forAllSystems = lib.genAttrs [
      "x86_64-linux"
      # "x86_64-darwin"
    ];
  in rec {
    overlays = {
      default = import ./nix/overlays {inherit inputs;};
      neovim = inputs.neovim-nightly-overlay.overlays.default;
      nushell = inputs.nushell-nightly.overlays.default;
      inherit (inputs.niri.overlays) niri;
    };

    devShells = forAllSystems (system: {
      default = legacyPackages.${system}.callPackage ./shell.nix {};
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

    packages = forAllSystems (system: let
      pkgs = legacyPackages."${system}";
    in {
      profile.dev =
        pkgs.callPackage ./nix/profiles/dev.nix {inherit pkgs inputs;};
      profile.minimal =
        pkgs.callPackage ./nix/profiles/minimal.nix {inherit pkgs inputs;};
    });

    nixosConfigurations = {
      boonix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          ./nix/hosts/boonix
        ];
      };
    };

    homeConfigurations = {
      arch-maddy = home-manager.lib.homeManagerConfiguration {
        pkgs = legacyPackages."x86_64-linux";
        extraSpecialArgs = {inherit inputs;};
        modules = [./nix/home/arch-maddy.nix];
      };
    };
  };
}
