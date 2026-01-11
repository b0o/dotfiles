{inputs, ...}: let
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  modifications = final: prev: {
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${final.stdenv.hostPlatform.system}.default;
    ghostty = inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;

    # TODO: remove once https://github.com/NixOS/nixpkgs/pull/466454 is merged
    # Bump nu_plugin_skim to v0.21.0 for nushell 0.109.x compatibility
    nushellPlugins =
      prev.nushellPlugins
      // {
        skim = let
          version = "0.21.0";
          src = final.fetchFromGitHub {
            owner = "idanarye";
            repo = "nu_plugin_skim";
            rev = "v${version}";
            hash = "sha256-cFk+B2bsXTjt6tQ/IVVefkOTZKjvU1hiirN+UC6xxgI=";
          };
          cargoHash = "sha256-eNT4NfSlyKuVUlOrmSNoimJJ1zU88prSemplbBWcyag=";
        in
          prev.nushellPlugins.skim.overrideAttrs (oldAttrs: {
            inherit version src;
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "${oldAttrs.pname}-${version}-vendor";
              hash = cargoHash;
            };
          });
      };
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [
    additions
    modifications
    (import ./charles.nix)
    (import ./opencode.nix {inherit inputs;})
  ]
