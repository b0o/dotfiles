{
  description = "Maddison's Dotfiles";

  inputs = {
    # Nix
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flakey-profile.url = "github:lf-/flakey-profile";

    # Neovim
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    neovim-nightly-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flakey-profile,
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
      nixos-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = [./nix/hosts/boonix];
      };
    };
  };
}
